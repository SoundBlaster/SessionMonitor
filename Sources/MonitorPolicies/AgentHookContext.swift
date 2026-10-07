import Foundation
import MonitorCore

/// Renders the short text a hook injects into the agent's context. Silent by default: without an
/// alert at or above `minimumSeverity` it returns `nil`, so routine turns cost no context.
public enum AgentHookContext {
    public static let characterLimit = 2_000

    public static func render(
        _ report: AgentStatusReport, match: AgentHookSessionMatch,
        minimumSeverity: DiagnosticSeverity = .warning, always: Bool = false
    ) -> String? {
        let alerts = report.alerts.filter { $0.severity.rank >= minimumSeverity.rank }
        guard always || !alerts.isEmpty else { return nil }

        var lines = ["SessionMonitor (local Codex usage monitor):"]
        for alert in alerts {
            lines.append("- [\(alert.severity.rawValue)] \(alert.title): \(alert.message)")
        }
        if alerts.isEmpty { lines.append("- No active alerts at \(minimumSeverity.rawValue) or above.") }
        if let session = report.session {
            let hit = session.cacheHitRatio.map { String(format: "%.0f%%", $0 * 100) } ?? "unknown"
            lines.append("This session: \(session.requests) requests, \(compact(session.inputTokens)) input tokens, "
                + "cache hit \(hit).")
        } else if match == .none {
            lines.append("This session is not a Codex session in the index; only account-wide alerts apply.")
        }
        if let recent = report.recent {
            let input = recent.inputTokens.map(compact) ?? "unknown"
            lines.append("Last \(Int(recent.windowSeconds / 60)) min: \(recent.requests) requests, \(input) input, "
                + "\(recent.waits) waits, \(recent.compactions) compactions.")
        }
        if let lowest = report.quota.compactMap({ quota in quota.remainingPercent.map { (quota, $0) } })
            .min(by: { $0.1 < $1.1 }) {
            lines.append("Lowest quota window: \(lowest.0.window.rawValue) \(String(format: "%.0f", lowest.1))% "
                + "remaining (\(lowest.0.freshness.rawValue)).")
        }
        let text = lines.joined(separator: "\n")
        return text.count <= characterLimit ? text : String(text.prefix(characterLimit - 1)) + "…"
    }

    static func compact(_ value: Int64) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: String(format: "%.1fK", Double(value) / 1_000)
        default: String(value)
        }
    }
}
