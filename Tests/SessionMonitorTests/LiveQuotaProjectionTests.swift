import Foundation
import MonitorCore
@testable import MonitorPolicies
import Testing

struct LiveQuotaProjectionTests {
    static let now = Date(timeIntervalSince1970: 1_000_000)

    static func snapshot(
        _ index: Int, secondsAgo: TimeInterval, used: Double?, resetIn: TimeInterval = 7_200,
        scope: UsageAccountScopeState = .assigned, state: UsageLimitSnapshotState = .observed
    ) -> UsageLimitSnapshotObservation {
        UsageLimitSnapshotObservation(
            eventIdentity: "e\(index)", timestamp: now.addingTimeInterval(-secondsAgo), sourceLine: index,
            sourceContextSessionID: nil, sourceSchema: "test", state: state, scope: .account, limitID: "codex",
            limitName: nil, planType: nil, accountScopeID: scope == .unknown ? nil : "acct",
            accountProfileLabel: "Work", accountScopeState: scope,
            windows: [UsageLimitWindowObservation(
                slot: .primary, windowMinutes: 300, usedPercent: used, resetsAt: now.addingTimeInterval(resetIn)
            )]
        )
    }

    static func batch(_ snapshots: [UsageLimitSnapshotObservation]) throws -> AlertSignalBatch {
        LiveRules.quotaProjection(
            UsageLimitSnapshotReport(query: try UsageQuery(), generatedAt: now, snapshots: snapshots), now: now
        )
    }

    /// 20% → 30% → 39% over 29 minutes is ~39 pp/h, so the window is full ~90 minutes from now.
    static let steady = [
        snapshot(1, secondsAgo: 1_800, used: 20), snapshot(2, secondsAgo: 900, used: 30),
        snapshot(3, secondsAgo: 60, used: 39)
    ]

    @Test func projectsExhaustionBeforeReset() throws {
        let result = try Self.batch(Self.steady)
        let alert = try #require(result.candidates.first)
        #expect(alert.kind == "projected_exhaustion")
        #expect(alert.source == .quota)
        #expect(alert.severity == .warning)
        #expect(alert.sessionIDs.isEmpty)
        #expect(alert.accountScopeID == "acct")
        #expect(alert.evidence.inference.first?.source == "linear_projection")
        #expect(result.scopes.contains(LiveRules.quotaProjectionScope))
    }

    @Test func nearExhaustionIsAnError() throws {
        let result = try Self.batch([
            Self.snapshot(1, secondsAgo: 1_800, used: 80), Self.snapshot(2, secondsAgo: 900, used: 88),
            Self.snapshot(3, secondsAgo: 60, used: 95)
        ])
        #expect(result.candidates.first?.severity == .error)
    }

    @Test func staysQuietWhenWindowResetsFirstOrUsageIsFlat() throws {
        let resetsSoon = Self.steady.enumerated().map { index, snapshot in
            Self.snapshot(index, secondsAgo: Self.now.timeIntervalSince(snapshot.timestamp),
                          used: snapshot.windows[0].usedPercent, resetIn: 3_600)
        }
        let early = try Self.batch(resetsSoon)
        #expect(early.candidates.isEmpty)
        #expect(early.scopes.contains(LiveRules.quotaProjectionScope))

        let flat = try Self.batch([
            Self.snapshot(1, secondsAgo: 1_800, used: 30), Self.snapshot(2, secondsAgo: 60, used: 30)
        ])
        #expect(flat.candidates.isEmpty)
        #expect(flat.scopes.contains(LiveRules.quotaProjectionScope))
    }

    @Test func unknownDataNeitherAlertsNorResolves() throws {
        let cases: [[UsageLimitSnapshotObservation]] = [
            // Span shorter than ten minutes.
            [Self.snapshot(1, secondsAgo: 300, used: 20), Self.snapshot(2, secondsAgo: 60, used: 39)],
            // Newest observation is stale.
            [Self.snapshot(1, secondsAgo: 5_000, used: 20), Self.snapshot(2, secondsAgo: 3_000, used: 39)],
            // Unknown account scope could blend accounts.
            Self.steady.indices.map { Self.snapshot($0, secondsAgo: 1_800 - Double($0) * 900, used: 20 + Double($0) * 9,
                                                    scope: .unknown) },
            // Used percent fell inside one window.
            [Self.snapshot(1, secondsAgo: 1_800, used: 40), Self.snapshot(2, secondsAgo: 900, used: 30),
             Self.snapshot(3, secondsAgo: 60, used: 39)],
            // Incomplete snapshot.
            [Self.snapshot(1, secondsAgo: 1_800, used: 20), Self.snapshot(2, secondsAgo: 60, used: nil)],
            [Self.snapshot(1, secondsAgo: 1_800, used: 20), Self.snapshot(2, secondsAgo: 60, used: 39, state: .partial)]
        ]
        for snapshots in cases {
            let result = try Self.batch(snapshots)
            #expect(result.candidates.isEmpty)
            #expect(!result.scopes.contains(LiveRules.quotaProjectionScope))
        }
    }

    @Test func previousWindowObservationsDoNotCountTowardTheRate() throws {
        // The 90% observation belongs to the previous window (different reset time).
        let result = try Self.batch([
            Self.snapshot(1, secondsAgo: 1_800, used: 90, resetIn: 100),
            Self.snapshot(2, secondsAgo: 900, used: 30), Self.snapshot(3, secondsAgo: 60, used: 39)
        ])
        let alert = try #require(result.candidates.first)
        #expect(alert.evidence.observed.first?.detail.contains("2 observations") == true)
    }
}
