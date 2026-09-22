import Foundation
import Testing
@testable import MonitorCore
@testable import MonitorPolicies

struct QuotaPresentationReviewTests {
    @Test func detectsResetAcrossUnknownObservation() throws {
        let snapshots = [
            quotaSnapshot(identity: "before", timestamp: 100, sourceLine: 1, used: 20, reset: 300),
            quotaSnapshot(identity: "unknown", timestamp: 150, sourceLine: 2, used: nil, reset: nil),
            quotaSnapshot(identity: "after", timestamp: 200, sourceLine: 3, used: 40, reset: 500)
        ]
        let report = UsageLimitSnapshotReport(
            query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 200), snapshots: snapshots
        )
        let presentation = try #require(QuotaPresentationDecision().decide(
            QuotaPresentationContext(report: report)
        ))

        #expect(presentation.windows.count == 1)
        #expect(presentation.windows[0].isResetDiscontinuity)
    }

    @Test func preservesEqualTimestampAmbiguity() throws {
        let snapshots = [
            quotaSnapshot(identity: "tie-a", timestamp: 100, sourceLine: 1, used: 20, reset: 300),
            quotaSnapshot(identity: "tie-b", timestamp: 100, sourceLine: 2, used: 80, reset: 500)
        ]
        let report = UsageLimitSnapshotReport(
            query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 100), snapshots: snapshots
        )
        let presentation = try #require(QuotaPresentationDecision().decide(
            QuotaPresentationContext(report: report)
        ))
        let window = try #require(presentation.windows.first)

        #expect(window.isAmbiguous)
        #expect(window.usedPercent == nil)
        #expect(window.remainingPercent == nil)
        #expect(window.resetsAt == nil)
        #expect(!window.isResetDiscontinuity)
    }

    @Test func keepsNamedLimitsWithoutIDsSeparate() throws {
        let snapshots = [
            quotaSnapshot(identity: "pool-a", timestamp: 100, sourceLine: 1, used: 20, reset: 300,
                          limitName: "pool-A"),
            quotaSnapshot(identity: "pool-b", timestamp: 200, sourceLine: 2, used: 80, reset: 500,
                          limitName: "pool-B")
        ]
        let report = UsageLimitSnapshotReport(
            query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 200), snapshots: snapshots
        )
        let presentation = try #require(QuotaPresentationDecision().decide(
            QuotaPresentationContext(report: report)
        ))

        #expect(presentation.windows.count == 2)
        #expect(Set(presentation.windows.compactMap(\.limitName)) == ["pool-A", "pool-B"])
        #expect(presentation.windows.allSatisfy { !$0.isResetDiscontinuity })
    }

    private func quotaSnapshot(
        identity: String, timestamp: TimeInterval, sourceLine: Int, used: Double?, reset: TimeInterval?,
        limitName: String? = nil
    ) -> UsageLimitSnapshotObservation {
        UsageLimitSnapshotObservation(
            eventIdentity: identity, timestamp: Date(timeIntervalSince1970: timestamp), sourceLine: sourceLine,
            sourceContextSessionID: "session", sourceSchema: "fixture", state: .observed,
            scope: .account, scopeIdentifier: "account-a", limitID: nil, limitName: limitName,
            planType: "fixture", windows: [UsageLimitWindowObservation(
                slot: .primary, windowMinutes: 300, usedPercent: used,
                resetsAt: reset.map { Date(timeIntervalSince1970: $0) }
            )]
        )
    }
}
