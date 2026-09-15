import Foundation
import MonitorCore
import MonitorPolicies
import XCTest
@testable import SessionMonitor

@MainActor
final class CacheHitThresholdTests: XCTestCase {
    func testThresholdValidationAcceptsBoundariesAndRejectsInvalidValues() throws {
        for value in [0.0, 50.0, 100.0] {
            XCTAssertNoThrow(try CacheHitThreshold(percent: value))
        }
        for value in [-0.01, 100.01, .nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try CacheHitThreshold(percent: value))
        }
    }

    func testPolicySeparatesBelowAtAndAboveThreshold() throws {
        let policy = CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: 50))
        XCTAssertEqual(
            policy.presentation(for: session(cached: 0)),
            .knownBelowThreshold(cacheHitPercent: 0, thresholdPercent: 50)
        )
        XCTAssertEqual(
            policy.presentation(for: session(cached: 50)),
            .knownAtThreshold(cacheHitPercent: 50, thresholdPercent: 50)
        )
        XCTAssertEqual(
            policy.presentation(for: session(cached: 100)),
            .knownAboveThreshold(cacheHitPercent: 100, thresholdPercent: 50)
        )
    }

    func testPolicyHandlesThresholdBoundariesAndCoverageStates() throws {
        for threshold in [0.0, 50.0, 100.0] {
            let policy = CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: threshold))
            let cached = Int64(threshold)
            XCTAssertEqual(
                policy.presentation(for: session(cached: cached)),
                .knownAtThreshold(cacheHitPercent: threshold, thresholdPercent: threshold)
            )
        }
        XCTAssertEqual(CacheHitThresholdPolicy(threshold: .default).presentation(for: SessionSummary(
            id: "unknown", model: "model", totals: UsageTotals()
        )), .noCanonicalRequests)
        XCTAssertEqual(CacheHitThresholdPolicy(threshold: .default).presentation(for: SessionSummary(
            id: "partial", model: "model", totals: UsageTotals(
                requests: 2, inputTokens: 100, cachedInputTokens: 50, unknownCacheRequests: 1
            )
        )), .partialCacheCoverage(unknownRequests: 1))
        XCTAssertEqual(CacheHitThresholdPolicy(threshold: .default).presentation(for: SessionSummary(
            id: "zero", model: "model", totals: UsageTotals(requests: 1)
        )), .zeroInput)
        XCTAssertEqual(CacheHitThresholdPolicy(threshold: .default).presentation(for: SessionSummary(
            id: "invalid", model: "model", totals: UsageTotals(requests: 1, inputTokens: 100, cachedInputTokens: -1)
        )), .unknown)
    }

    func testPolicyDoesNotMutateSummaryOrTotals() throws {
        let summary = session(cached: 50)
        let original = summary
        _ = CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: 80)).presentation(for: summary)
        XCTAssertEqual(summary, original)
    }

    func testSettingsPersistAndRecoverMissingOrCorruptedValues() {
        withDefaults { defaults in
            let first = CacheHitThresholdSettings(defaults: defaults)
            XCTAssertEqual(first.thresholdPercent, 80)
            first.input = "50"
            XCTAssertTrue(first.commitInput())
            let restored = CacheHitThresholdSettings(defaults: defaults)
            XCTAssertEqual(restored.thresholdPercent, 50)

            defaults.removeObject(forKey: CacheHitThresholdSettings.storageKey)
            XCTAssertEqual(CacheHitThresholdSettings(defaults: defaults).thresholdPercent, 80)
            defaults.set("broken", forKey: CacheHitThresholdSettings.storageKey)
            XCTAssertEqual(CacheHitThresholdSettings(defaults: defaults).thresholdPercent, 80)
            defaults.set(Double.nan, forKey: CacheHitThresholdSettings.storageKey)
            XCTAssertEqual(CacheHitThresholdSettings(defaults: defaults).thresholdPercent, 80)
        }
    }

    func testInvalidInputDoesNotChangeSavedOrActiveThreshold() {
        withDefaults { defaults in
            let settings = CacheHitThresholdSettings(defaults: defaults)
            settings.input = "50"
            XCTAssertTrue(settings.commitInput())
            for invalid in ["", "-1", "101", "NaN", "infinity"] {
                settings.input = invalid
                XCTAssertFalse(settings.commitInput())
                XCTAssertEqual(settings.thresholdPercent, 50)
                XCTAssertEqual(defaults.double(forKey: CacheHitThresholdSettings.storageKey), 50)
            }
        }
    }

    private func session(cached: Int64) -> SessionSummary {
        SessionSummary(id: "session", model: "model", totals: UsageTotals(
            requests: 1, inputTokens: 100, cachedInputTokens: cached
        ))
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "CacheHitThresholdTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Could not create isolated UserDefaults")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
