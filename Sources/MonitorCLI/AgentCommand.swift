import ArgumentParser
import Foundation
import MonitorCore
import MonitorRuntime

extension MonitorCommand {
    struct Agent: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Compact monitor data for an agent working in a session (tool, hook or mod).",
            subcommands: [AgentStatusCommand.self, AgentHookCommand.self], defaultSubcommand: AgentStatusCommand.self
        )
    }

    /// Read-only by default. `--evaluate` first commits an alert evaluation (without draining the
    /// outbox, so a running app still notifies). `--fail-on` lets hooks branch on the exit code.
    struct AgentStatusCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "status",
            abstract: "Usage, recent activity, active alerts and quota for one session.",
            discussion: "Without --session, the session with the newest request in the lookback window "
                + "is used. Exit code 2 means an active alert reached --fail-on."
        )

        @OptionGroup var options: DatabaseOptions
        @Option(help: "Session ID; defaults to the most recently active session.") var session: String?
        @Option(help: "Window for session usage, in hours (0.25...168).") var lookbackHours = 24.0
        @Option(help: "Window for recent activity, in minutes (1...1440).") var recentMinutes = 10.0
        @Flag(help: "Evaluate alert signals before reporting.") var evaluate = false
        @Option(help: "Exit with code 2 when an active alert has at least this severity.")
        var failOn: AgentAlertThreshold?
        @Flag(help: "Emit stable structured JSON.") var json = false

        mutating func validate() throws {
            guard (0.25...168).contains(lookbackHours) else {
                throw ValidationError("--lookback-hours must be between 0.25 and 168.")
            }
            guard (1...1_440).contains(recentMinutes) else {
                throw ValidationError("--recent-minutes must be between 1 and 1440.")
            }
            guard recentMinutes <= lookbackHours * 60 else {
                throw ValidationError("--recent-minutes must not exceed the lookback window.")
            }
        }

        mutating func run() async throws {
            let monitor = try options.runtime()
            if evaluate {
                let watchdog = AlertWatchdog(monitor: monitor, center: AlertCenter(monitor: monitor))
                try await watchdog.evaluate()
            }
            let report = try await monitor.agentStatus(
                sessionID: session, lookback: lookbackHours * 3_600, recentWindow: recentMinutes * 60
            )
            if json {
                try printJSON(report)
            } else {
                printAgentStatus(report)
            }
            if let failOn, let highest = report.highestSeverity, highest.rank >= failOn.severity.rank {
                throw ExitCode(2)
            }
        }
    }
}

enum AgentAlertThreshold: String, ExpressibleByArgument, CaseIterable {
    case info, warning, error

    var severity: DiagnosticSeverity {
        switch self {
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }
}

private func printAgentStatus(_ report: AgentStatusReport) {
    let formatter = ISO8601DateFormatter()
    if let session = report.session {
        let hit = session.cacheHitRatio.map { String(format: "%.1f%%", $0 * 100) } ?? "unknown"
        let idle = session.idleSeconds.map { "\(Int($0))s" } ?? "unknown"
        print("Session \(session.id) (\(session.model)): \(session.requests) requests, input \(session.inputTokens), "
              + "output \(session.outputTokens), cache hit \(hit) [\(session.cacheCoverage.rawValue)], idle \(idle)")
    } else {
        print("No session with canonical usage in the last \(Int(report.lookbackSeconds / 3_600))h.")
    }
    if let recent = report.recent {
        let input = recent.inputTokens.map(String.init) ?? "unknown"
        print("Last \(Int(recent.windowSeconds / 60))m: \(recent.requests) requests, input \(input), "
              + "\(recent.waits) waits, \(recent.compactions) compactions")
    }
    for quota in report.quota {
        let remaining = quota.remainingPercent.map { String(format: "%.0f%%", $0) } ?? "unknown"
        let reset = quota.resetsAt.map { formatter.string(from: $0) } ?? "unknown"
        print("Quota \(quota.window.rawValue): \(remaining) remaining, resets \(reset) [\(quota.freshness.rawValue)]")
    }
    if report.alerts.isEmpty { print("No active alerts.") }
    for alert in report.alerts {
        print("[\(alert.severity.rawValue)] \(alert.title): \(alert.message)")
    }
    let age = report.index.ageSeconds.map { "\(Int($0))s ago" } ?? "never"
    print("Index revision \(report.index.revision), committed \(age).")
}
