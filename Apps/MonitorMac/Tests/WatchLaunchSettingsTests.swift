import Foundation
import XCTest
@testable import SessionMonitor

final class WatchLaunchSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults()

    override func setUp() {
        super.setUp()
        suiteName = "WatchLaunchSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testNothingToResumeUntilAFolderIsChosen() {
        let settings = WatchLaunchSettings(defaults: defaults)
        XCTAssertNil(settings.directory)
        XCTAssertTrue(settings.startOnLaunch)
        XCTAssertNil(settings.launchDirectory())
    }

    func testRememberedExistingFolderIsResumedUnlessDisabled() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = WatchLaunchSettings(defaults: defaults)

        settings.remember(folder)
        XCTAssertEqual(settings.launchDirectory(), .success(folder.standardizedFileURL))

        defaults.set(false, forKey: WatchLaunchSettings.startOnLaunchKey)
        XCTAssertNil(settings.launchDirectory())
    }

    func testMissingFolderReportsAnActionableError() {
        let settings = WatchLaunchSettings(defaults: defaults)
        let missing = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)", isDirectory: true)
        settings.remember(missing)
        XCTAssertEqual(settings.launchDirectory(), .failure(.missingDirectory(missing.standardizedFileURL.path)))
    }
}
