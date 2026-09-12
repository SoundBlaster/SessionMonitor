import Foundation

/// Absolute half-open interval. Timezone is presentation metadata, never a second date conversion.
public struct UsageQuery: Codable, Equatable, Sendable {
    public let since: Date?
    public let until: Date?
    public let timeZoneIdentifier: String

    public init(since: Date? = nil, until: Date? = nil, timeZoneIdentifier: String = "UTC") throws {
        guard since?.timeIntervalSince1970.isFinite != false,
              until?.timeIntervalSince1970.isFinite != false else { throw QueryError.invalidPeriod }
        if let since, let until, since >= until { throw QueryError.invalidPeriod }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else { throw QueryError.invalidTimeZone }
        self.since = since
        self.until = until
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(since: values.decodeIfPresent(Date.self, forKey: .since),
                      until: values.decodeIfPresent(Date.self, forKey: .until),
                      timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier))
    }
}

public enum QueryError: Error, LocalizedError {
    case invalidPeriod
    case invalidTimeZone

    public var errorDescription: String? {
        switch self {
        case .invalidPeriod: "The finite start date must precede the finite end date."
        case .invalidTimeZone: "Unknown timezone identifier."
        }
    }
}

/// Identifies a committed index generation, not completeness or freshness of the source archive.
public struct QueryWatermark: Codable, Equatable, Sendable {
    public let databaseID: String
    public let revision: Int64
    public let committedAt: Date?

    public init(databaseID: String, revision: Int64, committedAt: Date?) {
        self.databaseID = databaseID
        self.revision = revision
        self.committedAt = committedAt
    }
}

public struct QueryCoverage: Codable, Equatable, Sendable {
    public enum Cache: String, Codable, Sendable { case empty, partial, complete }
    public let accounting: String
    public let diagnosticsScope: String
    public let cache: Cache
    public let knownCacheRequests: Int64
    public let unknownCacheRequests: Int64

    public init(totals: UsageTotals) {
        accounting = "canonical-only"
        diagnosticsScope = "all-imported-sources"
        knownCacheRequests = totals.requests - totals.unknownCacheRequests
        unknownCacheRequests = totals.unknownCacheRequests
        cache = totals.requests == 0 ? .empty : (totals.unknownCacheRequests == 0 ? .complete : .partial)
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let query: UsageQuery
    public let watermark: QueryWatermark
    public let coverage: QueryCoverage
    public let report: UsageReport

    public init(query: UsageQuery, watermark: QueryWatermark, report: UsageReport) {
        schemaVersion = 1
        self.query = query
        self.watermark = watermark
        coverage = QueryCoverage(totals: report.totals)
        self.report = report
    }
}
