import CryptoKit
import Foundation
import MonitorCore

// swiftlint:disable cyclomatic_complexity function_parameter_count file_length

public struct RolloutDecoder: Sendable {
    public init() {}

    public func parse(_ url: URL) throws -> ParsedRollout {
        try parseIncrementally(url).rollout
    }

    /// Reads the source only to recover metadata for records already in the store.
    /// It deliberately does not decode or return usage records.
    public func parseMetadata(_ url: URL) throws -> SourceImport {
        let source = try RolloutFile(url: url)
        var state = DecodeState()
        let progress = try JSONLReader().read(source, from: JSONLCursor()) { data, line in
            guard let data else { return }
            state.consume(data, line: line, includeRecords: false)
        }
        state.result.provenance = state.provenance()
        try source.validateSnapshot()
        let next = DecoderCheckpoint(version: source.version, cursor: progress.cursor,
                                     state: state.context)
        return SourceImport(rollout: state.result, checkpoint: try JSONEncoder().encode(next),
                            mode: .replaced, bytesRead: source.bytesRead)
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
    var schemaVersion = 4
    let version: RolloutFileVersion
    let cursor: JSONLCursor
    let state: DecoderContext

    func isUsable(for current: RolloutFileVersion) -> Bool {
        schemaVersion == 4 && version.identity == current.identity
            && current.size >= version.size
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
    var legacyBaseline: LegacyUsage?

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try values.decodeIfPresent(String.self, forKey: .sessionID)
        created = try values.decodeIfPresent(Date.self, forKey: .created)
        nativeTurns = try values.decodeIfPresent(Set<String>.self, forKey: .nativeTurns) ?? []
        models = try values.decodeIfPresent([String: String].self, forKey: .models) ?? [:]
        efforts = try values.decodeIfPresent([String: String].self, forKey: .efforts) ?? [:]
        rootSessionID = try values.decodeIfPresent(String.self, forKey: .rootSessionID)
        parentSessionID = try values.decodeIfPresent(String.self, forKey: .parentSessionID)
        agentNickname = try values.decodeIfPresent(String.self, forKey: .agentNickname)
        agentPath = try values.decodeIfPresent(String.self, forKey: .agentPath)
        originator = try values.decodeIfPresent(String.self, forKey: .originator)
        clientVersion = try values.decodeIfPresent(String.self, forKey: .clientVersion)
        modelProvider = try values.decodeIfPresent(String.self, forKey: .modelProvider)
        threadSource = try values.decodeIfPresent(String.self, forKey: .threadSource)
        legacyBaseline = try values.decodeIfPresent(LegacyUsage.self, forKey: .legacyBaseline)
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID, created, nativeTurns, models, efforts, rootSessionID, parentSessionID,
             agentNickname, agentPath, originator, clientVersion, modelProvider, threadSource, legacyBaseline
    }
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
    let info: LegacyTokenCountInfo?
    let role: String?
    let name: String?
    let turnKind: String?
    let continuationKind: String?
    let eventKind: String?
    let internalChatMessageMetadataPassthrough: MessageMetadataPassthrough?

    var resolvedTurnID: String? {
        turnID ?? internalChatMessageMetadataPassthrough?.turnID
    }

    enum CodingKeys: String, CodingKey {
        case type, id, timestamp, model, effort, usage, info, originator, role, name
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
        case turnKind = "turn_kind"
        case continuationKind = "continuation_kind"
        case eventKind = "event_kind"
        case internalChatMessageMetadataPassthrough = "internal_chat_message_metadata_passthrough"
    }
}

private struct MessageMetadataPassthrough: Decodable {
    let turnID: String?

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
    }
}

private struct UsageLimitEventPayload: Decodable {
    let type: String?
    let rateLimits: RateLimitsPayload?
    let containsRateLimits: Bool
    let rateLimitsDecodeFailed: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case rateLimits = "rate_limits"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        containsRateLimits = values.contains(.rateLimits)
        do {
            rateLimits = try values.decodeIfPresent(RateLimitsPayload.self, forKey: .rateLimits)
            rateLimitsDecodeFailed = false
        } catch {
            rateLimits = nil
            rateLimitsDecodeFailed = true
        }
    }
}

private struct UsageLimitEventEnvelope: Decodable {
    let payload: UsageLimitEventPayload
}

private struct RateLimitsPayload: Decodable {
    let limitID: String?
    let limitName: String?
    let planType: String?
    let primary: RateLimitWindowPayload?
    let secondary: RateLimitWindowPayload?
    let individualLimit: RateLimitWindowPayload?
    let hasRecognizedFields: Bool
    let hasDecodeIssues: Bool

    enum CodingKeys: String, CodingKey {
        case limitID = "limit_id"
        case limitName = "limit_name"
        case planType = "plan_type"
        case primary
        case secondary
        case individualLimit = "individual_limit"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = Self.decode(String.self, from: values, forKey: .limitID)
        let name = Self.decode(String.self, from: values, forKey: .limitName)
        let plan = Self.decode(String.self, from: values, forKey: .planType)
        let primary = Self.decode(RateLimitWindowPayload.self, from: values, forKey: .primary)
        let secondary = Self.decode(RateLimitWindowPayload.self, from: values, forKey: .secondary)
        let individual = Self.decode(RateLimitWindowPayload.self, from: values, forKey: .individualLimit)
        limitID = id.value
        limitName = name.value
        planType = plan.value
        self.primary = primary.value
        self.secondary = secondary.value
        individualLimit = individual.value
        hasDecodeIssues = id.failed || name.failed || plan.failed
            || primary.failed || secondary.failed || individual.failed
            || primary.value?.hasDecodeIssues == true || secondary.value?.hasDecodeIssues == true
            || individual.value?.hasDecodeIssues == true
        hasRecognizedFields = values.contains(.limitID) || values.contains(.limitName)
            || values.contains(.planType) || values.contains(.primary) || values.contains(.secondary)
            || values.contains(.individualLimit)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type, from values: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) -> (value: Value?, failed: Bool) {
        guard values.contains(key) else { return (nil, false) }
        do {
            return (try values.decodeIfPresent(type, forKey: key), false)
        } catch {
            return (nil, true)
        }
    }
}

private struct RateLimitWindowPayload: Decodable {
    let usedPercent: Double?
    let windowMinutes: Int64?
    let resetsAt: Int64?
    let hasDecodeIssues: Bool

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case windowMinutes = "window_minutes"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let used = Self.decode(Double.self, from: values, forKey: .usedPercent)
        let duration = Self.decode(Int64.self, from: values, forKey: .windowMinutes)
        let reset = Self.decode(Int64.self, from: values, forKey: .resetsAt)
        usedPercent = used.value
        windowMinutes = duration.value
        resetsAt = reset.value
        hasDecodeIssues = used.failed || duration.failed || reset.failed
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type, from values: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys
    ) -> (value: Value?, failed: Bool) {
        guard values.contains(key) else { return (nil, false) }
        do {
            return (try values.decodeIfPresent(type, forKey: key), false)
        } catch {
            return (nil, true)
        }
    }

    func observation(slot: UsageLimitWindowSlot) -> UsageLimitWindowObservation {
        UsageLimitWindowObservation(
            slot: slot,
            windowMinutes: windowMinutes.flatMap { $0 > 0 ? $0 : nil },
            usedPercent: usedPercent.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            resetsAt: resetsAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        )
    }
}

private struct LegacyTokenCountInfo: Decodable {
    let totalTokenUsage: LegacyUsage?

    enum CodingKeys: String, CodingKey {
        case totalTokenUsage = "total_token_usage"
    }
}

private struct LegacyUsage: Codable {
    let input: Int64?
    let cached: Int64?
    let output: Int64?
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
        guard let input, let output, let total,
              input >= 0, output >= 0, total >= 0,
              cached.map({ $0 >= 0 && $0 <= input }) ?? true,
              cacheWrite.map({ $0 >= 0 }) ?? true,
              reasoning.map({ $0 >= 0 && $0 <= output }) ?? true else { return false }
        return true
    }

    var isZero: Bool {
        input == 0 && (cached == nil || cached == 0) && output == 0
            && (cacheWrite == nil || cacheWrite == 0) && (reasoning == nil || reasoning == 0) && total == 0
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

    mutating func consume(_ data: Data, line: Int, includeRecords: Bool = true) {
        do {
            let header = try decoder.decode(Header.self, from: data)
            if header.type == "session_meta" {
                context = DecoderContext()
            }
            let supportedTypes = ["session_meta", "turn_context", "event_msg", "token_usage_record",
                                  "response_item", "compacted"]
            guard supportedTypes.contains(header.type)
            else {
                if !["response_item", "compacted"].contains(header.type) {
                    result.diagnostics["unknownRecordTypes", default: 0] += 1
                }
                return
            }
            // These envelope types are known, but a missing payload is not a malformed
            // canonical record and must remain ignored for backwards-compatible diagnostics.
            guard data.contains(payloadMarker) || !["response_item", "compacted"].contains(header.type) else { return }
            let event = try decoder.decode(Envelope.self, from: data)
            try process(event, line: line, includeRecords: includeRecords)
            if event.type == "event_msg", event.payload.type == "token_count" {
                appendUsageLimitSnapshot(data, timestamp: event.timestamp, line: line)
            }
        } catch {
            result.diagnostics["malformedRecords", default: 0] += 1
        }
    }

    private var payloadMarker: Data { Data("\"payload\"".utf8) }

    mutating func process(_ event: Envelope, line: Int, includeRecords: Bool) throws {
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
            if includeRecords, let kind = explicitTurnKind(payload) {
                let evidence = payload.turnKind ?? payload.continuationKind ?? "turn_context"
                appendEvent(sessionID: context.sessionID, turnID: turn, timestamp: event.timestamp,
                            line: line, kind: kind, evidence: evidence)
            }
        } else if event.type == "event_msg", payload.type == "task_started", let turn = payload.turnID {
            context.nativeTurns.remove(turn)
            if let started = payload.startedAt, let created = context.created,
               Double(started) >= floor(created.timeIntervalSince1970), !isSynthetic(turn) {
                context.nativeTurns.insert(turn)
            }
        } else if event.type == "event_msg", payload.type == "token_count" {
            appendLegacyEstimate(payload.info?.totalTokenUsage, timestamp: event.timestamp, line: line)
        } else if event.type == "token_usage_record", includeRecords {
            try append(payload, timestamp: event.timestamp, line: line)
        } else if event.type == "compacted", includeRecords {
            appendEvent(sessionID: context.sessionID, turnID: payload.turnID, timestamp: event.timestamp,
                        line: line, kind: .compaction, evidence: "compacted")
        } else if event.type == "response_item", includeRecords {
            appendResponseEvent(payload, timestamp: event.timestamp, line: line)
        } else if event.type == "event_msg", includeRecords {
            appendMessageEvent(payload, timestamp: event.timestamp, line: line)
        }
    }

    mutating func appendLegacyEstimate(_ usage: LegacyUsage?, timestamp: String, line: Int) {
        guard let usage, usage.isValid, let date = try? parseDate(timestamp) else {
            result.diagnostics["legacyUnknownSnapshots", default: 0] += 1
            result.diagnostics["legacySnapshotsNotCounted", default: 0] += 1
            return
        }
        guard let baseline = context.legacyBaseline else {
            context.legacyBaseline = usage
            result.diagnostics["legacyPartialCoverage", default: 0] += 1
            return
        }
        if usage.isZero {
            context.legacyBaseline = usage
            result.diagnostics["legacyResets", default: 0] += 1
            return
        }
        guard let input = usage.input, let baselineInput = baseline.input,
              let output = usage.output, let baselineOutput = baseline.output,
              let total = usage.total, let baselineTotal = baseline.total,
              input >= baselineInput, output >= baselineOutput, total >= baselineTotal else {
            // A lower cumulative snapshot can be a reset or a late mirror. Without
            // an epoch/identity field, retaining it is not semantically safe.
            result.diagnostics["legacyReversedOrUncertain", default: 0] += 1
            return
        }
        let cached = usage.cached.flatMap { current -> Int64? in
            guard let previous = baseline.cached, current >= previous else { return nil }
            return current - previous
        }
        let cacheWrite = usage.cacheWrite.flatMap { current -> Int64? in
            guard let previous = baseline.cacheWrite, current >= previous else { return nil }
            return current - previous
        }
        let reasoning = usage.reasoning.flatMap { current -> Int64? in
            guard let previous = baseline.reasoning, current >= previous else { return nil }
            return current - previous
        }
        let deltaInput = input - baselineInput
        let deltaOutput = output - baselineOutput
        let deltaTotal = total - baselineTotal
        if deltaInput > 0 || deltaOutput > 0 || deltaTotal > 0 {
            result.legacyEstimates.append(LegacyUsageEstimate(
                sessionID: context.sessionID, timestamp: date, sourceLine: line,
                inputTokens: deltaInput, cachedInputTokens: cached,
                outputTokens: deltaOutput, cacheWriteInputTokens: cacheWrite,
                reasoningOutputTokens: reasoning, totalTokens: deltaTotal
            ))
        }
        context.legacyBaseline = usage
    }

    mutating func appendResponseEvent(_ payload: Payload, timestamp: String, line: Int) {
        let kind: TimelineEventKind?
        switch payload.type {
        case "message" where payload.role == "user": kind = .humanTurn
        case "function_call", "custom_tool_call", "custom_tool_call_output": kind = .tool
        case .some: kind = .unknown
        case .none: kind = nil
        }
        guard let kind, let sessionID = context.sessionID, let date = try? parseDate(timestamp) else { return }
        let classification = kind == .tool
            ? ActivityToolClass.classify(toolName: payload.name)
            : nil
        let turnID = payload.resolvedTurnID
        appendEvent(sessionID: sessionID, turnID: turnID, timestamp: date, line: line,
                    kind: kind, evidence: payload.type ?? "response_item", toolName: payload.name,
                    model: turnID.flatMap { context.models[$0] }, activityClass: classification)
    }

    mutating func appendMessageEvent(_ payload: Payload, timestamp: String, line: Int) {
        guard let sessionID = context.sessionID, let date = try? parseDate(timestamp) else { return }
        let rawType = payload.eventKind ?? payload.type
        let kind = explicitTurnKind(payload) ?? explicitMessageKind(rawType)
        guard let kind else {
            guard rawType != nil, rawType != "task_started", rawType != "token_count",
                  rawType != "item_completed", rawType != "task_complete" else { return }
            let turnID = payload.resolvedTurnID
            appendEvent(sessionID: sessionID, turnID: turnID, timestamp: date, line: line,
                        kind: .unknown, evidence: rawType ?? "event_msg", toolName: payload.name,
                        model: turnID.flatMap { context.models[$0] })
            return
        }
        let classification: ActivityToolClass?
        if kind == .tool {
            classification = ActivityToolClass.classify(toolName: payload.name)
        } else if kind == .wait {
            classification = .wait
        } else if kind == .goalTurn {
            classification = .goalContinuation
        } else {
            classification = nil
        }
        let turnID = payload.resolvedTurnID
        appendEvent(sessionID: sessionID, turnID: turnID, timestamp: date, line: line,
                    kind: kind, evidence: rawType ?? "event_msg", toolName: payload.name,
                    model: turnID.flatMap { context.models[$0] }, activityClass: classification)
    }

    mutating func appendEvent(sessionID: String?, turnID: String?, timestamp: String, line: Int,
                              kind: TimelineEventKind, evidence: String, toolName: String? = nil,
                              model: String? = nil, activityClass: ActivityToolClass? = nil) {
        guard let date = try? parseDate(timestamp) else { return }
        appendEvent(sessionID: sessionID, turnID: turnID, timestamp: date, line: line,
                    kind: kind, evidence: evidence, toolName: toolName, model: model,
                    activityClass: activityClass)
    }

    mutating func appendEvent(sessionID: String?, turnID: String?, timestamp: Date, line: Int,
                              kind: TimelineEventKind, evidence: String, toolName: String? = nil,
                              model: String? = nil, activityClass: ActivityToolClass? = nil) {
        guard let sessionID else { return }
        result.timelineEvents.append(TimelineSourceEvent(sessionID: sessionID, turnID: turnID,
                                                         timestamp: timestamp, sourceLine: line,
                                                         kind: kind, evidence: evidence,
                                                         toolName: toolName, model: model,
                                                         activityClass: activityClass))
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

private func explicitTurnKind(_ payload: Payload) -> TimelineEventKind? {
    let value = (payload.turnKind ?? payload.continuationKind)?.lowercased()
    switch value {
    case "human", "user", "human_turn", "user_turn": return .humanTurn
    case "goal", "goal_turn", "auto_continuation", "auto_continuation_turn": return .goalTurn
    default: return nil
    }
}

private func explicitMessageKind(_ value: String?) -> TimelineEventKind? {
    guard let value else { return nil }
    let normalized = value.lowercased()
    if ["compacted", "compaction", "context_compacted", "compaction_started"].contains(normalized) {
        return .compaction
    }
    if ["tool_call", "tool_started", "tool_completed"].contains(normalized) { return .tool }
    if ["wait", "wait_started", "wait_completed"].contains(normalized) { return .wait }
    if ["human_turn_started", "user_turn_started"].contains(normalized) { return .humanTurn }
    let goalTypes = ["goal_started", "goal_turn_started", "auto_continuation_started", "continuation_started"]
    if goalTypes.contains(normalized) { return .goalTurn }
    return nil
}

private extension DecodeState {
    var rateLimitsMarker: Data { Data("\"rate_limits\"".utf8) }

    mutating func appendUsageLimitSnapshot(_ data: Data, timestamp: String, line: Int) {
        guard data.range(of: rateLimitsMarker) != nil else { return }
        guard let date = try? parseDate(timestamp) else {
            result.diagnostics["unsupportedUsageLimitSchemas", default: 0] += 1
            return
        }
        guard let decoded = try? decoder.decode(UsageLimitEventEnvelope.self, from: data),
              decoded.payload.containsRateLimits,
              !decoded.payload.rateLimitsDecodeFailed,
              let rateLimits = decoded.payload.rateLimits,
              rateLimits.hasRecognizedFields else {
            result.usageLimitSnapshots.append(unsupportedSnapshot(data, timestamp: date, line: line))
            result.diagnostics["unsupportedUsageLimitSchemas", default: 0] += 1
            return
        }

        let windows = [
            rateLimits.primary.map { $0.observation(slot: .primary) },
            rateLimits.secondary.map { $0.observation(slot: .secondary) },
            rateLimits.individualLimit.map { $0.observation(slot: .individualLimit) }
        ].compactMap { $0 }
        let hasDecodeIssues = rateLimits.hasDecodeIssues
        let state = snapshotState(windows, hasDecodeIssues: hasDecodeIssues)
        result.usageLimitSnapshots.append(UsageLimitSnapshotObservation(
            eventIdentity: hasDecodeIssues
                ? dataIdentity(data) : eventIdentity(timestamp: date, rateLimits: rateLimits, windows: windows),
            timestamp: date, sourceLine: line,
            sourceContextSessionID: context.sessionID, sourceSchema: "codex.event_msg.token_count.rate_limits",
            state: state, limitID: rateLimits.limitID, limitName: rateLimits.limitName,
            planType: rateLimits.planType, windows: windows
        ))
    }

    func unsupportedSnapshot(_ data: Data, timestamp: Date, line: Int) -> UsageLimitSnapshotObservation {
        UsageLimitSnapshotObservation(
            eventIdentity: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            timestamp: timestamp, sourceLine: line, sourceContextSessionID: context.sessionID,
            sourceSchema: nil, state: .unsupportedSchema, limitID: nil, limitName: nil, planType: nil, windows: []
        )
    }

    mutating func snapshotState(
        _ windows: [UsageLimitWindowObservation], hasDecodeIssues: Bool
    ) -> UsageLimitSnapshotState {
        guard !windows.isEmpty else {
            if hasDecodeIssues {
                result.diagnostics["unsupportedUsageLimitSchemas", default: 0] += 1
                return .unsupportedSchema
            }
            result.diagnostics["usageLimitSnapshotsWithoutWindows", default: 0] += 1
            return .noWindowData
        }
        guard !hasDecodeIssues, !windows.contains(where: { !$0.isComplete }) else {
            result.diagnostics["partialUsageLimitSnapshots", default: 0] += 1
            return .partial
        }
        return .observed
    }

    func eventIdentity(
        timestamp: Date, rateLimits: RateLimitsPayload, windows: [UsageLimitWindowObservation]
    ) -> String {
        let windowIdentity = windows.sorted { $0.slot.rawValue < $1.slot.rawValue }.map { window in
            [window.slot.rawValue, window.windowMinutes.map { String($0) } ?? "unknown-duration",
             window.usedPercent.map { String($0) } ?? "unknown-used",
             window.resetsAt.map { String($0.timeIntervalSince1970) } ?? "unknown-reset"].joined(separator: ":")
        }.joined(separator: ",")
        let material = [
            "adapter-v1", String(timestamp.timeIntervalSince1970), rateLimits.limitID ?? "unknown-limit-id",
            rateLimits.limitName ?? "unknown-limit-name", rateLimits.planType ?? "unknown-plan", windowIdentity
        ].joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func dataIdentity(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
// swiftlint:enable cyclomatic_complexity function_parameter_count file_length
