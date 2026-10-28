import AppKit
import XCTest

@MainActor
extension SandboxWatchUITests {
    func configuredApp(fixture: SandboxWatchFixture) -> XCUIApplication {
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

    func quitNormally(_ app: XCUIApplication) {
        app.menuBars.menuBarItems["SessionMonitor"].click()
        app.menuItems["Quit SessionMonitor"].click()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15))
    }

    func chooseFolder(_ directory: URL, confirmation: String, app: XCUIApplication) {
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

    func activateWatchControls(_ app: XCUIApplication) {
        app.activate()
        let controls = app.buttons.matching(NSPredicate(format: "identifier IN %@",
                                                        ["watch.chooseFolder", "watch.pauseResume"])).firstMatch
        XCTAssertTrue(controls.waitForExistence(timeout: 10), app.debugDescription)
    }

    func waitForStatus(_ status: String, app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: "watch.status").firstMatch
        let predicate = NSPredicate(format: "label == %@ OR value == %@", status, status)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, app.debugDescription)
    }

    func requestExpectation(_ count: Int, app: XCUIApplication) -> XCTNSPredicateExpectation {
        // macOS exposes the metric strip as label-only elements. The chart summary
        // includes the request count and also verifies that Watching refreshes its data.
        let element = app.groups.matching(identifier: "contextAnatomy").matching(
            NSPredicate(format: "label BEGINSWITH %@", "Context anatomy: \(count) request")
        ).firstMatch
        return XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: element)
    }

    func waitForRequests(_ count: Int, app: XCUIApplication) {
        XCTAssertEqual(XCTWaiter.wait(for: [requestExpectation(count, app: app)], timeout: 15), .completed,
                       app.debugDescription)
    }

    func expectNoRequests(_ count: Int, app: XCUIApplication) {
        let expectation = requestExpectation(count, app: app)
        expectation.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 2), .completed)
    }

    func verifySignedSandbox(_ product: URL) throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: product.path), "Build StoreDebug before the test")
        let data = try runCodesign(["-d", "--entitlements", ":-", product.path])
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
        XCTAssertNotNil(plist["com.apple.developer.team-identifier"], "An ad-hoc build cannot validate Store grants")
        _ = try runCodesign(["--verify", "--deep", "--strict", product.path])
    }

    func runCodesign(_ arguments: [String]) throws -> Data {
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
