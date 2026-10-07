import Foundation
import MonitorCore

/// Query results an agent status is projected from.
public struct AgentStatusInputs: Sendable {
    public let sessionID: String?
    public let summary: SessionSummary?
    public let timeline: RequestTimeline?
    public let activeAlerts: [AlertRecord]
    public let quota: QuotaPresentationReport?
    public let watermark: QueryWatermark

    public init(
        sessionID: String?, summary: SessionSummary?, timeline: RequestTimeline?, activeAlerts: [AlertRecord],
        quota: QuotaPresentationReport?, watermark: QueryWatermark
    ) {
        self.sessionID = sessionID
        self.summary = summary
        self.timeline = timeline
        self.activeAlerts = activeAlerts
        self.quota = quota
        self.watermark = watermark
    }
}

/// Pure projection of existing query results into `AgentStatusReport`. It adds no detection rules.
public enum AgentStatusBuilder {
    /// Account-level and service alert sources that matter to every session.
    static let sharedSources: Set<AlertSource> = [.quota, .watch, .importDiagnostics]

    public static func build(
        _ inputs: AgentStatusInputs, now: Date, recentWindow: TimeInterval, lookback: TimeInterval
    ) -> AgentStatusReport {
        let sessionID = inputs.sessionID
        let summary = inputs.summary
        let timeline = inputs.timeline
        let watermark = inputs.watermark
        let index = AgentStatusReport.Index(
            revision: watermark.revision, committedAt: watermark.committedAt,
            ageSeconds: watermark.committedAt.map { max(0, now.timeIntervalSince($0)) }
        )
        let requests = (timeline?.points ?? [])
            .filter { $0.kind == .usageRequest }
            .sorted { $0.timestamp < $1.timestamp }

        let session = summary.map { summary in
            AgentStatusReport.Session(
                id: summary.id, model: summary.model, totals: summary.totals,
                firstRequestAt: requests.first?.timestamp, lastRequestAt: requests.last?.timestamp,
                idleSeconds: requests.last.map { max(0, now.timeIntervalSince($0.timestamp)) }
            )
        }
        let recent = timeline.map { timeline in
            recentActivity(timeline, now: now, window: recentWindow)
        }
        let alerts = inputs.activeAlerts.filter { record in
            guard record.status == .active else { return false }
            if sharedSources.contains(record.candidate.source) { return true }
            guard let sessionID else { return false }
            return record.candidate.sessionIDs.contains(sessionID)
        }.sorted { lhs, rhs in
            let left = lhs.candidate.severity.rank
            let right = rhs.candidate.severity.rank
            return left == right ? lhs.id < rhs.id : left > right
        }.map(AgentStatusReport.Alert.init)

        return AgentStatusReport(
            generatedAt: now, lookbackSeconds: lookback, index: index, session: session, recent: recent,
            alerts: alerts,
            quota: (inputs.quota?.windows ?? []).map(AgentStatusReport.Quota.init)
        )
    }

    public static func recentActivity(
        _ timeline: RequestTimeline, now: Date, window: TimeInterval
    ) -> AgentStatusReport.Recent {
        let start = now.addingTimeInterval(-window)
        let points = timeline.points.filter { $0.timestamp >= start && $0.timestamp <= now }
        let requests = points.filter { $0.kind == .usageRequest }
        let inputs = requests.map(\.inputTokens)
        let input: Int64? = inputs.contains(nil) ? nil : inputs.compactMap { $0 }.reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? Int64.max : sum
        }
        // Same wait definition as polling detection: explicit wait events and wait tool invocations
        // (calls only, so a call and its output are not counted twice).
        let waits = points.filter { point in
            if point.kind == .wait { return true }
            guard point.kind == .tool, point.evidence == "function_call" || point.evidence == "custom_tool_call"
            else { return false }
            return point.activityClass == .wait || point.activityClass == .waitThreads
        }
        return AgentStatusReport.Recent(
            windowSeconds: window, requests: requests.count, inputTokens: input,
            waits: waits.count, compactions: points.filter { $0.kind == .compaction }.count
        )
    }
}
