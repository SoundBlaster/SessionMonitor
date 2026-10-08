import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

@MainActor
final class ReportScopeFocusTests: XCTestCase {
    func testFocusNarrowsTheQueryWithoutTouchingThePeriodAndIsNeverStored() {
        withDefaults { defaults in
            let model = ReportScopeModel(defaults: defaults, currentTimeZone: requiredTimeZone("UTC"),
                                         now: { self.date("2026-09-30T09:30:00Z") })
            model.selectPreset(.lastSevenDays)
            let period = model.query
            let day = DateInterval(start: date("2026-09-28T00:00:00Z"), end: date("2026-09-29T00:00:00Z"))
            let before = model.observationID
            model.focus(on: day)

            XCTAssertEqual(model.query, period)
            XCTAssertEqual(model.focusedQuery.since, day.start)
            XCTAssertEqual(model.focusedQuery.until, day.end)
            XCTAssertNotEqual(model.observationID, before)

            let restored = ReportScopeModel(defaults: defaults, currentTimeZone: requiredTimeZone("UTC"),
                                            now: { self.date("2026-09-30T09:30:00Z") })
            XCTAssertNil(restored.focusedInterval)
            XCTAssertEqual(restored.focusedQuery, restored.query)

            model.clearFocus()
            XCTAssertEqual(model.focusedQuery, period)
            XCTAssertEqual(model.observationID, before)
        }
    }

    func testFocusIsClippedToThePeriodAndIgnoredOutsideIt() {
        withDefaults { defaults in
            let model = ReportScopeModel(defaults: defaults, currentTimeZone: requiredTimeZone("UTC"),
                                         now: { self.date("2026-09-30T09:30:00Z") })
            model.selectPreset(.lastSevenDays)
            let since = model.query.since

            model.focus(on: DateInterval(start: date("2026-01-01T00:00:00Z"), end: date("2026-01-02T00:00:00Z")))
            XCTAssertNil(model.focusedInterval, "an interval outside the period is not selectable")

            model.focus(on: DateInterval(start: date("2026-01-01T00:00:00Z"), end: date("2026-09-25T00:00:00Z")))
            XCTAssertEqual(model.focusedQuery.since, since, "a partly overlapping interval is clipped")
        }
    }

    func testChangingPeriodTimezoneOrAccountDropsTheFocus() {
        withDefaults { defaults in
            let model = ReportScopeModel(defaults: defaults, currentTimeZone: requiredTimeZone("Europe/Moscow"),
                                         now: { self.date("2026-09-30T09:30:00Z") })
            let day = DateInterval(start: date("2026-09-28T00:00:00Z"), end: date("2026-09-29T00:00:00Z"))

            model.selectPreset(.lastSevenDays)
            model.focus(on: day)
            model.selectPreset(.lastThirtyDays)
            XCTAssertNil(model.focusedInterval)

            model.focus(on: day)
            model.selectTimeZone("Europe/Moscow")
            XCTAssertNil(model.focusedInterval)

            model.focus(on: day)
            model.selectAccount(.unknownOrMixed)
            XCTAssertNil(model.focusedInterval)
        }
    }

    func testFocusLeavingThePeriodAfterADayRolloverIsDropped() {
        withDefaults { defaults in
            var now = date("2026-09-30T09:30:00Z")
            let model = ReportScopeModel(defaults: defaults, currentTimeZone: requiredTimeZone("UTC"),
                                         now: { now })
            model.selectPreset(.lastSevenDays)
            model.focus(on: DateInterval(start: date("2026-09-24T00:00:00Z"), end: date("2026-09-25T00:00:00Z")))
            XCTAssertNotNil(model.focusedInterval)

            now = date("2026-10-10T09:30:00Z")
            model.refreshRelativePeriod()
            XCTAssertNil(model.focusedInterval)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "ReportScopeFocusTests.\(UUID().uuidString)"
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
