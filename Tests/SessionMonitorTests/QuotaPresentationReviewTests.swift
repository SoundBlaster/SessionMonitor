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
        #expect(presentation.windows[0].resetDiscontinuity?.previousUsedPercent == 20)
        #expect(presentation.windows[0].resetDiscontinuity?.previousResetsAt
            == Date(timeIntervalSince1970: 300))
        #expect(presentation.windows[0].resetDiscontinuity?.currentUsedPercent == 40)
        #expect(presentation.windows[0].resetDiscontinuity?.currentResetsAt
            == Date(timeIntervalSince1970: 500))
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

    @Test func keepsIdenticalQuotaEventsAndCoverageSeparateByAccountScope() throws {
        let snapshots = [
            quotaSnapshot(identity: "same-event", timestamp: 100, sourceLine: 1, used: 20, reset: 300,
                          scopeID: "profile:personal", profileID: "personal", profileLabel: "Personal"),
            quotaSnapshot(identity: "same-event", timestamp: 100, sourceLine: 1, used: 20, reset: 300,
                          scopeID: "profile:work", profileID: "work", profileLabel: "Work"),
            quotaSnapshot(identity: "work-unsupported", timestamp: 105, sourceLine: 2, used: nil, reset: nil,
                          scopeID: "profile:work", profileID: "work", profileLabel: "Work",
                          state: .unsupportedSchema, windows: []),
            quotaSnapshot(identity: "personal-partial", timestamp: 108, sourceLine: 3, used: nil, reset: nil,
                          scopeID: "profile:personal", profileID: "personal", profileLabel: "Personal",
                          state: .partial, windows: []),
            quotaSnapshot(identity: "unmapped", timestamp: 110, sourceLine: 2, used: nil, reset: nil,
                          scopeID: "mixed:/archive", scopeState: .mixed, state: .noWindowData, windows: [])
        ]
        let report = UsageLimitSnapshotReport(
            query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 110), snapshots: snapshots
        )
        let presentation = QuotaPresentationDecision().presentation(for: QuotaPresentationContext(report: report))

        #expect(presentation.windows.count == 2)
        #expect(Set(presentation.windows.compactMap(\.accountProfileID)) == ["personal", "work"])
        #expect(presentation.accountCoverages.count == 3)
        #expect(presentation.accountCoverages.first(where: { $0.accountProfileID == "personal" })?
            .coverage.state == .partial)
        let workCoverage = try #require(
            presentation.accountCoverages.first(where: { $0.accountProfileID == "work" })?.coverage
        )
        #expect(workCoverage.state == .partial)
        #expect(workCoverage.unsupportedSnapshots == 1)
        #expect(presentation.accountCoverages.first(where: { $0.accountScopeID == "mixed:/archive" })?
            .coverage.unknownReason == .noWindowData)
        #expect(presentation.coverage.snapshotsWithoutWindowData == 1)
    }

    @Test func decodesLegacyQuotaPresentationWithoutScopedCoverage() throws {
        let report = QuotaPresentationReport(
            query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 100),
            freshnessThresholdSeconds: 900, coverage: UsageLimitTelemetryCoverage(snapshots: []), windows: []
        )
        let encoded = try JSONEncoder().encode(report)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "accountCoverages")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(QuotaPresentationReport.self, from: legacy)
        #expect(decoded.accountCoverages.isEmpty)
        #expect(decoded.coverage == report.coverage)
    }

    private func quotaSnapshot(
        identity: String, timestamp: TimeInterval, sourceLine: Int, used: Double?, reset: TimeInterval?,
        limitName: String? = nil, scopeID: String? = nil, profileID: String? = nil,
        profileLabel: String? = nil, scopeState: UsageAccountScopeState = .unknown,
        state: UsageLimitSnapshotState = .observed, windows: [UsageLimitWindowObservation]? = nil
    ) -> UsageLimitSnapshotObservation {
        UsageLimitSnapshotObservation(
            eventIdentity: identity, timestamp: Date(timeIntervalSince1970: timestamp), sourceLine: sourceLine,
            sourceContextSessionID: "session", sourceSchema: "fixture", state: state,
            scope: .account, scopeIdentifier: "account-a", limitID: nil, limitName: limitName,
            planType: "fixture", accountScopeID: scopeID, accountProfileID: profileID,
            accountProfileLabel: profileLabel, accountScopeState: scopeState,
            windows: windows ?? [UsageLimitWindowObservation(
                slot: .primary, windowMinutes: 300, usedPercent: used,
                resetsAt: reset.map { Date(timeIntervalSince1970: $0) }
            )]
        )
    }
}
