import ArgumentParser
import Foundation
import MonitorCore
import MonitorPolicies
import MonitorRuntime

extension MonitorCommand {
    /// Hook adapter for Codex and Claude Code. Reads the hook JSON from stdin and prints
    /// `hookSpecificOutput.additionalContext` only when there is something worth the agent's context.
    /// It always exits 0: monitoring must never block or break the agent's turn.
    struct AgentHookCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "hook",
            abstract: "Hook adapter: read hook JSON on stdin, emit additionalContext with relevant alerts.",
            discussion: "Configure it for UserPromptSubmit (or SessionStart). Silent unless an active alert reaches "
                + "--min-severity. Never fails the hook: errors go to stderr and the exit code stays 0."
        )

        @OptionGroup var options: DatabaseOptions
        @Option(help: "Lowest alert severity worth injecting: info, warning or error.")
        var minSeverity: AgentAlertThreshold = .warning
        @Flag(help: "Always inject a one-paragraph status, even without alerts.") var always = false
        @Flag(help: "Do not import the hook's transcript before reporting.") var noImport = false
        @Option(help: "Window for session usage, in hours (0.25...168).") var lookbackHours = 6.0

        mutating func validate() throws {
            guard (0.25...168).contains(lookbackHours) else {
                throw ValidationError("--lookback-hours must be between 0.25 and 168.")
            }
        }

        mutating func run() async throws {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let input = (try? JSONDecoder().decode(AgentHookInput.self, from: data))
                ?? AgentHookInput(sessionID: nil, transcriptPath: nil, hookEventName: nil)
            do {
                let monitor = try options.runtime()
                let result = try await monitor.agentHook(
                    input, importTranscript: !noImport, lookback: lookbackHours * 3_600
                )
                guard let context = AgentHookContext.render(
                    result.report, match: result.match, minimumSeverity: minSeverity.severity, always: always
                ) else { return }
                let output = AgentHookOutput(
                    hookEventName: input.hookEventName ?? "UserPromptSubmit", additionalContext: context
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(output))
                FileHandle.standardOutput.write(Data([10]))
            } catch {
                FileHandle.standardError.write(Data("codex-monitor agent hook: \(error.localizedDescription)\n".utf8))
            }
        }
    }
}
