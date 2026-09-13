import Foundation
import MonitorCore

public struct RolloutDecoder: Sendable {
    public init() {}

    public func parse(_ url: URL) throws -> ParsedRollout {
        try parseIncrementally(url).rollout
    }

    public func parseIncrementally(_ url: URL, checkpoint: Data? = nil) throws -> SourceImport {
        let source = try RolloutFile(url: url)
        let previous = checkpoint.flatMap { try? JSONDecoder().decode(DecoderCheckpoint.self, from: $0) }
        var cursor = JSONLCursor()
        var state = DecodeState()
        var mode = SourceImportMode.replaced
        if let previous, previous.isUsable(for: source.version) {
            if previous.version == source.version, let checkpoint {
                try source.validateSnapshot()
                return SourceImport(rollout: ParsedRollout(), checkpoint: checkpoint, mode: .unchanged, bytesRead: 0)
            }
            // Growth of the same file is treated as append-only; --rescan repairs prefix rewrites.
            if source.version.size > previous.version.size {
                cursor = previous.cursor
                state.context = previous.state
                mode = .appended
            }
        }
        let progress = try JSONLReader().read(source, from: cursor) { data, line in
            guard let data else {
                state.result.diagnostics["oversizedLines", default: 0] += 1
                return
            }
            state.consume(data, line: line)
        }
        state.result.provenance = state.provenance()
        if progress.partialTail { state.result.diagnostics["partialTails"] = 1 }
        try source.validateSnapshot()
        let next = DecoderCheckpoint(version: source.version, cursor: progress.cursor,
                                     state: state.context)
        return SourceImport(rollout: state.result, checkpoint: try JSONEncoder().encode(next),
                            mode: mode, bytesRead: source.bytesRead)
    }
}

private struct DecoderCheckpoint: Codable {
    var schemaVersion = 3
    let version: RolloutFileVersion
    let cursor: JSONLCursor
    let state: DecoderContext

    func isUsable(for current: RolloutFileVersion) -> Bool {
        schemaVersion == 3 && version.identity == current.identity && current.size >= version.size
            && cursor.offset <= version.size && cursor.line >= 0 && UInt64(cursor.line) <= cursor.offset
    }
}

/// Normalized accounting context only. Raw unfinished lines remain in the source file.
private struct DecoderContext: Codable {
    var sessionID: String?
    var created: Date?
    var nativeTurns = Set<String>()
    var models: [String: String] = [:]
    var efforts: [String: String] = [:]
    var rootSessionID: String?
    var parentSessionID: String?
    var agentNickname: String?
    var agentPath: String?
    var originator: String?
    var clientVersion: String?
    var modelProvider: String?
    var threadSource: String?
}

private struct Header: Decodable {
    let type: String
}

private struct Envelope: Decodable {
    let timestamp: String
    let type: String
    let payload: Payload
}

private struct Payload: Decodable {
    let type: String?
    let id: String?
    let timestamp: String?
    let threadID: String?
    let turnID: String?
    let responseID: String?
    let startedAt: Int64?
    let model: String?
    let effort: String?
    let sessionID: String?
    let rootSessionID: String?
    let parentThreadID: String?
    let agentNickname: String?
    let agentPath: String?
    let originator: String?
    let clientVersion: String?
    let modelProvider: String?
    let threadSource: String?
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case type, id, timestamp, model, effort, usage, originator
        case threadID = "thread_id"
        case turnID = "turn_id"
        case responseID = "response_id"
        case startedAt = "started_at"
        case sessionID = "session_id"
        case rootSessionID = "root_session_id"
        case parentThreadID = "parent_thread_id"
        case agentNickname = "agent_nickname"
        case agentPath = "agent_path"
        case clientVersion = "cli_version"
        case modelProvider = "model_provider"
        case threadSource = "thread_source"
    }
}

private struct Usage: Decodable {
    let input: Int64
    let cached: Int64?
    let output: Int64
    let cacheWrite: Int64?
    let reasoning: Int64?
    let total: Int64?

    enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case cached = "cached_input_tokens"
        case output = "output_tokens"
        case cacheWrite = "cache_write_input_tokens"
        case reasoning = "reasoning_output_tokens"
        case total = "total_tokens"
    }

    var isValid: Bool {
        input >= 0 && output >= 0 && (cached.map { $0 >= 0 && $0 <= input } ?? true)
            && (cacheWrite.map { $0 >= 0 } ?? true) && (total.map { $0 >= 0 } ?? true)
            && (reasoning.map { $0 >= 0 && $0 <= output } ?? true)
    }
}

private struct DecodeState {
    var result = ParsedRollout()
    var context = DecoderContext()
    let decoder = JSONDecoder()

    mutating func consume(_ data: Data, line: Int) {
        do {
            let header = try decoder.decode(Header.self, from: data)
            if header.type == "session_meta" {
                context = DecoderContext()
            }
            guard ["session_meta", "turn_context", "event_msg", "token_usage_record"].contains(header.type)
            else {
                if !["response_item", "compacted"].contains(header.type) {
                    result.diagnostics["unknownRecordTypes", default: 0] += 1
                }
                return
            }
            let event = try decoder.decode(Envelope.self, from: data)
            try process(event, line: line)
        } catch {
            result.diagnostics["malformedRecords", default: 0] += 1
        }
    }

    mutating func process(_ event: Envelope, line: Int) throws {
        let payload = event.payload
        if event.type == "session_meta" {
            context.sessionID = payload.id
            context.created = try parseDate(payload.timestamp ?? event.timestamp)
            context.nativeTurns.removeAll()
            context.models.removeAll()
            context.efforts.removeAll()
            context.rootSessionID = payload.rootSessionID ?? payload.sessionID
            context.parentSessionID = payload.parentThreadID
            context.agentNickname = payload.agentNickname
            context.agentPath = payload.agentPath
            context.originator = payload.originator
            context.clientVersion = payload.clientVersion
            context.modelProvider = payload.modelProvider
            context.threadSource = payload.threadSource
        } else if event.type == "turn_context", let turn = payload.turnID {
            context.models[turn] = payload.model
            if let effort = payload.effort { context.efforts[turn] = effort }
        } else if event.type == "event_msg", payload.type == "task_started", let turn = payload.turnID {
            context.nativeTurns.remove(turn)
            if let started = payload.startedAt, let created = context.created,
               Double(started) >= floor(created.timeIntervalSince1970), !isSynthetic(turn) {
                context.nativeTurns.insert(turn)
            }
        } else if event.type == "event_msg", payload.type == "token_count" {
            result.diagnostics["legacySnapshotsNotCounted", default: 0] += 1
        } else if event.type == "token_usage_record" {
            try append(payload, timestamp: event.timestamp, line: line)
        }
    }

    mutating func append(_ payload: Payload, timestamp: String, line: Int) throws {
        guard let sessionID = context.sessionID, let created = context.created, payload.threadID == sessionID,
              let turn = payload.turnID, context.nativeTurns.contains(turn) else {
            result.diagnostics["unownedOrUnprovenRecords", default: 0] += 1
            return
        }
        let date = try parseDate(timestamp)
        guard date >= created else {
            result.diagnostics["replayedRecords", default: 0] += 1
            return
        }
        guard let response = payload.responseID, !response.isEmpty,
              let usage = payload.usage, usage.isValid else {
            result.diagnostics["invalidUsageOrIdentity", default: 0] += 1
            return
        }
        result.records.append(UsageRecord(
            responseID: response, sessionID: sessionID, turnID: turn, timestamp: date,
            model: context.models[turn] ?? "unknown", inputTokens: usage.input,
            cachedInputTokens: usage.cached, outputTokens: usage.output, sourceLine: line,
            cacheWriteInputTokens: usage.cacheWrite, reasoningOutputTokens: usage.reasoning, totalTokens: usage.total
        ))
    }

    func isSynthetic(_ turn: String) -> Bool {
        turn.hasPrefix("rollout-") && Int(turn.dropFirst("rollout-".count)) != nil
    }

    func parseDate(_ value: String) throws -> Date {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) { return date }
        return try Date.ISO8601FormatStyle().parse(value)
    }

    func provenance() -> SessionProvenance? {
        guard let sessionID = context.sessionID else { return nil }
        let kind: SessionRelationshipKind = context.threadSource == "subagent" ? .subagent : .unknown
        let relationship = (context.parentSessionID != nil || kind == .subagent)
            ? SessionRelationship(kind: kind, parentSessionID: context.parentSessionID)
            : nil
        return SessionProvenance(
            sessionID: sessionID,
            rootSessionID: context.rootSessionID,
            displayName: context.agentNickname,
            agentPath: context.agentPath,
            originator: context.originator,
            clientVersion: context.clientVersion,
            modelProvider: context.modelProvider,
            models: Array(Set(context.models.values.compactMap { $0 })).sorted(),
            efforts: Array(Set(context.efforts.values)).sorted(),
            relationship: relationship
        )
    }
}
