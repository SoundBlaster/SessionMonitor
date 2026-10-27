import AppKit
import XCTest

@MainActor
final class SandboxWatchUITests: XCTestCase {
    func testDeniedSourceAndIndexRecoverWithoutLosingHistory() throws {
        continueAfterFailure = false
        let product = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "SessionMonitor.app")
        try verifySignedSandbox(product)
        XCTAssertTrue(NSRunningApplication.runningApplications(
            withBundleIdentifier: "ru.egormerkushev.session-monitor"
        ).isEmpty, "Quit SessionMonitor before running the isolated smoke")
        let fixture = try SandboxWatchFixture(parent: .temporaryDirectory)
        let app = configuredApp(fixture: fixture)
        app.launch()
        let connect = app.buttons["storage.chooseIndexFolder"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15))
        connect.click()
        chooseFolder(fixture.index, confirmation: "Connect", app: app)
        activateWatchControls(app)
        app.buttons["watch.chooseFolder"].click()
        chooseFolder(fixture.source, confirmation: "Start Watch", app: app)
        waitForRequests(1, app: app)
        quitNormally(app)

        // Real filesystem denial, not an injected bookmark failure or a TCC reset.
        let sourcePermissions = try denyFolder(fixture.source)
        app.launch()
        waitForRequests(1, app: app)
        waitForStatus("Watch recovering", app: app)
        let denied = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", "permission", "permission"
        )).firstMatch
        XCTAssertTrue(denied.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["watch.stop"].click()
        XCTAssertTrue(app.buttons["watch.chooseFolder"].waitForExistence(timeout: 15))
        try FileManager.default.setAttributes([.posixPermissions: sourcePermissions], ofItemAtPath: fixture.source.path)
        app.buttons["watch.chooseFolder"].click()
        chooseFolder(fixture.source, confirmation: "Start Watch", app: app)
        waitForStatus("Watching", app: app)
        try fixture.append(request: 2)
        waitForRequests(2, app: app)
        quitNormally(app)

        let indexPermissions = try denyFolder(fixture.index)
        app.launch()
        XCTAssertTrue(connect.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["sessionExplorer.importFolder"].exists, "Do not open a fallback empty index")
        try FileManager.default.setAttributes([.posixPermissions: indexPermissions], ofItemAtPath: fixture.index.path)
        connect.click()
        chooseFolder(fixture.index, confirmation: "Connect", app: app)
        waitForRequests(2, app: app)
        waitForStatus("Watching", app: app)
    }

    private func denyFolder(_ directory: URL) throws -> NSNumber {
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions]
                                        as? NSNumber)
        // Registered after fixture teardown, so restoration runs first, even when an assertion fails.
        addTeardownBlock {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: directory.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        return permissions
    }

    func testMovedAndMissingFoldersRecoverThroughNativePickers() throws {
        continueAfterFailure = false
        let product = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "SessionMonitor.app")
        try verifySignedSandbox(product)
        XCTAssertTrue(NSRunningApplication.runningApplications(
            withBundleIdentifier: "ru.egormerkushev.session-monitor"
        ).isEmpty, "Quit SessionMonitor before running this isolated smoke")
        let fixture = try SandboxWatchFixture(parent: .temporaryDirectory)
        let app = configuredApp(fixture: fixture)
        app.launch()
        let connect = app.buttons["storage.chooseIndexFolder"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15))
        connect.click()
        chooseFolder(fixture.index, confirmation: "Connect", app: app)
        activateWatchControls(app)
        app.buttons["watch.chooseFolder"].click()
        chooseFolder(fixture.source, confirmation: "Start Watch", app: app)
        waitForRequests(1, app: app)
        quitNormally(app)

        let movedIndex = fixture.root.appending(path: "moved-index", directoryHint: .isDirectory)
        let movedSource = fixture.root.appending(path: "moved-rollouts", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: fixture.index, to: movedIndex)
        try FileManager.default.moveItem(at: fixture.source, to: movedSource)
        try fixture.append(request: 2, directory: movedSource)
        app.launch()
        waitForRequests(2, app: app)
        waitForStatus("Watching", app: app)
        try verifyMissingSource(app, fixture: fixture, movedSource: movedSource)
        try verifyMissingIndex(app, fixture: fixture, movedIndex: movedIndex)
    }

    func testNativeGrantsWatchPauseResumeAndRelaunch() throws {
        continueAfterFailure = false
        let productDirectory = Bundle.main.bundleURL.deletingLastPathComponent()
        let product = productDirectory.appending(path: "SessionMonitor.app")
        try verifySignedSandbox(product)
        XCTAssertTrue(NSRunningApplication.runningApplications(
            withBundleIdentifier: "ru.egormerkushev.session-monitor"
        ).isEmpty, "Quit SessionMonitor before running this smoke test; it never terminates a user's existing app.")

        // The UI driver is sandboxed too; fixtures belong in its writable temporary directory.
        let fixture = try SandboxWatchFixture(parent: .temporaryDirectory)
        let app = configuredApp(fixture: fixture)

        app.launch()
        let connect = app.buttons["storage.chooseIndexFolder"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15))
        connect.click()
        chooseFolder(fixture.index, confirmation: "Connect", app: app)
        XCTAssertTrue(app.buttons["sessionExplorer.importFolder"].waitForExistence(timeout: 15), app.debugDescription)

        activateWatchControls(app)
        app.buttons["watch.chooseFolder"].click()
        chooseFolder(fixture.source, confirmation: "Start Watch", app: app)
        activateWatchControls(app)
        waitForStatus("Watching", app: app)
        waitForRequests(1, app: app)
        try fixture.append(request: 2)
        waitForRequests(2, app: app)
        try verifyPauseResume(app, fixture: fixture)

        app.menuBars.menuBarItems["SessionMonitor"].click()
        app.menuItems["Quit SessionMonitor"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "Quit must drain Watching and release its source grant")
        try fixture.append(request: 4)
        app.launch()
        waitForRequests(4, app: app)
        activateWatchControls(app)
        waitForStatus("Watching", app: app)
        app.buttons["watch.stop"].click()
        XCTAssertTrue(app.buttons["watch.chooseFolder"].waitForExistence(timeout: 15))
        try fixture.append(request: 5)
        expectNoRequests(5, app: app)
        waitForRequests(4, app: app)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "sandbox-watch-complete"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func verifyMissingSource(_ app: XCUIApplication, fixture: SandboxWatchFixture,
                                     movedSource: URL) throws {
        quitNormally(app)
        try FileManager.default.copyItem(at: movedSource, to: fixture.source)
        try FileManager.default.removeItem(at: movedSource)
        app.launch()
        waitForRequests(2, app: app)
        waitForStatus("Watch not started", app: app)
        let explanation = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", "Choose", "Choose"
        )).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["watch.chooseFolder"].click()
        chooseFolder(fixture.source, confirmation: "Start Watch", app: app)
        try fixture.append(request: 3)
        waitForRequests(3, app: app)
        waitForStatus("Watching", app: app)
    }

    private func verifyMissingIndex(_ app: XCUIApplication, fixture: SandboxWatchFixture,
                                    movedIndex: URL) throws {
        quitNormally(app)
        let backup = fixture.root.appending(path: "backup-index", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: movedIndex, to: backup)
        try FileManager.default.removeItem(at: movedIndex)
        app.launch()
        let connect = app.buttons["storage.chooseIndexFolder"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["sessionExplorer.importFolder"].exists, "No fallback index may open")
        XCTAssertFalse(FileManager.default.fileExists(atPath: movedIndex.path), "Do not recreate the lost index")
        try FileManager.default.moveItem(at: backup, to: fixture.index)
        connect.click()
        chooseFolder(fixture.index, confirmation: "Connect", app: app)
        waitForRequests(3, app: app)
        waitForStatus("Watching", app: app)
    }

    private func verifyPauseResume(_ app: XCUIApplication, fixture: SandboxWatchFixture) throws {
        activateWatchControls(app)
        app.buttons["watch.pauseResume"].click()
        waitForStatus("Watch paused", app: app)
        try fixture.append(request: 3)
        expectNoRequests(3, app: app)
        activateWatchControls(app)
        app.buttons["watch.pauseResume"].click()
        waitForStatus("Watching", app: app)
        waitForRequests(3, app: app)

    }

}
