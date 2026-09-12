import Foundation
import MonitorCore

/// Owns one event stream and serial reconciliation loop. Call stop(), or cancel waitUntilStopped(), to close it.
public actor SessionWatch {
    /// One consumer receives the latest status; slow consumers do not accumulate an unbounded event log.
    public nonisolated let updates: AsyncStream<WatchStatus>
    public private(set) var status = WatchStatus()
    private let continuation: AsyncStream<WatchStatus>.Continuation
    private let source: any FileEventSource
    private let importer: @Sendable () async throws -> ImportSummary
    private let lease: ImportLock?
    private let options: WatchOptions
    private var retryDelay: Duration
    private var worker: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var timerGeneration = 0
    private var sourceGeneration = 0
    private var pending = false
    private var needsReattach = false
    private var paused = false
    private var stopping = false
    private var closed = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    init(source: any FileEventSource, options: WatchOptions, lease: ImportLock? = nil,
         importer: @escaping @Sendable () async throws -> ImportSummary) throws {
        try options.validate()
        self.lease = lease
        self.source = source
        self.options = options
        self.importer = importer
        retryDelay = options.retryDelay
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    func start() throws {
        try attach()
        pending = true
        launch()
    }

    /// No new import starts after acknowledgement until resume; an existing import is allowed to finish.
    public func pause() async {
        guard !closed, !stopping else { return }
        paused = true
        pending = true
        cancelTimer()
        await worker?.value
        if paused, !closed, !stopping { publish(.paused) }
    }

    /// Reconciles even if events were dropped or no changes were queued while paused.
    public func resume() {
        guard paused, !closed, !stopping else { return }
        paused = false
        pending = true
        retryDelay = options.retryDelay
        launch()
    }

    public func stop() async {
        guard !closed else { return }
        if stopping {
            await waitForStop()
            return
        }
        stopping = true
        cancelTimer()
        sourceGeneration += 1
        source.stop()
        worker?.cancel()
        await worker?.value
        worker = nil
        lease?.release()
        closed = true
        publish(.stopped)
        continuation.finish()
        let waiters = stopWaiters
        stopWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    /// Cancellation stops the actual importer task and waits for its cleanup before returning.
    public func waitUntilStopped() async {
        await withTaskCancellationHandler {
            await waitForStop()
        } onCancel: {
            Task { await self.stop() }
        }
    }

    private func waitForStop() async {
        guard !closed else { return }
        await withCheckedContinuation { stopWaiters.append($0) }
    }

    private func attach() throws {
        sourceGeneration += 1
        let generation = sourceGeneration
        try source.start { [weak self] event in
            Task { await self?.changed(event, generation: generation) }
        }
    }

    private func changed(_ event: FileWatchEvent, generation: Int) {
        guard generation == sourceGeneration, !closed, !stopping else { return }
        pending = true
        needsReattach = needsReattach || event.needsReattach
        if !paused, worker == nil { schedule(after: options.debounce) }
    }

    // The first event opens a fixed debounce window. Later events cannot postpone it indefinitely.
    private func schedule(after delay: Duration) {
        guard timer == nil, !paused, !closed, !stopping else { return }
        timerGeneration += 1
        let generation = timerGeneration
        timer = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                await self?.timerFired(generation)
            } catch { /* Cancellation invalidates this debounce/retry window. */ }
        }
    }

    private func cancelTimer() {
        timerGeneration += 1
        timer?.cancel()
        timer = nil
    }

    private func timerFired(_ generation: Int) {
        guard generation == timerGeneration else { return }
        timer = nil
        launch()
    }

    private func launch() {
        guard pending, worker == nil, !paused, !closed, !stopping else { return }
        cancelTimer()
        if needsReattach {
            source.stop()
            do {
                try attach()
                needsReattach = false
            } catch {
                complete(.failure(error))
                return
            }
        }
        pending = false
        publish(.importing)
        worker = Task { [weak self, importer] in
            do {
                let summary = try await importer()
                await self?.complete(.success(summary))
            } catch {
                await self?.complete(.failure(error))
            }
        }
    }

    private func complete(_ result: Result<ImportSummary, Error>) {
        worker = nil
        guard !closed, !stopping else { return }
        switch result {
        case .success(let summary):
            status.completedImports += 1
            status.lastImport = summary
            status.error = nil
            retryDelay = options.retryDelay
            publish(paused ? .paused : .watching)
            if pending { schedule(after: options.debounce) }
        case .failure(let error):
            pending = true
            needsReattach = true
            status.error = error.localizedDescription
            publish(paused ? .paused : .recovering)
            schedule(after: retryDelay)
            retryDelay += min(retryDelay, options.maximumRetryDelay - retryDelay)
        }
    }

    private func publish(_ phase: WatchStatus.Phase) {
        status.phase = phase
        continuation.yield(status)
    }

    deinit {
        timer?.cancel()
        worker?.cancel()
        source.stop()
        let worker = worker
        let lease = lease
        Task {
            await worker?.value
            lease?.release()
        }
        continuation.finish()
    }
}
