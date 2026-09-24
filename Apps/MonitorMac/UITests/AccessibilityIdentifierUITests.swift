import XCTest

final class AccessibilityIdentifierUITests: XCTestCase {
    func testSessionExplorerControlsExposeStableAccessibilityIdentifiers() {
        let app = XCUIApplication()
        app.launch()

        let importFolder = app.buttons["sessionExplorer.importFolder"]
        XCTAssertTrue(importFolder.waitForExistence(timeout: 10))

        let update = app.buttons["sessionExplorer.update"]
        XCTAssertTrue(update.exists)

        let inspectorToggle = app.buttons["sessionExplorer.inspectorToggle"]
        XCTAssertTrue(inspectorToggle.exists)

        let accountScope = app.buttons["sessionExplorer.accountScope"]
        XCTAssertTrue(accountScope.exists)

        XCTAssertEqual(importFolder.label, "Import Folder…")
        XCTAssertTrue(inspectorToggle.label.contains("Inspector"))
    }
}
