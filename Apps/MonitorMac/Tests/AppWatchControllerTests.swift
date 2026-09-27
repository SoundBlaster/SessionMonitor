import Foundation
import MonitorRuntime
import XCTest
@testable import SessionMonitor

@MainActor
final class AppWatchControllerTests: XCTestCase {
    func testStartConsumesOneStatusStreamAndIgnoresDuplicateStart() async throws {
        let factory = WatchFactory()
        let controller = AppWatchController { directory in
            try await factory.make(directory)
        }
        let directory = URL(fileURLWithPath: "/tmp/first-watch")
        let otherDirectory = URL(fileURLWithPath: "/tmp/second-watch")

        await controller.start(directory)
        let handleValue = await awaitedHandle(from: factory)
        let handle = try XCTUnwrap(handleValue)
        let firstCallCount = await factory.callCount
        XCTAssertEqual(firstCallCount, 1)
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(controller.directory, directory)

        await handle.emit(try status(phase: "watching", completedImports: 1))
        try await eventually { controller.status?.phase == .watching }

        await controller.start(otherDirectory)

        let duplicateCallCount = await factory.callCount
        XCTAssertEqual(duplicateCallCount, 1)
        XCTAssertEqual(controller.directory, directory)
        let pauseCount = await handle.pauseCount
        XCTAssertEqual(pauseCount, 0)
    }

    func testCompletedImportsPublishWidgetSnapshotOnlyOncePerImport() async throws {
        let factory = WatchFactory()
        let callback = ImportCallbackCounter()
        let controller = AppWatchController(
            didImport: { await callback.record() },
            factory: { directory in try await factory.make(directory) }
        )
        await controller.start(URL(fileURLWithPath: "/tmp/widget-watch"))
        let handleValue = await factory.latestHandle
        let handle = try XCTUnwrap(handleValue)

        await handle.emit(try status(phase: "watching", completedImports: 1))
        try await eventually { await callback.count == 1 }
        await handle.emit(try status(phase: "watching", completedImports: 1))
        await handle.emit(try status(phase: "watching", completedImports: 2))
        try await eventually { await callback.count == 2 }

        let callbackCount = await callback.count
        XCTAssertEqual(callbackCount, 2)
        await controller.stop()
    }

    func testPauseResumeAndStopForwardToTheRuntimeHandle() async throws {
        let factory = WatchFactory()
        let controller = AppWatchController { directory in
            try await factory.make(directory)
        }
        await controller.start(URL(fileURLWithPath: "/tmp/watch"))
        let handleValue = await awaitedHandle(from: factory)
        let handle = try XCTUnwrap(handleValue)

        await controller.pause()
        await controller.resume()
        await controller.stop()

        let pauseCount = await handle.pauseCount
        let resumeCount = await handle.resumeCount
        let stopCount = await handle.stopCount
        XCTAssertEqual(pauseCount, 1)
        XCTAssertEqual(resumeCount, 1)
        XCTAssertEqual(stopCount, 1)
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(controller.isBusy)
        XCTAssertNil(controller.directory)
        XCTAssertNil(controller.status)
    }

    func testFactoryFailureLeavesAnActionableErrorAndNoRunningWatch() async {
        let factory = WatchFactory(error: FixtureError.factoryFailed)
        let controller = AppWatchController { directory in
            try await factory.make(directory)
        }

        await controller.start(URL(fileURLWithPath: "/tmp/failed-watch"))

        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(controller.isBusy)
        XCTAssertNil(controller.directory)
        XCTAssertEqual(controller.errorMessage, "Could not start watch. Fixture factory failed")
        let callCount = await factory.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testShutdownJoinsGatedFactoryAndStopsItsLateResult() async throws {
        let factory = WatchFactory(blocked: true)
        let controller = AppWatchController { directory in
            try await factory.make(directory)
        }
        let directory = URL(fileURLWithPath: "/tmp/gated-watch")

        let start = Task { await controller.start(directory) }
        try await eventually { controller.isRunning && controller.isBusy }
        try await eventually { await factory.callCount == 1 }

        let shutdown = Task { await controller.shutdown() }
        try await eventually { controller.isShuttingDown }
        XCTAssertTrue(controller.isRunning)

        await factory.release()
        await start.value
        await shutdown.value

        let handleValue = await awaitedHandle(from: factory)
        let handle = try XCTUnwrap(handleValue)
        let stopCount = await handle.stopCount
        XCTAssertEqual(stopCount, 1)
        XCTAssertTrue(controller.isShuttingDown)
        XCTAssertFalse(controller.isRunning)
        XCTAssertFalse(controller.isBusy)

        // A completed shutdown permanently rejects a later explicit start.
        await controller.start(URL(fileURLWithPath: "/tmp/after-shutdown"))
        let callCount = await factory.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testShutdownWhilePauseIsActiveStillStopsTheHandle() async throws {
        let factory = WatchFactory()
        let controller = AppWatchController { directory in
            try await factory.make(directory)
        }
        await controller.start(URL(fileURLWithPath: "/tmp/pause-watch"))
        let handleValue = await awaitedHandle(from: factory)
        let handle = try XCTUnwrap(handleValue)
        await handle.blockPause()

        let pause = Task { await controller.pause() }
        try await eventually { await handle.pauseCount == 1 }
        let shutdown = Task { await controller.shutdown() }
        try await eventually { await handle.stopCount == 1 }

        let stopCount = await handle.stopCount
        XCTAssertEqual(stopCount, 1)
        await handle.releasePause()
        await pause.value
        await shutdown.value
        XCTAssertFalse(controller.isRunning)
    }

    func testOldStatusConsumerCannotOverwriteANewStart() async throws {
        let factory = WatchFactory(finishesOnStop: false)
        let controller = AppWatchController { directory in
            try await factory.make(directory)
        }

        await controller.start(URL(fileURLWithPath: "/tmp/old-watch"))
        let oldHandleValue = await awaitedHandle(from: factory)
        let oldHandle = try XCTUnwrap(oldHandleValue)
        await oldHandle.emit(try status(phase: "watching", completedImports: 1))
        try await eventually { controller.status?.completedImports == 1 }

        await controller.stop()
        await controller.start(URL(fileURLWithPath: "/tmp/new-watch"))
        let newHandleValue = await awaitedHandle(from: factory)
        let newHandle = try XCTUnwrap(newHandleValue)
        await newHandle.emit(try status(phase: "watching", completedImports: 2))
        try await eventually { controller.status?.completedImports == 2 }

        await oldHandle.emit(try status(phase: "recovering", completedImports: 99, error: "stale"))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(controller.status?.completedImports, 2)
        XCTAssertEqual(controller.status?.phase, .watching)
        XCTAssertNil(controller.status?.error)
    }

    private func status(
        phase: String,
        completedImports: Int,
        error: String? = nil
    ) throws -> WatchStatus {
        let errorValue = error.map { "\"\($0)\"" } ?? "null"
        let json = """
        {"phase":"\(phase)","completedImports":\(completedImports),"lastImport":null,"error":\(errorValue)}
        """
        return try JSONDecoder().decode(WatchStatus.self, from: Data(json.utf8))
    }

    private func awaitedHandle(from factory: WatchFactory) async -> FakeWatchHandle? {
        await factory.latestHandle
    }

    private func eventually(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else { throw FixtureError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor ImportCallbackCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor WatchFactory {
    private let error: Error?
    private let finishesOnStop: Bool
    private var blocked: Bool
    private var released = false
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0
    private(set) var latestHandle: FakeWatchHandle?

    init(
        blocked: Bool = false,
        finishesOnStop: Bool = true,
        error: Error? = nil
    ) {
        self.blocked = blocked
        self.finishesOnStop = finishesOnStop
        self.error = error
    }

    func make(_ directory: URL) async throws -> any AppWatchHandle {
        callCount += 1
        if blocked, !released {
            await withCheckedContinuation { gate = $0 }
        }
        if let error { throw error }
        let handle = FakeWatchHandle(finishesOnStop: finishesOnStop)
        latestHandle = handle
        return handle
    }

    func release() {
        released = true
        gate?.resume()
        gate = nil
    }
}

private actor FakeWatchHandle: AppWatchHandle {
    nonisolated let updates: AsyncStream<WatchStatus>
    private let continuation: AsyncStream<WatchStatus>.Continuation
    private let finishesOnStop: Bool
    private var pauseIsBlocked = false
    private var pauseGate: CheckedContinuation<Void, Never>?
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0

    init(finishesOnStop: Bool) {
        let (updates, continuation) = AsyncStream<WatchStatus>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.updates = updates
        self.continuation = continuation
        self.finishesOnStop = finishesOnStop
    }

    func pause() async {
        pauseCount += 1
        if pauseIsBlocked {
            await withCheckedContinuation { pauseGate = $0 }
        }
    }

    func resume() async { resumeCount += 1 }

    func stop() async {
        stopCount += 1
        if finishesOnStop { continuation.finish() }
    }

    func emit(_ value: WatchStatus) { continuation.yield(value) }

    func blockPause() { pauseIsBlocked = true }

    func releasePause() {
        pauseIsBlocked = false
        pauseGate?.resume()
        pauseGate = nil
    }
}

private enum FixtureError: Error, LocalizedError {
    case factoryFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .factoryFailed: "Fixture factory failed"
        case .timeout: "Timed out waiting for fixture state"
        }
    }
}
