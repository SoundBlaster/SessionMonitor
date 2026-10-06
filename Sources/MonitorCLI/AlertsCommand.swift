import ArgumentParser
import Foundation
import MonitorCore
import MonitorPolicies
import MonitorRuntime

extension MonitorCommand {
    struct Alerts: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List or evaluate alerts built from existing analytics signals.",
            subcommands: [AlertList.self, AlertEvaluate.self], defaultSubcommand: AlertList.self
        )
    }

    struct AlertList: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list", abstract: "List persisted alert state."
        )

        @OptionGroup var options: DatabaseOptions
        @Option(help: "Alert status to list: active, resolved or all.") var status: AlertStatusFilter = .active
        @Flag(help: "Emit stable structured JSON.") var json = false

        mutating func run() async throws {
            let monitor = try options.runtime()
            let records = try await monitor.alerts(status: AlertStatus(rawValue: status.rawValue))
            if json {
                try printJSON(records)
                return
            }
            if records.isEmpty { print("No \(status.rawValue == "all" ? "" : status.rawValue + " ")alerts.") }
            for record in records {
                printAlert(record)
            }
        }
    }

    /// One evaluation of the current signals. Committed transitions stay in the outbox, so a running
    /// app or `watch --alerts` still delivers them; this command only reports what changed.
    struct AlertEvaluate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "evaluate", abstract: "Evaluate current signals once and print alert transitions."
        )

        @OptionGroup var options: DatabaseOptions
        @Option(help: "Recent window for session signals, in hours (0.25...168).") var lookbackHours = 6.0
        @Flag(help: "Emit stable structured JSON.") var json = false

        mutating func validate() throws {
            guard (0.25...168).contains(lookbackHours) else {
                throw ValidationError("--lookback-hours must be between 0.25 and 168.")
            }
        }

        mutating func run() async throws {
            let monitor = try options.runtime()
            let watchdog = AlertWatchdog(
                monitor: monitor, center: AlertCenter(monitor: monitor),
                options: AlertWatchdogOptions(lookback: lookbackHours * 3_600)
            )
            let events = try await watchdog.evaluate()
            if json {
                try printJSON(events)
                return
            }
            if events.isEmpty { print("No alert changes.") }
            for event in events {
                let delivery = event.notify ? "notify" : "silent (\(event.suppression?.rawValue ?? "none"))"
                print("\(event.transition.rawValue.uppercased()) \(delivery)")
                printAlert(event.record)
            }
        }
    }
}

private func printAlert(_ record: AlertRecord) {
    let alert = record.candidate
    let formatter = ISO8601DateFormatter()
    print("[\(alert.severity.rawValue)] \(alert.title) (\(alert.source.rawValue)/\(alert.kind))")
    print("  \(alert.message)")
    let sessions = alert.sessionIDs.isEmpty ? "none" : alert.sessionIDs.joined(separator: ", ")
    print("  status=\(record.status.rawValue) sessions=\(sessions) occurrences=\(record.occurrences)")
    print("  raised=\(formatter.string(from: record.raisedAt)) last seen=\(formatter.string(from: record.lastSeenAt))")
}

enum AlertStatusFilter: String, ExpressibleByArgument, CaseIterable {
    case active
    case resolved
    case all
}
