import AppKit
import XCTest

@MainActor
final class SandboxWatchUITests: XCTestCase {
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

    private func configuredApp(fixture: SandboxWatchFixture) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)",
                               "-AppleLocale", "en_US"]
        app.launchEnvironment["SESSIONMONITOR_UI_TEST_SUITE"] = fixture.suite
        app.launchEnvironment["SESSIONMONITOR_UI_TEST_FIXTURE"] = fixture.root.path
        addTeardownBlock { @MainActor in
            app.terminate()
            app.launchEnvironment["SESSIONMONITOR_UI_TEST_RESET"] = "1"
            app.launch()
            XCTAssertTrue(app.buttons["storage.chooseIndexFolder"].waitForExistence(timeout: 15))
            app.terminate()
            try FileManager.default.removeItem(at: fixture.root)
        }
        return app
    }

    private func quitNormally(_ app: XCUIApplication) {
        app.menuBars.menuBarItems["SessionMonitor"].click()
        app.menuItems["Quit SessionMonitor"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15))
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

    private func chooseFolder(_ directory: URL, confirmation: String, app: XCUIApplication) {
        let panel = app.dialogs["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let location = panel.popUpButtons["where popup"]
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        XCTAssertEqual(location.value as? String, directory.lastPathComponent, app.debugDescription)
        let button = panel.buttons.matching(identifier: "OKButton").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(confirmation) in the system folder picker")
        button.click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 10))
    }

    private func activateWatchControls(_ app: XCUIApplication) {
        app.activate()
        let controls = app.buttons.matching(NSPredicate(format: "identifier IN %@",
                                                        ["watch.chooseFolder", "watch.pauseResume"])).firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 10), app.debugDescription)
    }

    private func waitForStatus(_ status: String, app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: "watch.status").firstMatch
        let predicate = NSPredicate(format: "label == %@ OR value == %@", status, status)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, app.debugDescription)
    }

    private func requestExpectation(_ count: Int, app: XCUIApplication) -> XCTNSPredicateExpectation {
        // macOS exposes the metric strip as label-only elements. The chart summary
        // includes the request count and also verifies that Watching refreshes its data.
        let element = app.groups.matching(identifier: "contextAnatomy").matching(
            NSPredicate(format: "label BEGINSWITH %@", "Context anatomy: \(count) request")
        ).firstMatch
        return XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: element)
    }

    private func waitForRequests(_ count: Int, app: XCUIApplication) {
        XCTAssertEqual(XCTWaiter.wait(for: [requestExpectation(count, app: app)], timeout: 15), .completed,
                       app.debugDescription)
    }

    private func expectNoRequests(_ count: Int, app: XCUIApplication) {
        let expectation = requestExpectation(count, app: app)
        expectation.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 2), .completed)
    }

    private func verifySignedSandbox(_ product: URL) throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: product.path), "Build StoreDebug before the test")
        let data = try runCodesign(["-d", "--entitlements", ":-", product.path])
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
        XCTAssertNotNil(plist["com.apple.developer.team-identifier"], "An ad-hoc build cannot validate Store grants")
        _ = try runCodesign(["--verify", "--deep", "--strict", product.path])
    }

    private func runCodesign(_ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(process.terminationStatus, 0, message ?? "codesign failed")
        return output.fileHandleForReading.readDataToEndOfFile()
    }
}
