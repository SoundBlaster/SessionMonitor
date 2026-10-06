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
        let query = try UsageQuery(since: now.addingTimeInterval(-lookback))
        let snapshot = try snapshot(query: query)
        let id = try sessionID ?? store.latestSessionID(query: query)
        let summary = id.flatMap { id in snapshot.report.sessions.first { $0.id == id } }
        let sessionTimeline = try summary.map { try self.timeline(sessionID: $0.id, query: query) }
        let inputs = AgentStatusInputs(
            sessionID: id, summary: summary, timeline: sessionTimeline, activeAlerts: try alerts(status: .active),
            quota: try quotaPresentation(query: UsageQuery(), generatedAt: now), watermark: snapshot.watermark
        )
        return AgentStatusBuilder.build(inputs, now: now, recentWindow: recentWindow, lookback: lookback)
    }
}
