import ArgumentParser
import Foundation
import MonitorCore
import MonitorRuntime

extension MonitorCommand {
    struct Sessions: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List imported sessions without changing accounting.")
        @OptionGroup var options: DatabaseOptions
        @OptionGroup var queryOptions: UsageQueryOptions
        @Option(help: "Sort by input, requests, cached, output or id.") var sort = "input"
        @Option(help: "Sort order: asc or desc.") var order = "desc"
        @Option(help: "Match one model exactly.") var model: String?
        @Option(help: "Match a session ID prefix.") var idPrefix: String?
        @Option(help: "Filter relationship state: knownRoot, attached, unknown, orphan, conflict or cycle.")
        var relationship: String?
        @Flag(help: "Emit stable structured JSON.") var json = false

        mutating func run() async throws {
            let query = try queryOptions.query()
            let sort = try parseSort()
            let descending = try parseOrder()
            let relationship = try parseRelationship()
            let monitor = try options.runtime()
            let result = try await monitor.listSessions(
                query: query, sort: sort, descending: descending,
                model: model, idPrefix: idPrefix, relationship: relationship
            )
            if json {
                try printJSON(result)
                return
            }
            for session in result.sessions {
                let ratio = session.cacheHitRatio.map { "\(Int(($0 * 100).rounded()))%" } ?? "unknown"
                print(
                    "\(session.id)  requests=\(session.totals.requests) input=\(session.totals.inputTokens) "
                        + "cached=\(session.totals.cachedInputTokens) output=\(session.totals.outputTokens) "
                        + "cache=\(ratio) provenance=\(session.provenanceState.rawValue) "
                        + "relationship=\(session.relationshipState.rawValue)"
                )
            }
        }

        private func parseSort() throws -> SessionListSort {
            guard let value = SessionListSort(rawValue: sort) else {
                throw ValidationError("Invalid --sort value: \(sort)")
            }
            return value
        }

        private func parseOrder() throws -> Bool {
            switch order.lowercased() {
            case "desc": return true
            case "asc": return false
            default: throw ValidationError("Invalid --order value: \(order); use asc or desc.")
            }
        }

        private func parseRelationship() throws -> SessionTreeState? {
            guard let relationship else { return nil }
            guard let state = SessionTreeState(rawValue: relationship) else {
                throw ValidationError("Invalid --relationship value: \(relationship)")
            }
            return state
        }
    }

    struct Inspect: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Explain one session using persisted usage and evidence."
        )
        @OptionGroup var options: DatabaseOptions
        @OptionGroup var queryOptions: UsageQueryOptions
        @Argument(help: "Exact session ID.") var sessionID: String
        @Flag(help: "Emit stable structured JSON.") var json = false

        mutating func run() async throws {
            let query = try queryOptions.query()
            let monitor = try options.runtime()
            guard let result = try await monitor.inspect(sessionID: sessionID, query: query) else {
                throw ValidationError("Session not found in the selected query: \(sessionID)")
            }
            if json {
                try printJSON(result)
                return
            }
            let ratio = result.cache.hitRatio.map { "\(Int(($0 * 100).rounded()))%" } ?? "unknown"
            let effort = result.effort.isEmpty ? "unknown" : result.effort.joined(separator: ", ")
            let clientVersion = result.clientVersion ?? "unknown"
            print("Session: \(result.sessionID)")
            print("Model: \(result.model)")
            print("Effort: \(effort)")
            print("Client version: \(clientVersion)")
            print(
                "Requests: \(result.totals.requests); input: \(result.totals.inputTokens); "
                    + "cached: \(result.totals.cachedInputTokens); output: \(result.totals.outputTokens)"
            )
            print(
                "Cache: \(ratio) (\(result.cache.status.rawValue), "
                    + "unknown requests: \(result.cache.unknownRequests))"
            )
            print("Timeline events: \(result.timeline.eventCounts)")
            print("Relationship: \(result.relationship.state.rawValue)")
            let evidenceSources = Set(result.evidence.observed.map(\.source)).sorted().joined(separator: ", ")
            print("Evidence sources: \(evidenceSources)")
            for limitation in result.evidence.limitations { print("Limitation: \(limitation)") }
        }
    }

    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Report read-only diagnostic findings for imported data."
        )
        @OptionGroup var options: DatabaseOptions
        @OptionGroup var queryOptions: UsageQueryOptions
        @Flag(help: "Emit stable structured JSON.") var json = false

        mutating func run() async throws {
            let query = try queryOptions.query()
            let monitor = try options.runtime()
            let report = try await monitor.doctor(query: query)
            if json {
                try printJSON(report)
                return
            }
            if report.findings.isEmpty {
                print("No diagnostic findings.")
                return
            }
            for finding in report.findings {
                print("[\(finding.severity.rawValue)] \(finding.id): \(finding.title)")
                print("  \(finding.explanation)")
                let affectedSessions = finding.affectedSessions.joined(separator: ", ")
                print("  confidence=\(finding.confidence.rawValue) sessions=\(affectedSessions)")
                print("  next: \(finding.suggestedNextAction)")
            }
        }
    }
}
