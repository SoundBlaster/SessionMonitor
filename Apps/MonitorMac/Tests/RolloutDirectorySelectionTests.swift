import Foundation
import XCTest
@testable import SessionMonitor

final class RolloutDirectorySelectionTests: XCTestCase {
    func testNewUserStartsInCurrentYearAndAdvancesWithCalendar() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let year2026 = home.appending(path: ".codex/sessions/2026", directoryHint: .isDirectory)
        let year2027 = home.appending(path: ".codex/sessions/2027", directoryHint: .isDirectory)
        for year in [year2026, year2027] {
            try FileManager.default.createDirectory(at: year, withIntermediateDirectories: true)
        }
        XCTAssertEqual(RolloutDirectorySelection.initialDirectory(preferred: nil, home: home, year: 2026), year2026)
        XCTAssertEqual(RolloutDirectorySelection.initialDirectory(preferred: nil, home: home, year: 2027), year2027)
    }

    func testExistingSavedFolderWinsAndMissingSavedFolderFallsBack() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let saved = home.appending(path: "custom-rollouts", directoryHint: .isDirectory)
        let year = home.appending(path: ".codex/sessions/2026", directoryHint: .isDirectory)
        for folder in [saved, year] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        XCTAssertEqual(RolloutDirectorySelection.initialDirectory(preferred: saved, home: home, year: 2026), saved)
        try FileManager.default.removeItem(at: saved)
        XCTAssertEqual(RolloutDirectorySelection.initialDirectory(preferred: saved, home: home, year: 2026), year)
    }

    func testMissingYearFallsBackToSessionsAndIgnoresRegularFiles() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appending(path: ".codex/sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let yearFile = sessions.appending(path: "2026", directoryHint: .notDirectory)
        try Data().write(to: yearFile)
        XCTAssertEqual(
            RolloutDirectorySelection.initialDirectory(preferred: yearFile, home: home, year: 2026), sessions
        )
        try FileManager.default.removeItem(at: sessions)
        XCTAssertEqual(RolloutDirectorySelection.initialDirectory(preferred: nil, home: home, year: 2026),
                       home.appending(path: ".codex", directoryHint: .isDirectory))
        try FileManager.default.removeItem(at: home.appending(path: ".codex", directoryHint: .isDirectory))
        XCTAssertEqual(RolloutDirectorySelection.initialDirectory(preferred: nil, home: home, year: 2026), home)
    }

    func testDirectoryYearIsGregorianEvenWithOtherPreferredCalendars() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-31T22:00:00Z"))
        for identifier in [Calendar.Identifier.gregorian, .buddhist, .japanese, .islamicUmmAlQura] {
            var calendar = Calendar(identifier: identifier)
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
            XCTAssertEqual(RolloutDirectorySelection.directoryYear(at: date, calendar: calendar), 2027)
            calendar.timeZone = .gmt
            XCTAssertEqual(RolloutDirectorySelection.directoryYear(at: date, calendar: calendar), 2026)
        }
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
}
