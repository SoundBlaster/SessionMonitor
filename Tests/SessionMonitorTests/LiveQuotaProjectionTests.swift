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
        // A raised candidate always evaluates its own per-series scope.
        let scopes = result.evaluation(at: Self.now).scopes
        #expect(scopes.count == 1)
        #expect(scopes.first?.id.hasPrefix("quota:projection:") == true)
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
        #expect(early.scopes.count == 1)

        let flat = try Self.batch([
            Self.snapshot(1, secondsAgo: 1_800, used: 30), Self.snapshot(2, secondsAgo: 60, used: 30)
        ])
        #expect(flat.candidates.isEmpty)
        #expect(flat.scopes.count == 1)
    }

    @Test func unknownDataNeitherAlertsNorResolves() throws {
        let cases: [[UsageLimitSnapshotObservation]] = [
            // Span shorter than ten minutes.
            [Self.snapshot(1, secondsAgo: 300, used: 20), Self.snapshot(2, secondsAgo: 60, used: 39)],
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
            #expect(result.scopes.isEmpty)
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

    @Test func stalePaceAndPassedResetsResolveButConflictsDoNot() throws {
        // No fresh observation: the pace is not live any more, so the series is evaluated and quiet.
        let stale = try Self.batch([
            Self.snapshot(1, secondsAgo: 5_000, used: 20), Self.snapshot(2, secondsAgo: 3_000, used: 39)
        ])
        #expect(stale.candidates.isEmpty)
        #expect(stale.scopes.count == 1)
        // Same-time observations with the same used percent but different resets are ambiguous.
        let ambiguous = try Self.batch(Self.steady + [Self.snapshot(9, secondsAgo: 60, used: 39, resetIn: 9_000)])
        #expect(ambiguous.candidates.isEmpty)
        #expect(ambiguous.scopes.isEmpty)
    }

    @Test func scopesAreIsolatedPerSeriesAndAbsentSeriesResolve() throws {
        // A known second series must not resolve the alert of an unknown one.
        let unknownScope = Self.steady.indices.map { index in
            Self.snapshot(index, secondsAgo: 1_800 - Double(index) * 900, used: 20 + Double(index) * 9, scope: .unknown)
        }
        let mixed = try Self.batch(Self.steady + unknownScope)
        #expect(mixed.candidates.count == 1)
        #expect(mixed.evaluation(at: Self.now).scopes.count == 1)
        // An alerting series that no longer has any observation in the report is evaluated and quiet.
        let report = UsageLimitSnapshotReport(query: try UsageQuery(), generatedAt: Self.now, snapshots: [])
        let absent = LiveRules.quotaProjection(report, now: Self.now, activeSeriesIDs: ["gone"])
        #expect(absent.scopes == [LiveRules.quotaProjectionScope("gone")])
        #expect(LiveRules.quotaProjection(report, now: Self.now).scopes.isEmpty)
    }
}

/// The quota requirements are Specifications too, judged one at a time.
struct LiveQuotaProjectionSpecsTests {
    private static func context(_ snapshots: [UsageLimitSnapshotObservation]) -> QuotaProjectionContext {
        QuotaProjectionContext(
            series: snapshots.flatMap { snapshot in
                snapshot.windows.map { QuotaWindowCandidate(snapshot: snapshot, window: $0) }
            },
            now: LiveQuotaProjectionTests.now, configuration: LiveRuleConfiguration()
        )
    }

    @Test func eachRequirementIsIndependent() {
        let steady = Self.context(LiveQuotaProjectionTests.steady)
        #expect(HasKnownNewestObservationSpec().isSatisfiedBy(steady))
        #expect(IsLiveProjectionSpec().isSatisfiedBy(steady))
        #expect(HasUnambiguousNewestSpec().isSatisfiedBy(steady))
        #expect(HasProjectionSpanSpec().isSatisfiedBy(steady))
        #expect(IsMonotonicUsageSpec().isSatisfiedBy(steady))
        #expect(HasRisingUsageSpec().isSatisfiedBy(steady))
        #expect(ExhaustsBeforeResetSpec().isSatisfiedBy(steady))

        let flat = Self.context([
            LiveQuotaProjectionTests.snapshot(1, secondsAgo: 1_800, used: 30),
            LiveQuotaProjectionTests.snapshot(2, secondsAgo: 60, used: 30)
        ])
        #expect(!HasRisingUsageSpec().isSatisfiedBy(flat))
        let early = Self.context(LiveQuotaProjectionTests.steady.enumerated().map { index, snapshot in
            LiveQuotaProjectionTests.snapshot(
                index, secondsAgo: LiveQuotaProjectionTests.now.timeIntervalSince(snapshot.timestamp),
                used: snapshot.windows[0].usedPercent, resetIn: 3_600
            )
        })
        #expect(HasRisingUsageSpec().isSatisfiedBy(early))
        #expect(!ExhaustsBeforeResetSpec().isSatisfiedBy(early))
        let stale = Self.context([LiveQuotaProjectionTests.snapshot(1, secondsAgo: 5_000, used: 20)])
        #expect(!IsLiveProjectionSpec().isSatisfiedBy(stale))
        #expect(!HasProjectionSpanSpec().isSatisfiedBy(stale))
    }
}
