import ArgumentParser
import Foundation
import MonitorCore
import MonitorPolicies
import MonitorRuntime

@main
struct MonitorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codex-monitor", abstract: "Inspect local Codex canonical request usage.",
        version: "0.1.0", subcommands: [Import.self, Report.self]
    )
}

struct DatabaseOptions: ParsableArguments {
    @Option(help: "SQLite database path; defaults to Application Support/SessionMonitor/usage.sqlite.")
    var database: String?

    func runtime() throws -> SessionMonitor {
        let url = database.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return try SessionMonitor(databaseURL: url ?? SessionMonitor.defaultDatabaseURL)
    }
}

extension MonitorCommand {
    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Incrementally import JSONL files with atomic checkpoints."
        )
        @OptionGroup var options: DatabaseOptions
        @Argument(help: "A JSONL file or directory, recursively scanned. The source is read only.")
        var path: String
        @Flag(help: "Rebuild selected sources from the beginning, ignoring saved checkpoints.")
        var rescan = false

        mutating func run() async throws {
            let runtime = try options.runtime()
            let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let summary = try await runtime.importDirectory(source, rescan: rescan)
            try printJSON(summary)
        }
    }

    struct Report: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show globally deduplicated canonical usage.")
        @OptionGroup var options: DatabaseOptions
        @Option(help: "Inclusive ISO 8601 start timestamp.") var since: String?
        @Option(help: "Exclusive ISO 8601 end timestamp.") var until: String?
        @Flag(help: "Emit structured JSON.") var json = false

        mutating func run() async throws {
            let runtime = try options.runtime()
            let report = try await runtime.report(since: parseDate(since), until: parseDate(until))
            if json {
                try printJSON(report)
            } else {
                print("Confirmed canonical requests: \(report.totals.requests)")
                print("Input: \(report.totals.inputTokens); cached known: \(report.totals.cachedInputTokens)")
                print("Output: \(report.totals.outputTokens); sessions: \(report.sessions.count)")
                let ratio = report.totals.cacheHitRatio.map { String(format: "%.2f%%", $0 * 100) } ?? "unknown"
                print("Cache hit: \(ratio)")
                print(CacheCoverageDecision().decide(report.totals) ?? "")
                print("Canonical only; legacy snapshots are not added. Diagnostics cover all imported sources.")
                for key in report.diagnostics.keys.sorted() {
                    print("  \(key): \(report.diagnostics[key, default: 0])")
                }
            }
        }

        private func parseDate(_ value: String?) throws -> Date? {
            guard let value else { return nil }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) { return date }
            guard let date = try? Date.ISO8601FormatStyle().parse(value) else {
                throw ValidationError("Invalid ISO 8601 timestamp: \(value)")
            }
            return date
        }
    }
}

private func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}
