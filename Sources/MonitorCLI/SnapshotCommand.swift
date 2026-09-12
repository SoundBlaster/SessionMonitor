import ArgumentParser
import Foundation
import MonitorCore

extension MonitorCommand {
    struct Snapshot: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Read a versioned query snapshot; optionally follow committed changes without importing."
        )
        @OptionGroup var options: DatabaseOptions
        @Option(help: "Inclusive ISO 8601 start timestamp.") var since: String?
        @Option(help: "Exclusive ISO 8601 end timestamp.") var until: String?
        @Option(help: "Timezone identifier for presentation; timestamps remain absolute.") var timeZone = "UTC"
        @Flag(help: "Emit the initial snapshot and committed changes as JSON lines, checking revision every second.")
        var follow = false

        mutating func run() async throws {
            let query = try UsageQuery(since: parseDate(since), until: parseDate(until), timeZoneIdentifier: timeZone)
            let monitor = try options.runtime()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let writer = try WatchOutput()
            if !follow {
                var line = try encoder.encode(await monitor.snapshot(query: query))
                line.append(10)
                try await writer.write(line)
                return
            }
            let stream = await monitor.snapshots(query: query)
            let output = Task {
                for try await snapshot in stream {
                    var line = try encoder.encode(snapshot)
                    line.append(10)
                    try await writer.write(line)
                }
            }
            let signals = WatchSignals { _ in output.cancel() }
            defer { signals.cancel() }
            do { try await output.value } catch is CancellationError { /* Graceful signal-driven shutdown. */ }
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
