import Foundation
import MonitorCore
import MonitorPolicies
import Testing

struct AlertSignalsTests {
    @Test func anomalyKeyIgnoresGrowingEvidenceAndCoversEvaluatedSessions() throws {
        let query = try UsageQuery()
        let first = DiagnosticReport(query: query, findings: [Self.finding(id: "repetitive_polling|busy|R1|10")])
        let grown = DiagnosticReport(query: query, findings: [Self.finding(id: "repetitive_polling|busy|R1,R2|10,12")])

        let before = AlertSignals.diagnostics(first, evaluatedSessions: ["busy", "quiet"])
        let after = AlertSignals.diagnostics(grown, evaluatedSessions: ["busy", "quiet"])
        #expect(before.candidates.map(\.key) == ["anomaly|repetitive_polling|busy"])
        #expect(after.candidates.map(\.key) == before.candidates.map(\.key))
        #expect(before.candidates.first?.source == .anomaly)
        #expect(before.candidates.first?.scope == AlertSignals.anomalyScope("busy"))
        #expect(before.scopes == [
            AlertSignals.anomalyScope("busy"), AlertSignals.anomalyScope("quiet"), AlertSignals.databaseScope
        ])
    }

    @Test func databaseWideFindingsUseStableIDs() throws {
        let report = DiagnosticReport(query: try UsageQuery(), findings: [DiagnosticFinding(
            id: "malformed_source_evidence", severity: .error, title: "Malformed source evidence",
            explanation: "Fixture.", evidence: DiagnosticEvidence(), confidence: .high,
            affectedSessions: [], suggestedNextAction: "Fix it."
        )])
        let batch = AlertSignals.diagnostics(report, evaluatedSessions: [])
        let candidate = try #require(batch.candidates.first)
        #expect(candidate.key == "diagnostics|malformed_source_evidence")
        #expect(candidate.source == .importDiagnostics)
        #expect(candidate.scope == AlertSignals.databaseScope)
        #expect(candidate.severity == .error)
    }

    @Test func onlyRecentSharpShiftsAlertOncePerSeries() {
        let now = Date(timeIntervalSince1970: 10_000)
        let batch = AlertSignals.quotaShifts([
            Self.assessment(outcome: .sharpShift, observedAt: 9_900, rate: 30),
            Self.assessment(outcome: .sharpShift, observedAt: 9_000, rate: 20),
            Self.assessment(outcome: .sharpShift, observedAt: 1_000, rate: 50, limit: "old"),
            Self.assessment(outcome: .unknown, observedAt: 9_950, limit: "unknown"),
            Self.assessment(outcome: .stableUsage, observedAt: 9_950, limit: "stable")
        ], now: now)

        #expect(batch.candidates.count == 1)
        #expect(batch.candidates.first?.key == "quota|sharp_shift|account-1|codex|primary|300")
        #expect(batch.candidates.first?.message.contains("30.0 pp/h") == true)
        #expect(batch.candidates.first?.sessionIDs.isEmpty == true)
        #expect(batch.scopes == [AlertSignals.quotaShiftScope])
    }

    @Test func lowRemainingQuotaUsesSeverityAndOnlyKeepsUncertainWindowsAlreadyActive() throws {
        let report = QuotaPresentationReport(
            query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 0), freshnessThresholdSeconds: 900,
            coverage: UsageLimitTelemetryCoverage(snapshots: []), windows: [
                Self.window(id: "low", used: 85, freshness: .current),
                Self.window(id: "critical", used: 97, freshness: .current),
                Self.window(id: "stale-active", used: 90, freshness: .stale),
                Self.window(id: "stale-new", used: 90, freshness: .stale),
                Self.window(id: "ambiguous-active", used: nil, freshness: .current, ambiguous: true),
                Self.window(id: "healthy", used: 40, freshness: .current)
            ]
        )
        let batch = AlertSignals.quotaRemaining(report, activeKeys: [
            "quota|remaining|stale-active", "quota|remaining|ambiguous-active", "quota|remaining|healthy"
        ])
        let byKey = Dictionary(uniqueKeysWithValues: batch.candidates.map { ($0.key, $0) })
        let uncertain = AnomalyCoverage.unknown(reason: "The latest quota observation is stale or ambiguous.")

        #expect(Set(byKey.keys) == [
            "quota|remaining|low", "quota|remaining|critical",
            "quota|remaining|stale-active", "quota|remaining|ambiguous-active"
        ])
        #expect(byKey["quota|remaining|low"]?.severity == .warning)
        #expect(byKey["quota|remaining|critical"]?.severity == .error)
        #expect(byKey["quota|remaining|stale-active"]?.coverage == uncertain)
        #expect(byKey["quota|remaining|ambiguous-active"]?.coverage == uncertain)
        #expect(byKey["quota|remaining|ambiguous-active"]?.message.contains("an unknown remaining") == true)
    }

    @Test func cacheThresholdIsInformationalAndSkipsUnknownCoverage() {
        let sessions = [
            SessionSummary(id: "low", model: "fixture",
                           totals: UsageTotals(requests: 2, inputTokens: 1_000, cachedInputTokens: 500)),
            SessionSummary(id: "high", model: "fixture",
                           totals: UsageTotals(requests: 2, inputTokens: 1_000, cachedInputTokens: 950)),
            SessionSummary(id: "unknown", model: "fixture",
                           totals: UsageTotals(requests: 2, inputTokens: 1_000, unknownCacheRequests: 1))
        ]
        let batch = AlertSignals.cacheThreshold(sessions)

        #expect(batch.candidates.map(\.key) == ["cache_threshold|low"])
        #expect(batch.candidates.first?.severity == .info)
        #expect(batch.candidates.first?.scope == AlertSignals.cacheScope("low"))
        #expect(batch.scopes.count == 3)
        #expect(AlertSignals.cacheScope("low") != AlertSignals.anomalyScope("low"))
    }

    static func finding(id: String) -> DiagnosticFinding {
        DiagnosticFinding(
            id: id, severity: .warning, title: "Repetitive polling", explanation: "Fixture.",
            evidence: DiagnosticEvidence(), confidence: .medium, affectedSessions: ["busy"],
            suggestedNextAction: "Add backoff.", coverage: .observed
        )
    }

    static func assessment(
        outcome: QuotaAnomalyOutcome, observedAt: TimeInterval, rate: Double? = nil, limit: String = "codex"
    ) -> QuotaAnomalyAssessment {
        QuotaAnomalyAssessment(
            id: "\(limit)-\(observedAt)", outcome: outcome, accountScopeID: "account-1",
            accountScopeState: .assigned, scope: .account, limitID: limit, slot: .primary, windowMinutes: 300,
            currentObservedAt: Date(timeIntervalSince1970: observedAt),
            rateChangePercentagePointsPerHour: rate, baselineMedianPercentagePointsPerHour: 2,
            evidence: DiagnosticEvidence()
        )
    }

    static func window(
        id: String, used: Double?, freshness: QuotaFreshnessState, ambiguous: Bool = false
    ) -> QuotaWindowPresentation {
        QuotaWindowPresentation(
            id: id, accountScopeID: "account-1", scope: .account, scopeIdentifier: nil, limitID: "codex",
            limitName: nil, planType: nil, slot: .primary, windowKind: .fiveHour, windowMinutes: 300,
            usedPercent: used, remainingPercent: used.map { 100 - $0 }, resetsAt: nil,
            observedAt: Date(timeIntervalSince1970: 0), freshness: QuotaFreshness(state: freshness, ageSeconds: 0),
            isResetDiscontinuity: false, isAmbiguous: ambiguous
        )
    }
}
