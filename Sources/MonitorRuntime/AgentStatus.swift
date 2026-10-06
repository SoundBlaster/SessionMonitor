import Foundation
import MonitorCore
import MonitorPolicies

extension SessionMonitor {
    /// Status for an agent's session. Without `sessionID`, the session with the newest request in the
    /// lookback window is used. Usage totals cover the lookback window; quota uses the latest
    /// observation per window. Read-only: it never imports, evaluates or delivers alerts.
    public func agentStatus(
        sessionID: String? = nil, now: Date = Date(), lookback: TimeInterval = 24 * 3_600,
        recentWindow: TimeInterval = 600
    ) throws -> AgentStatusReport {
        // Bounded at `now`, so future-dated (skewed or malformed) records never enter the window.
        let query = try UsageQuery(since: now.addingTimeInterval(-lookback), until: now)
        // Select before the snapshot: imports only add sessions, so a later snapshot still contains
        // the selected one even if another process commits in between (GRDB reads cannot nest).
        let id = try sessionID ?? store.latestSessionID(query: query)
        let snapshot = try snapshot(query: query)
        let summary = id.flatMap { id in snapshot.report.sessions.first { $0.id == id } }
        let sessionTimeline = try summary.map { try self.timeline(sessionID: $0.id, query: query) }
        let inputs = AgentStatusInputs(
            sessionID: id, summary: summary, timeline: sessionTimeline, activeAlerts: try alerts(status: .active),
            quota: try quotaPresentation(query: UsageQuery(), generatedAt: now), watermark: snapshot.watermark
        )
        // Recent activity cannot extend past the fetched timeline; the report states the effective window.
        return AgentStatusBuilder.build(
            inputs, now: now, recentWindow: min(recentWindow, lookback), lookback: lookback
        )
    }
}
