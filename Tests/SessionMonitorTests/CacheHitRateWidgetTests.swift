import Foundation
import MonitorCore
import XCTest

final class CacheHitRateWidgetTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "UTC") ?? .current
    private let reference = Date(timeIntervalSince1970: 1_725_000_000)

    func testPeriodRateIsWeightedInsteadOfMeanOfSessionRates() throws {
        let report = makeReport([
            observation(hoursBeforeReference: 1, session: "large", input: 900, cached: 900),
            observation(hoursBeforeReference: 1, session: "small", input: 100, cached: 0)
        ])

        XCTAssertEqual(try XCTUnwrap(report.periodCacheHitRate), 90, accuracy: 0.0001)
        XCTAssertNotEqual(report.periodCacheHitRate, 50)
    }

    func testBucketsDoNotExposeSessionOrModelIdentity() {
        let report = makeReport([
            observation(hoursBeforeReference: 2, session: "sensitive-session-id", input: 100, cached: 90),
            observation(hoursBeforeReference: 2, session: "another-id", input: 100, cached: 80)
        ])

        XCTAssertEqual(report.sessionCount, 2)
        XCTAssertEqual(report.buckets.count, 1)
        XCTAssertEqual(report.buckets[0].sampleCount, 2)
        XCTAssertFalse(String(describing: report.buckets[0]).contains("sensitive-session-id"))
    }

    func testPartialCoverageSuppressesPeriodRate() {
        let report = makeReport([
            observation(hoursBeforeReference: 1, session: "known", input: 100, cached: 90),
            observation(hoursBeforeReference: 1, session: "unknown", input: 100, cached: nil)
        ])

        XCTAssertEqual(report.availability, .partialCoverage(unknownObservationCount: 1))
        XCTAssertNil(report.periodCacheHitRate)
    }

    func testZeroInputIsNotApplicable() {
        let report = makeReport([
            observation(hoursBeforeReference: 1, session: "zero", input: 0, cached: 0)
        ])

        XCTAssertEqual(report.availability, .notApplicable)
        XCTAssertNil(report.periodCacheHitRate)
        XCTAssertTrue(report.buckets.isEmpty)
    }

    func testInsufficientSamplesUsesMinMaxAndNoOutliers() throws {
        let report = makeReport([
            observation(hoursBeforeReference: 1, session: "first", input: 100, cached: 80),
            observation(hoursBeforeReference: 1, session: "second", input: 100, cached: 95)
        ])
        let bucket = try XCTUnwrap(report.buckets.first)

        XCTAssertTrue(bucket.usesMinMaxFallback)
        XCTAssertEqual(bucket.lower, 80, accuracy: 0.0001)
        XCTAssertEqual(bucket.upper, 95, accuracy: 0.0001)
        XCTAssertTrue(bucket.outliers.isEmpty)
    }

    func testPreviousEqualPeriodProvidesPercentagePointDelta() throws {
        let report = makeReport([
            observation(hoursBeforeReference: 1, session: "current", input: 100, cached: 90),
            observation(hoursBeforeReference: 25, session: "previous", input: 100, cached: 80)
        ])

        XCTAssertEqual(try XCTUnwrap(report.periodCacheHitRate), 90, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(report.comparisonDeltaPercentagePoints), 10, accuracy: 0.0001)
    }

    func testDailyBucketsUseConfiguredTimeZoneCalendarBoundaries() {
        let report = CacheHitRateWidgetBuilder.build(
            observations: [
                observation(hoursBeforeReference: 2, session: "one", input: 100, cached: 90),
                observation(hoursBeforeReference: 26, session: "two", input: 100, cached: 80)
            ],
            period: .last7Days,
            referenceDate: reference,
            timeZone: timeZone
        )

        XCTAssertEqual(report.buckets.count, 2)
        XCTAssertTrue(report.buckets.allSatisfy { $0.end.timeIntervalSince($0.start) <= 24 * 60 * 60 })
    }

    private func makeReport(_ observations: [CacheHitRateObservation]) -> CacheHitRateWidgetReport {
        CacheHitRateWidgetBuilder.build(
            observations: observations,
            period: .last24Hours,
            referenceDate: reference,
            timeZone: timeZone
        )
    }

    private func observation(hoursBeforeReference: Double, session: String, input: Int64,
                             cached: Int64?) -> CacheHitRateObservation {
        CacheHitRateObservation(
            timestamp: reference.addingTimeInterval(-hoursBeforeReference * 60 * 60),
            sessionID: session,
            cacheableInputTokens: input,
            cachedInputTokens: cached
        )
    }
}
