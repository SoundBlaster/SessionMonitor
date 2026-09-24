import Foundation
import MonitorCore
import MonitorPolicies
import Testing

struct QuotaAnomalyPolicyTests {
    @Test func detectsRateOutlierAfterMatchedRobustBaselineAndNeverAttributesSession() throws {
        let report = try Self.report(
            ratesPerHour: [0.8, 0.9, 1, 1.1, 1.2, 20], elapsedHours: [1, 2, 1, 3, 1, 0.5]
        )

        let results = try Self.evaluate(report)
        let finding = try #require(results.first { $0.outcome == .sharpShift })
        #expect(finding.rateChangePercentagePointsPerHour == 20)
        #expect(finding.baselineMedianPercentagePointsPerHour == 1)
        #expect((finding.robustZScore ?? 0) >= 3)
        #expect(finding.evidence.observed.flatMap(\.sessionIDs).isEmpty)
        #expect(finding.sessionAttribution == .notApplicable)
        #expect(finding.evidence.limitations.contains { $0.contains("never attributed") })
    }

    @Test func reportsStableUsageOnlyAfterEnoughComparableIntervals() throws {
        let results = try Self.evaluate(try Self.report(ratesPerHour: [0.8, 0.9, 1, 1.1, 1.2, 1.05]))
        #expect(results.count == 1)
        #expect(results.first?.outcome == .stableUsage)
    }

    @Test func resetChangeIsExplicitAndNeverComparedAcrossBoundary() throws {
        let report = try Self.report(ratesPerHour: [0.8, 0.9, 1, 1.1, 1.2, 20], resetAfter: 4)

        let results = try Self.evaluate(report)
        #expect(results.contains { $0.outcome == .resetDiscontinuity })
        #expect(!results.contains { $0.outcome == .sharpShift })
    }

    @Test func insufficientHistoryIsUnknown() throws {
        let report = try Self.report(ratesPerHour: [1, 1, 1])
        let results = try Self.evaluate(report)
        #expect(results.contains { $0.outcome == .unknown && $0.reason == .insufficientHistory })
    }

    @Test func zeroMADDoesNotTurnAnUnscorableChangeIntoAnomaly() throws {
        let report = try Self.report(ratesPerHour: [1, 1, 1, 1, 1, 20])
        let results = try Self.evaluate(report)
        #expect(results.contains { $0.outcome == .unknown && $0.reason == .zeroMedianAbsoluteDeviation })
        #expect(!results.contains { $0.outcome == .sharpShift })
    }

    @Test func unknownAccountScopeIsNotApplicable() throws {
        let report = try Self.report(ratesPerHour: [1], scopeState: .mixed)
        let results = try Self.evaluate(report)
        #expect(results.contains { $0.outcome == .notApplicable && $0.reason == .unknownAccountScope })
    }

    @Test func staleAndPartialSnapshotsProduceExplicitUnknowns() throws {
        let staleReport = try Self.report(ratesPerHour: [1], generatedAtOffset: 3_600)
        let stale = try Self.evaluate(staleReport)
        #expect(stale.contains { $0.outcome == .unknown && $0.reason == .staleObservation })

        let partial = try Self.evaluate(try Self.report(ratesPerHour: [1], snapshotState: .partial))
        #expect(partial.contains { $0.outcome == .unknown && $0.reason == .incompleteCoverage })

        let unsupported = try Self.evaluate(try Self.report(ratesPerHour: [1], snapshotState: .unsupportedSchema))
        #expect(unsupported.contains { $0.outcome == .unknown && $0.reason == .unsupportedSnapshot })
    }

    @Test func conflictingSameTimestampAndMissingResetAreUnknown() throws {
        let conflict = try Self.report(ratesPerHour: [1], duplicateConflict: true)
        #expect(try Self.evaluate(conflict).contains { $0.reason == .ambiguousObservation })

        let missingReset = try Self.report(ratesPerHour: [1], missingReset: true)
        #expect(try Self.evaluate(missingReset).contains { $0.reason == .missingReset })
    }

    @Test func identicalWindowsInDifferentAccountsRemainSeparate() throws {
        let first = Self.snapshot(timestamp: 1, used: 10, accountScopeID: "account-a", line: 1)
        let second = Self.snapshot(timestamp: 1, used: 10, accountScopeID: "account-b", line: 1)
        let report = UsageLimitSnapshotReport(query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 2),
                                              snapshots: [first, second])

        let results = try Self.evaluate(report)
        #expect(results.count == 2)
        #expect(Set(results.compactMap(\.accountScopeID)) == ["account-a", "account-b"])
    }

    @Test func differentQuotaLimitsAndWindowLengthsAreNotCombined() throws {
        let first = Self.snapshot(timestamp: 10_000, used: 10, line: 1, limitID: "limit-a", windowMinutes: 300)
        let second = Self.snapshot(timestamp: 10_000, used: 90, line: 2, limitID: "limit-b", windowMinutes: 10_080)
        let report = UsageLimitSnapshotReport(query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 10_030),
                                              snapshots: [first, second])

        let results = try Self.evaluate(report)
        #expect(results.count == 2)
        #expect(!results.contains { $0.reason == .ambiguousObservation })
    }

    @Test func unchangedQuotaPollingIsStableAndNotUsageEvidence() throws {
        let results = try Self.evaluate(try Self.report(ratesPerHour: [0, 0, 0, 0, 0, 0]))
        #expect(results.contains { $0.outcome == .stableUsage })
        #expect(results.allSatisfy { $0.evidence.observed.flatMap(\.sessionIDs).isEmpty })
    }

    @Test func noSnapshotsStillProduceUnknownOutcome() throws {
        let report = UsageLimitSnapshotReport(query: try UsageQuery(), generatedAt: Date(), snapshots: [])
        #expect(try Self.evaluate(report).first?.reason == .noSnapshots)
    }

    @Test func diagnosticReportDecodesWithoutQuotaAssessments() throws {
        let report = DiagnosticReport(query: try UsageQuery(), findings: [])
        let encoded = try JSONEncoder().encode(report)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "quotaAssessments")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        #expect(try JSONDecoder().decode(DiagnosticReport.self, from: legacy).quotaAssessments.isEmpty)
    }

    private static func evaluate(_ report: UsageLimitSnapshotReport) throws -> [QuotaAnomalyAssessment] {
        try #require(QuotaAnomalyDecision().decide(QuotaAnomalyContext(report: report)))
    }

    private static func report(
        ratesPerHour: [Double], elapsedHours: [Double]? = nil, resetAfter: Int? = nil,
        scopeState: UsageAccountScopeState = .assigned, snapshotState: UsageLimitSnapshotState = .observed,
        generatedAtOffset: TimeInterval = 30, duplicateConflict: Bool = false, missingReset: Bool = false
    ) throws -> UsageLimitSnapshotReport {
        let intervals = elapsedHours ?? Array(repeating: 1, count: ratesPerHour.count)
        var timestamp: TimeInterval = 10_000
        var used = 20.0
        var snapshots = [snapshot(
            timestamp: timestamp, used: used, line: 1, reset: Date(timeIntervalSince1970: 200_000),
            scopeState: scopeState, snapshotState: snapshotState, missingReset: missingReset
        )]
        for (index, rate) in ratesPerHour.enumerated() {
            timestamp += intervals[index] * 3_600
            used += rate * intervals[index]
            let reset = resetAfter.map { index >= $0
                ? Date(timeIntervalSince1970: 300_000) : Date(timeIntervalSince1970: 200_000)
            } ?? Date(timeIntervalSince1970: 200_000)
            snapshots.append(snapshot(
                timestamp: timestamp, used: used, line: index + 2,
                reset: reset,
                scopeState: scopeState, snapshotState: snapshotState,
                missingReset: missingReset
            ))
        }
        if duplicateConflict, let latest = snapshots.last {
            snapshots.append(snapshot(
                timestamp: latest.timestamp.timeIntervalSince1970, used: (latest.windows[0].usedPercent ?? 0) + 1,
                line: snapshots.count + 1
            ))
        }
        let generatedAt = Date(timeIntervalSince1970: timestamp + generatedAtOffset)
        return UsageLimitSnapshotReport(query: try UsageQuery(), generatedAt: generatedAt, snapshots: snapshots)
    }

    private static func snapshot(
        timestamp: TimeInterval, used: Double, accountScopeID: String = "account-a", line: Int,
        reset: Date? = Date(timeIntervalSince1970: 200_000),
        scopeState: UsageAccountScopeState = .assigned,
        snapshotState: UsageLimitSnapshotState = .observed, missingReset: Bool = false,
        limitID: String = "primary-limit", windowMinutes: Int64 = 300
    ) -> UsageLimitSnapshotObservation {
        UsageLimitSnapshotObservation(
            eventIdentity: "event-\(line)", timestamp: Date(timeIntervalSince1970: timestamp),
            sourceLine: line, sourceContextSessionID: "context-session-\(line)", sourceSchema: "fixture-v1",
            state: snapshotState, scope: .account, scopeIdentifier: nil, limitID: limitID,
            limitName: "Primary", planType: nil, accountScopeID: accountScopeID,
            accountProfileID: "profile-\(accountScopeID)", accountProfileLabel: accountScopeID,
            accountScopeState: scopeState, windows: [UsageLimitWindowObservation(
                slot: .primary, windowMinutes: windowMinutes, usedPercent: used, resetsAt: missingReset ? nil : reset
            )]
        )
    }
}
