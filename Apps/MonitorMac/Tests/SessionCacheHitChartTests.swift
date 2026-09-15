import Foundation
import MonitorCore
import MonitorPolicies
import XCTest
@testable import SessionMonitor

@MainActor
final class SessionCacheHitChartTests: XCTestCase {
    func testDatumUsesPolicyForBelowAtAndAboveThreshold() throws {
        let policy = CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: 50))
        let data = SessionCacheHitChartDatum.make(
            sessions: [
                session("below", cachedInputTokens: 0),
                session("at", cachedInputTokens: 50),
                session("above", cachedInputTokens: 100)
            ],
            provenance: [:],
            policy: policy
        )

        XCTAssertEqual(data.map(\.id), ["below", "at", "above"])
        XCTAssertEqual(data.map(\.visualState), [.belowThreshold, .known, .known])
        XCTAssertEqual(data.map(\.valueLabel), ["0.0%", "50.0%", "100.0%"])
        XCTAssertEqual(data.map(\.statusLabel), ["Below threshold", "At threshold", "Above threshold"])
        XCTAssertTrue(data[0].accessibilityValue.contains("Below threshold"))
        XCTAssertTrue(data[1].accessibilityValue.contains("At threshold"))
        XCTAssertTrue(data[2].accessibilityValue.contains("Above threshold"))
    }

    func testUnknownPartialZeroInputAndNoRequestsUseNeutralUnavailableState() throws {
        let policy = CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: 80))
        let data = SessionCacheHitChartDatum.make(
            sessions: [
                SessionSummary(id: "unknown", model: "model", totals: UsageTotals(
                    requests: 1, inputTokens: 100, cachedInputTokens: -1
                )),
                SessionSummary(id: "partial", model: "model", totals: UsageTotals(
                    requests: 2, inputTokens: 100, cachedInputTokens: 50, unknownCacheRequests: 1
                )),
                SessionSummary(id: "zero", model: "model", totals: UsageTotals(requests: 1)),
                SessionSummary(id: "none", model: "model", totals: UsageTotals())
            ],
            provenance: [:],
            policy: policy
        )

        XCTAssertEqual(data.map(\.visualState), Array(repeating: .unavailable, count: 4))
        XCTAssertEqual(data.map(\.cacheHitPercent), [Double?](repeating: nil, count: 4))
        XCTAssertEqual(
            data.map(\.statusLabel),
            ["Unknown cache coverage", "Partial cache coverage", "Zero input tokens", "No canonical requests"]
        )
        XCTAssertTrue(data.allSatisfy { $0.accessibilityValue.hasPrefix("Unavailable.") })
    }

    func testChangingValidatedThresholdReevaluatesDataWithoutChangingSessions() throws {
        let sessions = [session("same", cachedInputTokens: 60)]
        let first = SessionCacheHitChartDatum.make(
            sessions: sessions,
            provenance: [:],
            policy: CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: 80))
        )
        let second = SessionCacheHitChartDatum.make(
            sessions: sessions,
            provenance: [:],
            policy: CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: 50))
        )

        XCTAssertEqual(first[0].id, second[0].id)
        XCTAssertEqual(first[0].cacheHitPercent, second[0].cacheHitPercent)
        XCTAssertEqual(first[0].visualState, .belowThreshold)
        XCTAssertEqual(second[0].visualState, .known)
        XCTAssertEqual(second[0].statusLabel, "Above threshold")
    }

    func testEmptyDataAndLargeListKeepOneDatumPerSessionAndUniqueShortLabels() throws {
        let policy = CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: 80))
        XCTAssertTrue(SessionCacheHitChartDatum.make(sessions: [], provenance: [:], policy: policy).isEmpty)

        let longName = String(repeating: "Long model name ", count: 5)
        let sessions = (0..<250).map { index in
            session("session-\(index)", cachedInputTokens: Int64(index % 101))
        }
        var provenance: [String: SessionProvenance] = [:]
        provenance["session-0"] = SessionProvenance(sessionID: "session-0", displayName: longName)
        provenance["session-1"] = SessionProvenance(sessionID: "session-1", displayName: longName)

        let data = SessionCacheHitChartDatum.make(sessions: sessions, provenance: provenance, policy: policy)

        XCTAssertEqual(data.count, sessions.count)
        XCTAssertEqual(Set(data.map(\.id)).count, sessions.count)
        XCTAssertEqual(Set(data.map(\.axisLabel)).count, data.count)
        XCTAssertTrue(data[0].axisLabel.contains("…"))
        XCTAssertTrue(data[1].axisLabel.hasSuffix("#2"))
    }

    func testLargeSessionChartUsesBoundedViewportAndSparseAxisContract() throws {
        let policy = CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: 80))
        let sessions = (0..<250).map { index in
            session("session-\(index)", cachedInputTokens: Int64(index % 101))
        }

        for count in [192, 250, 512] {
            XCTAssertLessThanOrEqual(SessionCacheHitChartLayout.axisMarkCount(for: count), 8)
            XCTAssertLessThanOrEqual(
                SessionCacheHitChartLayout.axisMarkIndices(startingAt: 0, count: count).count,
                8
            )
            XCTAssertLessThanOrEqual(SessionCacheHitChartLayout.visibleYDomainLength(for: count), 8)
            XCTAssertLessThanOrEqual(SessionCacheHitChartLayout.chartHeight(for: count), 220)
            XCTAssertLessThanOrEqual(SessionCacheHitChartLayout.chartViewportHeight(for: count), 248)
        }

        measure(metrics: [XCTClockMetric()]) {
            let data = SessionCacheHitChartDatum.make(sessions: sessions, provenance: [:], policy: policy)
            XCTAssertEqual(data.count, 250)
        }
    }

    func testDatumIdentityRoutesChartSelectionToTheMatchingSession() throws {
        let sessions = [session("first", cachedInputTokens: 0), session("second", cachedInputTokens: 100)]
        let policy = CacheHitThresholdPolicy(threshold: try CacheHitThreshold(percent: 80))
        let data = SessionCacheHitChartDatum.make(sessions: sessions, provenance: [:], policy: policy)
        let selectedID = data[1].id

        XCTAssertEqual(selectedID, "second")
        XCTAssertNotEqual(selectedID, data[0].id)
    }

    private func session(_ id: String, cachedInputTokens: Int64) -> SessionSummary {
        SessionSummary(id: id, model: "model", totals: UsageTotals(
            requests: 1, inputTokens: 100, cachedInputTokens: cachedInputTokens
        ))
    }
}
