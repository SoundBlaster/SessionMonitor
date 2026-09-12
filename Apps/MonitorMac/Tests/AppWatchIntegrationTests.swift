import Foundation
import MonitorRuntime
import XCTest
@testable import SessionMonitor

@MainActor
final class AppWatchIntegrationTests: XCTestCase {
    func testAppShutdownReleasesRealPausedWatchOwnership() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let rollouts = root.appending(path: "rollouts")
        try FileManager.default.createDirectory(at: rollouts, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try MonitorRuntime.SessionMonitor(databaseURL: root.appending(path: "usage.sqlite"))
        let controller = AppWatchController { try await runtime.watch($0) }
        await controller.start(rollouts)
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(controller.isRunning)
        await controller.pause()
        do {
            _ = try await runtime.importDirectory(rollouts)
            XCTFail("Paused app watch must retain importer ownership")
        } catch MonitorError.importerBusy {
            // Expected: pause retains the watch lease.
        } catch {
            await controller.shutdown()
            throw error
        }
        await controller.shutdown()
        XCTAssertFalse(controller.isRunning)
        _ = try await runtime.importDirectory(rollouts)
    }
}
