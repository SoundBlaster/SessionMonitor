import Foundation

/// Aggregate-only data shared with WidgetKit. No session, model, source, or database identity is exposed.
public struct WidgetSharedSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let widgetKind = "ru.egormerkushev.session-monitor.widget.snapshot"
    public static let appGroupIdentifier = "group.ru.egormerkushev.session-monitor"

    public let schemaVersion: Int
    public let generatedAt: Date
    public let timeZoneIdentifier: String
    public let revision: Int64
    public let usage: [WidgetUsagePeriodSnapshot]
    public let cache: WidgetCachePeriodSnapshot

    public init(generatedAt: Date, timeZoneIdentifier: String, revision: Int64,
                usage: [WidgetUsagePeriodSnapshot], cache: WidgetCachePeriodSnapshot) throws {
        guard generatedAt.timeIntervalSince1970.isFinite,
              TimeZone(identifier: timeZoneIdentifier) != nil,
              revision >= 0,
              usage.count == WidgetUsagePeriod.allCases.count,
              Set(usage.map(\.period)).count == usage.count,
              usage.allSatisfy({ $0.isValid }), cache.isValid else {
            throw WidgetSharedSnapshotError.invalidSnapshot
        }
        schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.revision = revision
        self.usage = usage.sorted { $0.period.rawValue < $1.period.rawValue }
        self.cache = cache
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.currentSchemaVersion else { throw WidgetSharedSnapshotError.unsupportedVersion(version) }
        try self.init(
            generatedAt: values.decode(Date.self, forKey: .generatedAt),
            timeZoneIdentifier: values.decode(String.self, forKey: .timeZoneIdentifier),
            revision: values.decode(Int64.self, forKey: .revision),
            usage: values.decode([WidgetUsagePeriodSnapshot].self, forKey: .usage),
            cache: values.decode(WidgetCachePeriodSnapshot.self, forKey: .cache)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, generatedAt, timeZoneIdentifier, revision, usage, cache
    }
}

public enum WidgetUsagePeriod: String, Codable, CaseIterable, Sendable {
    case today
    case last7Days
}

public struct WidgetUsagePeriodSnapshot: Codable, Equatable, Sendable {
    public let period: WidgetUsagePeriod
    public let startsAt: Date
    public let endsAt: Date
    public let requests: Int64
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let outputTokens: Int64
    public let knownCacheRequests: Int64
    public let unknownCacheRequests: Int64
    public let cacheCoverage: WidgetCacheCoverage

    public init(period: WidgetUsagePeriod, startsAt: Date, endsAt: Date, totals: UsageTotals) throws {
        guard startsAt < endsAt, totals.requests >= 0, totals.inputTokens >= 0,
              totals.cachedInputTokens >= 0, totals.outputTokens >= 0,
              totals.unknownCacheRequests >= 0, totals.unknownCacheRequests <= totals.requests else {
            throw WidgetSharedSnapshotError.invalidSnapshot
        }
        self.period = period
        self.startsAt = startsAt
        self.endsAt = endsAt
        requests = totals.requests
        inputTokens = totals.inputTokens
        cachedInputTokens = totals.cachedInputTokens
        outputTokens = totals.outputTokens
        knownCacheRequests = totals.requests - totals.unknownCacheRequests
        unknownCacheRequests = totals.unknownCacheRequests
        cacheCoverage = totals.requests == 0 ? .empty : (totals.unknownCacheRequests == 0 ? .complete : .partial)
    }

    fileprivate var isValid: Bool {
        startsAt.timeIntervalSince1970.isFinite && endsAt.timeIntervalSince1970.isFinite && startsAt < endsAt
            && requests >= 0 && inputTokens >= 0 && cachedInputTokens >= 0 && outputTokens >= 0
            && knownCacheRequests >= 0 && unknownCacheRequests >= 0 && unknownCacheRequests <= requests
            && knownCacheRequests == requests - unknownCacheRequests
            && cacheCoverage == (requests == 0 ? .empty : (unknownCacheRequests == 0 ? .complete : .partial))
    }
}

public enum WidgetCacheCoverage: String, Codable, Sendable {
    case empty
    case partial
    case complete
    case notApplicable
}

public struct WidgetCachePeriodSnapshot: Codable, Equatable, Sendable {
    public let startsAt: Date
    public let endsAt: Date
    public let hitRate: Double?
    public let comparisonDeltaPercentagePoints: Double?
    public let availability: Availability
    public let sessionCount: Int
    public let unknownObservationCount: Int
    public let buckets: [WidgetCacheBucket]

    public enum Availability: String, Codable, Sendable {
        case available
        case partial
        case notApplicable
        case noData
    }

    public init(startsAt: Date, endsAt: Date, hitRate: Double?, comparisonDeltaPercentagePoints: Double?,
                availability: Availability, sessionCount: Int, unknownObservationCount: Int = 0,
                buckets: [WidgetCacheBucket]) throws {
        guard startsAt < endsAt, sessionCount >= 0, unknownObservationCount >= 0,
              hitRate.map({ $0.isFinite && (0...100).contains($0) }) ?? true,
              comparisonDeltaPercentagePoints.map(\.isFinite) ?? true else {
            throw WidgetSharedSnapshotError.invalidSnapshot
        }
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.hitRate = hitRate
        self.comparisonDeltaPercentagePoints = comparisonDeltaPercentagePoints
        self.availability = availability
        self.sessionCount = sessionCount
        self.unknownObservationCount = unknownObservationCount
        self.buckets = buckets
    }

    fileprivate var isValid: Bool {
        startsAt.timeIntervalSince1970.isFinite && endsAt.timeIntervalSince1970.isFinite && startsAt < endsAt
            && sessionCount >= 0
            && (hitRate.map { $0.isFinite && (0...100).contains($0) } ?? true)
            && (comparisonDeltaPercentagePoints?.isFinite ?? true)
            && unknownObservationCount >= 0
            && availabilityMatchesMetrics
            && buckets.allSatisfy(\.isValid)
    }

    private var availabilityMatchesMetrics: Bool {
        switch availability {
        case .available: hitRate != nil && unknownObservationCount == 0
        case .partial: hitRate == nil && unknownObservationCount > 0
        case .notApplicable: hitRate == nil && unknownObservationCount == 0
        case .noData: hitRate == nil && sessionCount == 0 && unknownObservationCount == 0
        }
    }
}

public struct WidgetCacheBucket: Codable, Equatable, Sendable, Identifiable {
    public let startsAt: Date
    public let endsAt: Date
    public let lower: Double
    public let upper: Double
    public let average: Double
    public let sampleCount: Int
    public let outliers: [WidgetCacheOutlier]

    public var id: Date { startsAt }

    public init(startsAt: Date, endsAt: Date, lower: Double, upper: Double, average: Double, sampleCount: Int,
                outliers: [WidgetCacheOutlier] = []) throws {
        guard startsAt < endsAt, (0...100).contains(lower), (0...100).contains(average),
              (0...100).contains(upper), lower <= average, average <= upper, sampleCount >= 0 else {
            throw WidgetSharedSnapshotError.invalidSnapshot
        }
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.lower = lower
        self.upper = upper
        self.average = average
        self.sampleCount = sampleCount
        self.outliers = outliers
    }

    fileprivate var isValid: Bool {
        startsAt.timeIntervalSince1970.isFinite && endsAt.timeIntervalSince1970.isFinite && startsAt < endsAt
            && (0...100).contains(lower) && (0...100).contains(average) && (0...100).contains(upper)
            && lower <= average && average <= upper && sampleCount >= 0
            && outliers.allSatisfy(\.isValid)
    }
}

public struct WidgetCacheOutlier: Codable, Equatable, Sendable {
    public enum Severity: String, Codable, Sendable { case notable, strong }

    public let hitRate: Double
    public let deviation: Double
    public let severity: Severity

    public init(hitRate: Double, deviation: Double, severity: Severity) throws {
        guard hitRate.isFinite, (0...100).contains(hitRate), deviation.isFinite else {
            throw WidgetSharedSnapshotError.invalidSnapshot
        }
        self.hitRate = hitRate
        self.deviation = deviation
        self.severity = severity
    }

    fileprivate var isValid: Bool { hitRate.isFinite && (0...100).contains(hitRate) && deviation.isFinite }
}

public enum WidgetSharedSnapshotError: Error, Equatable {
    case invalidSnapshot
    case unsupportedVersion(Int)
}

/// Atomic file transport. App and extension instantiate it with the same App Group directory.
public struct WidgetSharedSnapshotStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func appGroup(identifier: String = WidgetSharedSnapshot.appGroupIdentifier) -> Self? {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return nil
        }
        return Self(fileURL: directory.appending(path: "widget-snapshot.json"))
    }

    public func write(_ snapshot: WidgetSharedSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func read() throws -> WidgetSharedSnapshot {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(WidgetSharedSnapshot.self, from: data)
    }
}
