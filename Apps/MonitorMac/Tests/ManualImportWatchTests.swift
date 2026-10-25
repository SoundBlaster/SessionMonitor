import Foundation
import MonitorCore
import MonitorRuntime
import XCTest
@testable import SessionMonitor

@MainActor
final class ManualImportWatchTests: XCTestCase {
    func testModelImportStopsRealActiveAndPausedWatchForAnotherFolder() async throws {
        for paused in [false, true] {
            let fixture = try ManualImportFixture()
            defer { fixture.remove() }
            let runtime = try MonitorRuntime.SessionMonitor(databaseURL: fixture.database)
            let watch = AppWatchController { try await runtime.watch($0) }
            await watch.start(fixture.watched)
            XCTAssertTrue(watch.isRunning)
            if paused { await watch.pause() }
            if paused { try ImportedDirectorySettings(defaults: fixture.defaults).save(fixture.selected) }
            let model = fixture.model(runtime: runtime, watch: watch)

            if paused {
                await model.update()
            } else {
                await model.importDirectory(fixture.selected)
            }

            XCTAssertNil(model.errorMessage)
            XCTAssertEqual(model.importedDirectory, fixture.selected)
            XCTAssertNotNil(model.importSummary)
            XCTAssertFalse(watch.isRunning)
            XCTAssertFalse(watch.isImporting)
            await watch.stop()
        }
    }

    func testCleanupCompletesBeforeImportAndStartIsBlockedUntilImportEnds() async throws {
        let handle = ManualWatchHandle()
        let imports = ManualImportProbe()
        let starts = ManualImportProbe()
        let watch = AppWatchController { _ in
            await starts.record()
            return handle
        }
        await watch.start(URL(fileURLWithPath: "/tmp/watched"))
        let importing = Task {
            try await watch.importManually {
                await imports.record()
                await imports.release.wait()
                return ImportSummary(files: 1, records: 0, diagnostics: [:])
            }
        }
        await handle.stopEntered.wait()
        let beforeCleanup = await imports.count
        XCTAssertEqual(beforeCleanup, 0)
        await handle.stopRelease.open()
        await imports.entered.wait()

        await watch.start(URL(fileURLWithPath: "/tmp/new-watch"))
        let blockedStarts = await starts.count
        XCTAssertEqual(blockedStarts, 1)
        XCTAssertTrue(watch.isImporting)
        await imports.release.open()
        _ = try await importing.value

        XCTAssertFalse(watch.isRunning)
        XCTAssertFalse(watch.isImporting)
        await watch.start(URL(fileURLWithPath: "/tmp/explicit-restart"))
        let allowedStarts = await starts.count
        XCTAssertEqual(allowedStarts, 2)
        await watch.stop()
    }

    func testPendingWatchResultIsStoppedBeforeManualImport() async throws {
        let factory = ManualImportProbe()
        let handle = ManualWatchHandle()
        await handle.stopRelease.open()
        let watch = AppWatchController { _ in
            await factory.record()
            await factory.release.wait()
            return handle
        }
        let starting = Task { await watch.start(URL(fileURLWithPath: "/tmp/pending")) }
        await factory.entered.wait()
        let importing = Task {
            try await watch.importManually {
                let stopped = await handle.stopCount
                XCTAssertEqual(stopped, 1)
                return ImportSummary(files: 0, records: 0, diagnostics: [:])
            }
        }
        try await eventually { watch.isImporting && watch.isBusy }
        await factory.release.open()
        await starting.value
        _ = try await importing.value
        XCTAssertFalse(watch.isRunning)
    }

    func testCancellationDuringStopFinishesCleanupWithoutStartingImport() async throws {
        let handle = ManualWatchHandle()
        let imports = ManualImportProbe()
        let watch = AppWatchController { _ in handle }
        await watch.start(URL(fileURLWithPath: "/tmp/watched"))
        let importing = Task {
            try await watch.importManually {
                await imports.record()
                return ImportSummary(files: 0, records: 0, diagnostics: [:])
            }
        }
        await handle.stopEntered.wait()
        importing.cancel()
        await handle.stopRelease.open()
        do {
            _ = try await importing.value
            XCTFail("Cancelled import must not run")
        } catch is CancellationError {
            // Watch cleanup must still finish before returning cancellation.
        }
        let count = await imports.count
        XCTAssertEqual(count, 0)
        XCTAssertFalse(watch.isRunning)
        XCTAssertFalse(watch.isImporting)
        _ = try await watch.importManually { ImportSummary(files: 0, records: 0, diagnostics: [:]) }
    }

    func testTwoWindowImportsAreSerializedAndFailureReleasesSlot() async throws {
        let fixture = try ManualImportFixture()
        defer { fixture.remove() }
        let runtime = StubExplorerRuntime(report: UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:]))
        let handle = ManualWatchHandle()
        await handle.stopRelease.open()
        let watch = AppWatchController { _ in handle }
        await watch.start(fixture.watched)
        let probe = ManualImportProbe()
        let first = fixture.model(runtime: runtime, watch: watch, beforeImport: {
            await probe.record()
            await probe.release.wait()
            throw ManualImportFailure.expected
        })
        let second = fixture.model(runtime: runtime, watch: watch)
        let firstTask = Task { await first.importDirectory(fixture.watched) }
        await probe.entered.wait()
        let secondTask = Task { await second.importDirectory(fixture.selected) }
        try await eventually { second.isBusy }
        let beforeRelease = await runtime.importedDirectories
        XCTAssertTrue(beforeRelease.isEmpty)
        await probe.release.open()
        await firstTask.value
        await secondTask.value
        let afterRelease = await runtime.importedDirectories
        XCTAssertEqual(afterRelease, [fixture.selected])
        XCTAssertNotNil(first.errorMessage)
        XCTAssertNil(second.errorMessage)
        XCTAssertFalse(watch.isRunning)
        XCTAssertFalse(watch.isImporting)
    }

    func testExternalWatchStillBlocksImportAndRetryUsesSameCoordination() async throws {
        let fixture = try ManualImportFixture()
        defer { fixture.remove() }
        let owner = try MonitorRuntime.SessionMonitor(databaseURL: fixture.database)
        let reader = try MonitorRuntime.SessionMonitor(databaseURL: fixture.database)
        let external = try await owner.watch(fixture.watched)
        await external.pause()
        let watch = AppWatchController { try await reader.watch($0) }
        let model = fixture.model(runtime: reader, watch: watch)

        await model.importDirectory(fixture.selected)

        XCTAssertEqual(model.importRecoveryDirectory, fixture.selected)
        let status = await external.status
        XCTAssertEqual(status.phase, .paused)
        await external.stop()
        await watch.start(fixture.watched)
        XCTAssertTrue(watch.isRunning)
        await model.retryImport()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.importedDirectory, fixture.selected)
        XCTAssertFalse(watch.isRunning)
    }

    func testShutdownCancelsAndJoinsManualImportThenRejectsAnother() async throws {
        let probe = ManualImportProbe()
        let watch = AppWatchController { _ in ManualWatchHandle() }
        let importing = Task {
            try await watch.importManually {
                await probe.record()
                await probe.release.wait()
                try Task.checkCancellation()
                return ImportSummary(files: 0, records: 0, diagnostics: [:])
            }
        }
        await probe.entered.wait()
        let shutdown = Task { await watch.shutdown() }
        try await eventually { watch.isShuttingDown }
        await probe.release.open()
        do {
            _ = try await importing.value
            XCTFail("Shutdown must cancel the import")
        } catch is CancellationError {}
        await shutdown.value
        XCTAssertFalse(watch.isImporting)
        do {
            _ = try await watch.importManually {
                XCTFail("Shutdown must reject a new import")
                return ImportSummary(files: 0, records: 0, diagnostics: [:])
            }
            XCTFail("Expected cancellation after shutdown")
        } catch is CancellationError {}
    }

    private func eventually(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition() {
            guard clock.now < deadline else { throw ManualImportFailure.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor ManualImportGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor ManualImportProbe {
    let entered = ManualImportGate()
    let release = ManualImportGate()
    private(set) var count = 0
    func record() async {
        count += 1
        await entered.open()
    }
}

private actor ManualWatchHandle: AppWatchHandle {
    nonisolated let updates: AsyncStream<WatchStatus>
    private let continuation: AsyncStream<WatchStatus>.Continuation
    let stopEntered = ManualImportGate()
    let stopRelease = ManualImportGate()
    private(set) var stopCount = 0
    init() {
        let pair = AsyncStream<WatchStatus>.makeStream()
        updates = pair.stream
        continuation = pair.continuation
    }
    func pause() async {}
    func resume() async {}
    func stop() async {
        stopCount += 1
        await stopEntered.open()
        await stopRelease.wait()
        continuation.finish()
    }
}

@MainActor
private struct ManualImportFixture {
    let root: URL
    let watched: URL
    let selected: URL
    let database: URL
    let defaults: UserDefaults
    let suite = "ManualImportWatchTests.\(UUID())"
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        watched = root.appendingPathComponent("watched", isDirectory: true)
        selected = root.appendingPathComponent("selected", isDirectory: true)
        database = root.appending(path: "usage.sqlite")
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: watched, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
    }
    func model(runtime: any SessionExplorerRuntime, watch: AppWatchController,
               beforeImport: @escaping @Sendable () async throws -> Void = {}) -> SessionExplorerModel {
        SessionExplorerModel(importOperation: { directory, runtime, progress in
            try await watch.importManually {
                try await beforeImport()
                return try await runtime.importDirectory(directory, progress: progress)
            }
        }, runtimeFactory: { runtime }, importedDirectorySettings: ImportedDirectorySettings(defaults: defaults))
    }
    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private enum ManualImportFailure: Error {
    case expected
    case timeout
}
