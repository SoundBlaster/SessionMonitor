import Foundation
import MonitorCore
import MonitorPolicies
import MonitorRuntime
import MonitorStore
import Testing

struct AgentStatusTests {
    @Test func builderKeepsSessionAndSharedAlertsAndCountsRecentActivity() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let timeline = RequestTimeline(sessionID: "mine", query: try UsageQuery(), points: [
            Self.request("R1", at: 8_000, input: 5_000),
            Self.request("R2", at: 9_700, input: 1_000),
            Self.request("R3", at: 9_900, input: 2_000),
            Self.tool("W1", at: 9_800, evidence: "function_call", activity: .wait),
            Self.tool("W1-out", at: 9_801, evidence: "function_call_output", activity: .wait),
            RequestTimelinePoint(id: "C1", sessionID: "mine", timestamp: Date(timeIntervalSince1970: 9_850),
                                 kind: .compaction)
        ])
        let report = AgentStatusBuilder.build(AgentStatusInputs(
            sessionID: "mine",
            summary: SessionSummary(id: "mine", model: "fixture",
                                    totals: UsageTotals(requests: 3, inputTokens: 8_000, cachedInputTokens: 6_000)),
            timeline: timeline,
            activeAlerts: [
                Self.alert("anomaly|polling|mine", source: .anomaly, sessions: ["mine"], severity: .warning),
                Self.alert("anomaly|polling|other", source: .anomaly, sessions: ["other"], severity: .error),
                Self.alert("quota|remaining|weekly", source: .quota, sessions: [], severity: .error),
                Self.alert("resolved", source: .watch, sessions: [], severity: .error, status: .resolved)
            ],
            quota: nil, watermark: QueryWatermark(databaseID: "db", revision: 7,
                                                  committedAt: Date(timeIntervalSince1970: 9_990))
        ), now: now, recentWindow: 600, lookback: 3_600)

        #expect(report.alerts.map(\.key) == ["quota|remaining|weekly", "anomaly|polling|mine"])
        #expect(report.highestSeverity == .error)
        #expect(report.session?.lastRequestAt == Date(timeIntervalSince1970: 9_900))
        #expect(report.session?.idleSeconds == 100)
        #expect(report.session?.cacheHitRatio == 0.75)
        #expect(report.recent == AgentStatusReport.Recent(
            windowSeconds: 600, requests: 2, inputTokens: 3_000, waits: 1, compactions: 1
        ))
        #expect(report.index.ageSeconds == 10)
    }

    @Test func recentInputIsUnknownWhenAnyRequestLacksIt() throws {
        let timeline = RequestTimeline(sessionID: "mine", query: try UsageQuery(), points: [
            Self.request("R1", at: 990, input: 100), Self.request("R2", at: 995, input: nil)
        ])
        let recent = AgentStatusBuilder.recentActivity(timeline, now: Date(timeIntervalSince1970: 1_000), window: 60)
        #expect(recent.requests == 2)
        #expect(recent.inputTokens == nil)
    }

    @Test func runtimeUsesNewestSessionAndReportsItsAlerts() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "usage.sqlite")
        let now = Date()
        let store = try UsageStore(url: url)
        for (session, offset) in [("older", -1_800.0), ("newer", -120.0)] {
            var rollout = ParsedRollout()
            rollout.records = [UsageRecord(
                responseID: "\(session)-1", sessionID: session, turnID: "T",
                timestamp: now.addingTimeInterval(offset), model: "fixture", inputTokens: 1_000,
                cachedInputTokens: 900, outputTokens: 10, sourceLine: 1
            )]
            rollout.provenance = SessionProvenance(sessionID: session, models: ["fixture"])
            try store.replace(source: session, rollout: rollout)
        }
        _ = try store.applyAlertEvaluation(AlertEvaluation(scopes: [], candidates: [AlertCandidate(
            key: "anomaly|repetitive_polling|newer", scope: AlertScope("anomaly:session:newer"), source: .anomaly,
            kind: "repetitive_polling", severity: .warning, title: "Repetitive polling", message: "Fixture.",
            sessionIDs: ["newer"]
        )], observedAt: now))

        let monitor = try SessionMonitor(databaseURL: url)
        let latest = try await monitor.agentStatus(now: now, lookback: 3_600, recentWindow: 600)
        #expect(latest.session?.id == "newer")
        #expect(latest.session?.requests == 1)
        #expect(latest.recent?.requests == 1)
        #expect(latest.alerts.map(\.key) == ["anomaly|repetitive_polling|newer"])

        let older = try await monitor.agentStatus(sessionID: "older", now: now, lookback: 3_600)
        #expect(older.session?.id == "older")
        #expect(older.alerts.isEmpty)

        let missing = try await monitor.agentStatus(sessionID: "absent", now: now, lookback: 3_600)
        #expect(missing.session == nil)
        #expect(missing.recent == nil)

        // The window ends at `now`: a request at now - 120 s is outside a status generated 200 s earlier.
        let earlier = try await monitor.agentStatus(now: now.addingTimeInterval(-200), lookback: 3_600)
        #expect(earlier.session?.id == "older")

        let clamped = try await monitor.agentStatus(now: now, lookback: 300, recentWindow: 3_600)
        #expect(clamped.recent?.windowSeconds == 300)
    }

    @Test func watchAlertsAreReportedWithoutPaths() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let record = AlertRecord(
            candidate: AlertCandidate(
                key: "watch|unhealthy|/Users/someone/.codex/sessions", scope: AlertScope("watch:/Users/someone"),
                source: .watch, kind: "unhealthy", severity: .warning, title: "Session watch needs attention",
                message: "Watch for sessions is recovering: /Users/someone/.codex/sessions denied"
            ),
            status: .active, firstSeenAt: now, raisedAt: now, lastSeenAt: now
        )
        let alert = AgentStatusReport.Alert(record)
        #expect(alert.key == "watch|unhealthy")
        #expect(!alert.message.contains("/"))
        #expect(!alert.message.contains("sessions"))
    }

    private static func request(_ id: String, at seconds: TimeInterval, input: Int64?) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: "mine", timestamp: Date(timeIntervalSince1970: seconds), kind: .usageRequest,
            responseID: id, inputTokens: input
        )
    }

    private static func tool(
        _ id: String, at seconds: TimeInterval, evidence: String, activity: ActivityToolClass
    ) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: "mine", timestamp: Date(timeIntervalSince1970: seconds), kind: .tool,
            evidence: evidence, activityClass: activity
        )
    }

    private static func alert(
        _ key: String, source: AlertSource, sessions: [String], severity: DiagnosticSeverity,
        status: AlertStatus = .active
    ) -> AlertRecord {
        let now = Date(timeIntervalSince1970: 9_000)
        return AlertRecord(
            candidate: AlertCandidate(
                key: key, scope: AlertScope(key), source: source, kind: "fixture", severity: severity,
                title: key, message: "Fixture.", sessionIDs: sessions
            ),
            status: status, firstSeenAt: now, raisedAt: now, lastSeenAt: now
        )
    }
}
