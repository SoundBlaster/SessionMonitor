import Foundation
import MonitorCore
@testable import MonitorRuntime
import Testing

struct SessionWatchTests {
    @Test func registrationPrecedesInitialImportAndChangesDuringImportRemainPending() async throws {
        let source = FakeWatchSource()
        let probe = WatchImportProbe(blocked: true)
        let watch = try makeWatch(source, probe)
        defer { Task { await watch.stop() } }
        try await watch.start()
        try await eventually { await probe.calls == 1 }
        #expect(await probe.registeredBeforeImport)
        source.emit()
        try await Task.sleep(for: .milliseconds(30))
        await probe.release()
        try await eventually { await watch.status.completedImports == 2 }
        await watch.stop()
    }

    @Test func burstUsesOneBoundedDebounceWindow() async throws {
        let source = FakeWatchSource()
        let probe = WatchImportProbe()
        let watch = try makeWatch(source, probe, debounce: .milliseconds(100))
        defer { Task { await watch.stop() } }
        try await watch.start()
        try await eventually { await watch.status.completedImports == 1 }
        for _ in 0..<100 { source.emit() }
        try await eventually { await watch.status.completedImports == 2 }
        try await Task.sleep(for: .milliseconds(150))
        #expect(await probe.calls == 2)
        await watch.stop()
    }

    @Test func pauseJoinsImportAndResumeReconcilesWithoutEvents() async throws {
        let source = FakeWatchSource()
        let probe = WatchImportProbe(blocked: true)
        let watch = try makeWatch(source, probe)
        defer { Task { await watch.stop() } }
        try await watch.start()
        try await eventually { await probe.calls == 1 }
        let acknowledged = CompletionFlag()
        let pausing = Task { await watch.pause(); await acknowledged.finish() }
        try await Task.sleep(for: .milliseconds(40))
        #expect(await acknowledged.finished == false)
        await probe.release()
        try await eventually { await acknowledged.finished }
        await pausing.value
        #expect(await watch.status.phase == .paused)
        try await Task.sleep(for: .milliseconds(80))
        #expect(await probe.calls == 1)
        await watch.resume()
        try await eventually { await watch.status.completedImports == 2 }
        await watch.stop()
    }

    @Test(arguments: [false, true])
    func stopAndCancelledWaiterJoinImporter(cancelWaiter: Bool) async throws {
        let source = FakeWatchSource()
        let probe = WatchImportProbe(blocked: true)
        let watch = try makeWatch(source, probe)
        defer { Task { await watch.stop() } }
        try await watch.start()
        try await eventually { await probe.calls == 1 }
        let acknowledged = CompletionFlag()
        let waiting = Task { await watch.waitUntilStopped(); await acknowledged.finish() }
        if cancelWaiter { waiting.cancel() } else { Task { await watch.stop() } }
        try await eventually { await acknowledged.finished }
        await waiting.value
        #expect(await probe.cancelled)
        #expect(await probe.active == 0)
        #expect(await watch.status.phase == .stopped)
        #expect(source.stops == 1)
        source.emit(generation: 0)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await probe.calls == 1)
    }

    @Test func transientFailureRetriesWithoutAnotherEvent() async throws {
        let source = FakeWatchSource()
        let probe = WatchImportProbe(failures: 1)
        let watch = try makeWatch(source, probe)
        defer { Task { await watch.stop() } }
        try await watch.start()
        try await eventually { await watch.status.completedImports == 1 }
        #expect(await probe.calls == 2)
        #expect(await watch.status.error == nil)
        await watch.stop()
    }

    @Test func reattachmentRejectsCallbacksFromPreviousGeneration() async throws {
        let source = FakeWatchSource()
        let probe = WatchImportProbe()
        let watch = try makeWatch(source, probe)
        defer { Task { await watch.stop() } }
        try await watch.start()
        try await eventually { await watch.status.completedImports == 1 }
        source.emit(reattach: true)
        try await eventually { await watch.status.completedImports == 2 }
        #expect(source.starts == 2)
        source.emit(reattach: true, generation: 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(source.starts == 2)
        #expect(await probe.calls == 2)
        source.emit()
        try await eventually { await watch.status.completedImports == 3 }
        await watch.stop()
    }
}

private func makeWatch(_ source: FakeWatchSource, _ probe: WatchImportProbe,
                       debounce: Duration = .milliseconds(20)) throws -> SessionWatch {
    try SessionWatch(source: source, options: WatchOptions(
        debounce: debounce, retryDelay: .milliseconds(20), maximumRetryDelay: .milliseconds(80)
    )) { try await probe.run(registered: source.starts > 0) }
}

private func eventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw WatchTestError.timeout }
        try await Task.sleep(for: .milliseconds(5))
    }
}

private enum WatchTestError: Error { case timeout, transient }

private actor CompletionFlag {
    var finished = false
    func finish() { finished = true }
}

private actor WatchImportProbe {
    var calls = 0
    var active = 0
    var cancelled = false
    var registeredBeforeImport = true
    private var blocked: Bool
    private var failures: Int

    init(blocked: Bool = false, failures: Int = 0) {
        self.blocked = blocked
        self.failures = failures
    }

    func release() { blocked = false }

    func run(registered: Bool) async throws -> ImportSummary {
        calls += 1
        active += 1
        registeredBeforeImport = registeredBeforeImport && registered
        defer { active -= 1 }
        do {
            let deadline = ContinuousClock.now + .seconds(3)
            while blocked {
                guard ContinuousClock.now < deadline else { throw WatchTestError.timeout }
                try await Task.sleep(for: .milliseconds(5))
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            cancelled = true
            throw CancellationError()
        }
        if failures > 0 {
            failures -= 1
            throw WatchTestError.transient
        }
        return ImportSummary(files: 1, records: 1, diagnostics: [:])
    }
}

// All mutable fake native-source state is guarded by the lock; callbacks run outside it.
private final class FakeWatchSource: FileEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [@Sendable (FileWatchEvent) -> Void] = []
    private var stopCount = 0
    var starts: Int { lock.withLock { callbacks.count } }
    var stops: Int { lock.withLock { stopCount } }

    func start(_ receive: @escaping @Sendable (FileWatchEvent) -> Void) throws {
        lock.withLock { callbacks.append(receive) }
    }

    func stop() { lock.withLock { stopCount += 1 } }

    func emit(reattach: Bool = false, generation: Int? = nil) {
        let callback = lock.withLock { callbacks[generation ?? (callbacks.count - 1)] }
        callback(FileWatchEvent(needsReattach: reattach))
    }
}
