import Foundation
import XCTest
@testable import SessionMonitor

@MainActor
final class ReportScopeTests: XCTestCase {
    func testDefaultsToAllTimeUTCAndOffersActualCurrentTimezone() {
        withDefaults { defaults in
            let model = ReportScopeModel(
                defaults: defaults,
                currentTimeZone: requiredTimeZone("Europe/Moscow"),
                now: { Date(timeIntervalSince1970: 1_757_679_240) }
            )

            XCTAssertEqual(model.preset, .all)
            XCTAssertEqual(model.timeZoneIdentifier, "UTC")
            XCTAssertEqual(model.timeZoneIdentifiers, ["UTC", "Europe/Moscow"])
            XCTAssertNil(model.query.since)
            XCTAssertNil(model.query.until)
            XCTAssertEqual(model.query.timeZoneIdentifier, "UTC")
        }
    }

    func testCalendarPresetsResolveFromLocalStartOfDay() {
        withDefaults { defaults in
            let now = Date(timeIntervalSince1970: 1_757_679_240)
            let model = ReportScopeModel(
                defaults: defaults,
                currentTimeZone: requiredTimeZone("Europe/Moscow"),
                now: { now }
            )
            model.selectTimeZone("Europe/Moscow")

            model.selectPreset(.today)
            XCTAssertEqual(model.query.since, date("2025-09-11T21:00:00Z"))
            XCTAssertEqual(model.query.until, date("2025-09-12T21:00:00Z"))
            model.selectPreset(.lastSevenDays)
            XCTAssertEqual(model.query.since, date("2025-09-05T21:00:00Z"))
            model.selectPreset(.lastThirtyDays)
            XCTAssertEqual(model.query.since, date("2025-08-13T21:00:00Z"))
            XCTAssertEqual(model.query.until, date("2025-09-12T21:00:00Z"))
        }
    }

    func testSelectionPersistsAndInvalidStoredValuesFallBack() {
        withDefaults { defaults in
            let timeZone = requiredTimeZone("Europe/Moscow")
            let first = ReportScopeModel(defaults: defaults, currentTimeZone: timeZone)
            first.selectPreset(.lastSevenDays)
            first.selectTimeZone("Europe/Moscow")

            let restored = ReportScopeModel(defaults: defaults, currentTimeZone: timeZone)
            XCTAssertEqual(restored.preset, .lastSevenDays)
            XCTAssertEqual(restored.timeZoneIdentifier, "Europe/Moscow")

            defaults.set("unsupported", forKey: "reportScope.periodPreset")
            defaults.set("America/New_York", forKey: "reportScope.timeZoneIdentifier")
            let recovered = ReportScopeModel(defaults: defaults, currentTimeZone: timeZone)
            XCTAssertEqual(recovered.preset, .all)
            XCTAssertEqual(recovered.timeZoneIdentifier, "UTC")
        }
    }

    func testRefreshRelativePeriodUsesInjectedClock() {
        withDefaults { defaults in
            var now = date("2025-09-13T20:59:00Z")
            let model = ReportScopeModel(
                defaults: defaults,
                currentTimeZone: requiredTimeZone("Europe/Moscow"),
                now: { now }
            )
            model.selectTimeZone("Europe/Moscow")
            model.selectPreset(.today)
            XCTAssertEqual(model.query.since, date("2025-09-12T21:00:00Z"))
            XCTAssertEqual(model.query.until, date("2025-09-13T21:00:00Z"))

            now = date("2025-09-13T21:01:00Z")
            model.refreshRelativePeriod()
            XCTAssertEqual(model.query.since, date("2025-09-13T21:00:00Z"))
            XCTAssertEqual(model.query.until, date("2025-09-14T21:00:00Z"))
        }
    }

    func testRelativePeriodRefreshesAtScheduledBoundary() async {
        let suite = "ReportScopeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var now = date("2025-09-13T20:59:00Z")
        var scheduledBoundaries: [Date] = []
        let model = ReportScopeModel(
            defaults: defaults,
            currentTimeZone: requiredTimeZone("Europe/Moscow"),
            now: { now },
            sleepUntil: { boundary in
                scheduledBoundaries.append(boundary)
                if scheduledBoundaries.count == 1 {
                    now = boundary.addingTimeInterval(1)
                    return
                }
                try await Task.sleep(for: .seconds(60))
            }
        )
        model.selectTimeZone("Europe/Moscow")
        model.selectPreset(.today)

        for _ in 0..<50 where scheduledBoundaries.last != date("2025-09-14T21:00:00Z") {
            await Task.yield()
        }

        XCTAssertEqual(scheduledBoundaries.first, date("2025-09-13T21:00:00Z"))
        XCTAssertEqual(model.query.since, date("2025-09-13T21:00:00Z"))
        XCTAssertEqual(model.query.until, date("2025-09-14T21:00:00Z"))
        XCTAssertEqual(scheduledBoundaries.last, date("2025-09-14T21:00:00Z"))
        model.selectPreset(.all)
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "ReportScopeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    private func requiredTimeZone(_ identifier: String) -> TimeZone {
        guard let value = TimeZone(identifier: identifier) else {
            preconditionFailure("Missing test timezone \(identifier)")
        }
        return value
    }

    private func date(_ value: String) -> Date {
        guard let date = try? Date.ISO8601FormatStyle().parse(value) else {
            preconditionFailure("Invalid fixture date \(value)")
        }
        return date
    }
}
