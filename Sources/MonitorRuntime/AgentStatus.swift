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

/// Result of one hook invocation: the status, how the session was matched and whether the
/// transcript import ran (it is skipped while another importer, such as the app watch, holds the lock).
public struct AgentHookResult: Sendable {
    public let report: AgentStatusReport
    public let match: AgentHookSessionMatch
    public let importedTranscript: Bool
}

extension SessionMonitor {
    /// Hook entry point. Freshens the hook's own rollout incrementally, matches the session by
    /// `session_id`, then by transcript path, and never selects an unrelated "latest" session.
    /// After its own import it evaluates alerts like the watch does after an import, so a standalone
    /// hook reports signals from the freshly imported turns and resolves stale ones.
    public func agentHook(
        _ input: AgentHookInput, now: Date = Date(), importTranscript: Bool = true,
        lookback: TimeInterval = 6 * 3_600, recentWindow: TimeInterval = 600
    ) async throws -> AgentHookResult {
        var imported = false
        let transcript = input.transcriptPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        if importTranscript, let transcript,
           (try? transcript.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            // Best effort: a busy importer (the running watch) already keeps the index fresh and
            // evaluates alerts itself.
            imported = (try? importDirectory(transcript)) != nil
        }
        if imported {
            // Events stay in the durable outbox for the app's sinks; the hook itself delivers nothing.
            // Watch-default options: a shorter hook lookback must not resolve alerts the watch keeps.
            let watchdog = AlertWatchdog(monitor: self, center: AlertCenter(monitor: self))
            try await watchdog.evaluate(now: now)
        }

        var match = AgentHookSessionMatch.none
        var sessionID = input.sessionID ?? ""
        if let id = input.sessionID, try store.hasSession(id) {
            match = .sessionID
        } else if let transcript,
                  let id = try store.sessionIDs(source: transcript.resolvingSymlinksInPath().path).first {
            match = .transcript
            sessionID = id
        }
        // An unmatched ID yields no session block, so only shared (account-wide) alerts are reported.
        let report = try agentStatus(
            sessionID: sessionID, now: now, lookback: lookback, recentWindow: min(recentWindow, lookback)
        )
        return AgentHookResult(report: report, match: match, importedTranscript: imported)
    }
}
