import Foundation
import MonitorCore

/// Shares the default report observation across windows and the menu without owning imports.
actor SharedReportRuntime: SessionExplorerRuntime {
    private let runtime: any SessionExplorerRuntime
    private var observers: [UUID: AsyncThrowingStream<UsageSnapshot, Error>.Continuation] = [:]
    private var observation: Task<Void, Never>?
    private var generation = UUID()
    private var latest: UsageSnapshot?

    init(runtime: any SessionExplorerRuntime) { self.runtime = runtime }

    func importDirectory(_ directory: URL) async throws -> ImportSummary {
        try await runtime.importDirectory(directory)
    }

    func snapshot(query: UsageQuery) async throws -> UsageSnapshot {
        try await runtime.snapshot(query: query)
    }

    func snapshots(query: UsageQuery) async -> AsyncThrowingStream<UsageSnapshot, Error> {
        // Nondefault queries retain their own stream until period selection is shared in SM-301.
        guard query.since == nil, query.until == nil, query.timeZoneIdentifier == "UTC" else {
            return await runtime.snapshots(query: query)
        }
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<UsageSnapshot, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        observers[id] = continuation
        if let latest { continuation.yield(latest) }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        if observation == nil {
            let generation = generation
            let runtime = runtime
            observation = Task { [weak self] in
                let source = await runtime.snapshots(query: query)
                do {
                    for try await value in source {
                        guard !Task.isCancelled else { break }
                        await self?.publish(value, generation: generation)
                    }
                    await self?.finish(generation: generation, error: nil)
                } catch {
                    await self?.finish(generation: generation, error: error)
                }
            }
        }
        return stream
    }

    private func publish(_ value: UsageSnapshot, generation: UUID) {
        guard generation == self.generation else { return }
        latest = value
        for observer in observers.values { observer.yield(value) }
    }

    private func finish(generation: UUID, error: (any Error)?) {
        guard generation == self.generation else { return }
        let completed = Array(observers.values)
        reset()
        for observer in completed { observer.finish(throwing: error) }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
        if observers.isEmpty { reset() }
    }

    private func reset() {
        observation?.cancel()
        observation = nil
        generation = UUID()
        latest = nil
        observers.removeAll()
    }

    deinit { observation?.cancel() }
}
