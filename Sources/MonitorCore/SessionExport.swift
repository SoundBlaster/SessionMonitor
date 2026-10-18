import Foundation

public enum AnonymizedSessionExportError: Error, LocalizedError {
    case multipleAccountScopes
    case unsupportedRuntime

    public var errorDescription: String? {
        switch self {
        case .multipleAccountScopes:
            "This session ID exists in multiple account scopes. Select one profile before exporting."
        case .unsupportedRuntime:
            "The active data runtime does not support anonymized session exports."
        }
    }
}

/// Versioned, identity-free session data intended for sharing as a diagnostic fixture.
public struct AnonymizedSessionExport: Codable, Equatable, Sendable {
    public static let formatVersion = "session-export.v1"

    public let format: String
    public let clientVersion: String?
    public let requests: [AnonymizedSessionExportRequest]

    public init(clientVersion: String?, requests: [AnonymizedSessionExportRequest]) {
        format = Self.formatVersion
        self.clientVersion = clientVersion
        self.requests = requests
    }

    private enum CodingKeys: String, CodingKey {
        case format
        case clientVersion = "client_version"
        case requests
    }

    /// Produces stable JSON so exported examples can be checked into regression tests.
    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data([10])
    }
}

public struct AnonymizedSessionExportRequest: Codable, Equatable, Sendable {
    public let ordinal: Int
    public let offsetSeconds: Double
    public let model: String?
    public let inputTokens: Int64?
    public let cachedInputTokens: Int64?
    public let uncachedInputTokens: Int64?
    public let outputTokens: Int64?
    public let reasoningOutputTokens: Int64?
    public let cacheWriteInputTokens: Int64?
    public let contextWindowTokens: Int64?
    public let eventsUntilNextRequest: [AnonymizedSessionExportEventCount]

    public init(
        ordinal: Int, offsetSeconds: Double, model: String?, inputTokens: Int64?, cachedInputTokens: Int64?,
        uncachedInputTokens: Int64?, outputTokens: Int64?, reasoningOutputTokens: Int64?, cacheWriteInputTokens: Int64?,
        contextWindowTokens: Int64?, eventsUntilNextRequest: [AnonymizedSessionExportEventCount]
    ) {
        self.ordinal = ordinal
        self.offsetSeconds = offsetSeconds
        self.model = model
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.uncachedInputTokens = uncachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.contextWindowTokens = contextWindowTokens
        self.eventsUntilNextRequest = eventsUntilNextRequest
    }

    private enum CodingKeys: String, CodingKey {
        case ordinal
        case offsetSeconds = "offset_seconds"
        case model
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case uncachedInputTokens = "uncached_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case cacheWriteInputTokens = "cache_write_input_tokens"
        case contextWindowTokens = "context_window_tokens"
        case eventsUntilNextRequest = "events_until_next_request"
    }
}

public struct AnonymizedSessionExportEventCount: Codable, Equatable, Sendable {
    public let type: String
    public let count: Int
    public let toolClass: String?

    public init(type: String, count: Int, toolClass: String?) {
        self.type = type
        self.count = count
        self.toolClass = toolClass
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case count
        case toolClass = "tool_class"
    }
}

/// Projects an internal timeline into a strict allowlist of fields safe for external sharing.
public enum AnonymizedSessionExportBuilder {
    public static func build(
        clientVersion: String?, timeline: RequestTimeline
    ) -> AnonymizedSessionExport? {
        let points = timeline.points
        let requestIndices = points.indices.filter { points[$0].kind == .usageRequest }
        guard let firstIndex = requestIndices.first else { return nil }
        let requests = requestIndices.enumerated().map { ordinal, pointIndex in
            let nextPointIndex = ordinal + 1 < requestIndices.count ? requestIndices[ordinal + 1] : points.endIndex
            let eventCounts = ordinal + 1 < requestIndices.count
                ? summarize(points[(pointIndex + 1)..<nextPointIndex])
                : []
            let point = points[pointIndex]
            return AnonymizedSessionExportRequest(
                ordinal: ordinal + 1,
                offsetSeconds: max(0, point.timestamp.timeIntervalSince(points[firstIndex].timestamp)),
                model: point.model,
                inputTokens: point.inputTokens,
                cachedInputTokens: point.cachedInputTokens,
                uncachedInputTokens: point.uncachedInputTokens,
                outputTokens: point.outputTokens,
                reasoningOutputTokens: point.reasoningOutputTokens,
                cacheWriteInputTokens: point.cacheWriteInputTokens,
                contextWindowTokens: point.contextWindowTokens,
                eventsUntilNextRequest: eventCounts
            )
        }
        return AnonymizedSessionExport(clientVersion: clientVersion, requests: requests)
    }

    private static func summarize(
        _ points: ArraySlice<RequestTimelinePoint>
    ) -> [AnonymizedSessionExportEventCount] {
        let eventPoints = points.filter { $0.kind != .usageRequest }
        let counts = Dictionary(grouping: eventPoints) {
            ExportEventKey(type: $0.kind.rawValue, toolClass: $0.activityClass?.rawValue)
        }
        return counts.map { key, values in
            AnonymizedSessionExportEventCount(type: key.type, count: values.count, toolClass: key.toolClass)
        }.sorted {
            if $0.type != $1.type { return $0.type < $1.type }
            return ($0.toolClass ?? "") < ($1.toolClass ?? "")
        }
    }

    private struct ExportEventKey: Hashable {
        let type: String
        let toolClass: String?
    }
}
