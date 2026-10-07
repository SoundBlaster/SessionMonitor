import Foundation

/// The JSON a Codex or Claude Code hook receives on stdin. Only the fields SessionMonitor needs;
/// unknown fields are ignored and every field is optional, so either client's payload decodes.
public struct AgentHookInput: Codable, Equatable, Sendable {
    public let sessionID: String?
    public let transcriptPath: String?
    public let hookEventName: String?
    public let cwd: String?

    public init(sessionID: String?, transcriptPath: String?, hookEventName: String?, cwd: String? = nil) {
        self.sessionID = sessionID
        self.transcriptPath = transcriptPath
        self.hookEventName = hookEventName
        self.cwd = cwd
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case hookEventName = "hook_event_name"
        case cwd
    }
}

/// How the hook's session was matched to the index.
public enum AgentHookSessionMatch: String, Codable, Sendable {
    /// `session_id` is an indexed Codex session.
    case sessionID = "session_id"
    /// `transcript_path` is an imported rollout; its session was used.
    case transcript
    /// Neither matched (for example a Claude Code session): only shared alerts are reported.
    case none
}

/// The response both clients accept for context injection:
/// `{"hookSpecificOutput": {"hookEventName": ..., "additionalContext": ...}}`.
public struct AgentHookOutput: Codable, Equatable, Sendable {
    public struct Specific: Codable, Equatable, Sendable {
        public let hookEventName: String
        public let additionalContext: String
    }

    public let hookSpecificOutput: Specific

    public init(hookEventName: String, additionalContext: String) {
        hookSpecificOutput = Specific(hookEventName: hookEventName, additionalContext: additionalContext)
    }
}
