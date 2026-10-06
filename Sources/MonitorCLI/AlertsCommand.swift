import ArgumentParser
import Foundation
import MonitorCore
import MonitorRuntime

extension MonitorCommand {
    struct Alerts: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List persisted alert state; signals are evaluated by watch and other producers."
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
            let formatter = ISO8601DateFormatter()
            for record in records {
                let alert = record.candidate
                print("[\(alert.severity.rawValue)] \(alert.title) (\(alert.source.rawValue)/\(alert.kind))")
                print("  \(alert.message)")
                let sessions = alert.sessionIDs.isEmpty ? "none" : alert.sessionIDs.joined(separator: ", ")
                print("  status=\(record.status.rawValue) sessions=\(sessions) occurrences=\(record.occurrences)")
                print("  raised=\(formatter.string(from: record.raisedAt)) "
                      + "last seen=\(formatter.string(from: record.lastSeenAt))")
            }
        }
    }
}

enum AlertStatusFilter: String, ExpressibleByArgument, CaseIterable {
    case active
    case resolved
    case all
}
