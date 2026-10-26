import AppKit
import Carbon
import XCTest

@MainActor
final class SandboxWatchUITests: XCTestCase {
    func testNativeGrantsWatchPauseResumeAndRelaunch() throws {
        continueAfterFailure = false
        let productDirectory = Bundle.main.bundleURL.deletingLastPathComponent()
        let product = productDirectory.appending(path: "SessionMonitor.app")
        try verifySignedSandbox(product)
        XCTAssertTrue(NSRunningApplication.runningApplications(
            withBundleIdentifier: "ru.egormerkushev.session-monitor"
        ).isEmpty, "Quit SessionMonitor before running this smoke test; it never terminates a user's existing app.")
        try useLatinKeyboard()

        // The UI driver is sandboxed too; fixtures belong in its writable temporary directory.
        let fixture = try SandboxWatchFixture(parent: .temporaryDirectory)
        let app = configuredApp(fixture: fixture)

        app.launch()
        let connect = app.buttons["storage.chooseIndexFolder"]
        XCTAssertTrue(connect.waitForExistence(timeout: 15))
        connect.click()
        chooseFolder(fixture.index, confirmation: "Connect", app: app)
        XCTAssertTrue(app.buttons["sessionExplorer.importFolder"].waitForExistence(timeout: 15), app.debugDescription)

        openWatchPanel(app)
        app.buttons["watch.chooseFolder"].click()
        chooseFolder(fixture.source, confirmation: "Start Watch", app: app)
        openWatchPanel(app)
        waitForStatus("Watching", app: app)
        dismissPanel(app)
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
        openWatchPanel(app)
        waitForStatus("Watching", app: app)
        app.buttons["watch.stop"].click()
        XCTAssertTrue(app.buttons["watch.chooseFolder"].waitForExistence(timeout: 15))
        dismissPanel(app)
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

    private func useLatinKeyboard() throws {
        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let filter = [kTISPropertyInputSourceID: "com.apple.keylayout.ABC"] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue()
        let latin = try XCTUnwrap((sources as? [TISInputSource])?.first, "Enable the standard ABC input source")
        XCTAssertEqual(TISSelectInputSource(latin), noErr)
        // Registered first, restored last, after the app's cleanup launch.
        addTeardownBlock { @MainActor in
            XCTAssertEqual(TISSelectInputSource(original), noErr)
        }
    }

    private func verifyPauseResume(_ app: XCUIApplication, fixture: SandboxWatchFixture) throws {
        openWatchPanel(app)
        app.buttons["watch.pauseResume"].click()
        waitForStatus("Watch paused", app: app)
        dismissPanel(app)
        try fixture.append(request: 3)
        expectNoRequests(3, app: app)
        openWatchPanel(app)
        app.buttons["watch.pauseResume"].click()
        waitForStatus("Watching", app: app)
        dismissPanel(app)
        waitForRequests(3, app: app)

    }

    private func chooseFolder(_ directory: URL, confirmation: String, app: XCUIApplication) {
        let panel = app.dialogs["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        app.activate()
        panel.click()
        // A literal slash opens Go to Folder without depending on a Latin keyboard layout.
        panel.typeText("/")
        let field = app.textFields["PathTextField"]
        let pathAppeared = field.waitForExistence(timeout: 10)
        if !pathAppeared {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "picker-go-to-folder"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(pathAppeared, app.debugDescription)
        XCTAssertEqual(field.value as? String, "/")
        field.typeText(String(directory.path.dropFirst()))
        XCTAssertEqual(field.value as? String, directory.path)
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 10), app.debugDescription)
        let button = panel.buttons.matching(identifier: "OKButton").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(confirmation) in the system folder picker")
        button.click()
    }

    private func openWatchPanel(_ app: XCUIApplication) {
        if app.buttons["watch.pauseResume"].exists || app.buttons["watch.chooseFolder"].exists { return }
        app.activate()
        let systemMenu = XCUIApplication(bundleIdentifier: "com.apple.MenuBarAgent")
        if systemMenu.state != .notRunning {
            let reveals = systemMenu.buttons.matching(identifier: "Show Hidden Menu Bar Items")
            if let reveal = reveals.allElementsBoundByIndex.first(where: \.isHittable) {
                reveal.click()
                addTeardownBlock { @MainActor in
                    let hides = systemMenu.buttons.matching(identifier: "Hide Menu Bar Items")
                    if let hide = hides.allElementsBoundByIndex.first(where: \.isHittable) { hide.click() }
                }
            }
        }
        let item = app.descendants(matching: .statusItem).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
        item.click()
        let controls = app.buttons.matching(NSPredicate(format: "identifier IN %@",
                                                        ["watch.chooseFolder", "watch.pauseResume"])).firstMatch
        if !controls.waitForExistence(timeout: 3) {
            // The first click can activate the status area before opening its panel.
            item.click()
        }
        let panelScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        panelScreenshot.name = "watch-panel"
        panelScreenshot.lifetime = .keepAlways
        add(panelScreenshot)
        XCTAssertTrue(controls.waitForExistence(timeout: 10), app.debugDescription)
    }

    private func dismissPanel(_ app: XCUIApplication) {
        app.windows.matching(identifier: "session-explorer-AppWindow-1").firstMatch.click()
    }

    private func waitForStatus(_ status: String, app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: "watch.status").firstMatch
        let predicate = NSPredicate(format: "label == %@ OR value == %@", status, status)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, app.debugDescription)
    }

    private func requestExpectation(_ count: Int, app: XCUIApplication) -> XCTNSPredicateExpectation {
        let element = app.descendants(matching: .any).matching(identifier: "sessionDetail.requests").firstMatch
        return XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", String(count)), object: element)
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
