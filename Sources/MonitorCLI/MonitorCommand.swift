import ArgumentParser
import Foundation
import MonitorCore
import MonitorPolicies
import MonitorRuntime

@main
struct MonitorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codex-monitor", abstract: "Inspect local Codex canonical request usage.",
        version: "0.1.0", subcommands: [Import.self, Report.self, Watch.self, Snapshot.self,
                                         Sessions.self, Inspect.self, Activity.self, Doctor.self, Quota.self]
            + [Profiles.self]
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
    struct Profiles: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "profiles", abstract: "Manage explicit account profile mappings.",
            subcommands: [ProfileMapRoot.self, ProfileList.self], defaultSubcommand: ProfileList.self
        )
    }

    struct ProfileMapRoot: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "map-root", abstract: "Map a homogeneous source root."
        )
        @OptionGroup var options: DatabaseOptions
        @Option(name: .long, help: "Source folder containing only one account profile.") var root: String
        @Option(name: .long, help: "Stable local profile ID.") var id: String
        @Option(name: .long, help: "Display label for this profile.") var label: String

        mutating func run() async throws {
            let url = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
                .resolvingSymlinksInPath().standardizedFileURL
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw ValidationError("--root must be an existing directory.")
            }
            let monitor = try options.runtime()
            let profile = try await monitor.assignAccountProfile(root: url, profileID: id, label: label)
            try printJSON(profile)
        }
    }

    struct ProfileList: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list", abstract: "List account profile mappings."
        )
        @OptionGroup var options: DatabaseOptions

        mutating func run() async throws {
            let monitor = try options.runtime()
            try printJSON(await monitor.accountProfiles())
        }
    }

    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Incrementally import JSONL files with atomic checkpoints."
        )
        @OptionGroup var options: DatabaseOptions
        @Argument(help: "Read-only JSONL file or recursive directory; includes *.jsonl and numeric *.jsonl.N archives.")
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
        static let configuration = CommandConfiguration(abstract: "Show account-scoped canonical usage.")
        @OptionGroup var options: DatabaseOptions
        @OptionGroup var queryOptions: UsageQueryOptions
        @Flag(help: "Emit structured JSON.") var json = false

        mutating func run() async throws {
            let runtime = try options.runtime()
            let query = try queryOptions.query()
            let snapshot = try await runtime.snapshot(query: query)
            let report = snapshot.report
            if json {
                try printJSON(report)
            } else {
                print("Account scope: \(query.accountScope.displayLabel)")
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
    }
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}
