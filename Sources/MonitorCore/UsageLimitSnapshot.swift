import Foundation

public enum UsageLimitScope: String, Codable, CaseIterable, Sendable {
    case account
    case modelPool
    case source
    case unknown
}

public enum UsageLimitWindowSlot: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
    case individualLimit
}

public enum UsageLimitSnapshotState: String, Codable, CaseIterable, Sendable {
    case observed
    case partial
    case noWindowData
    case unsupportedSchema
}

public struct UsageLimitWindowObservation: Codable, Equatable, Sendable {
    public let slot: UsageLimitWindowSlot
    public let windowMinutes: Int64?
    public let usedPercent: Double?
    public let resetsAt: Date?

    public var remainingPercentDerived: Double? {
        guard let usedPercent, usedPercent >= 0 else { return nil }
        return max(0, 100 - usedPercent)
    }

    public var isComplete: Bool {
        windowMinutes.map { $0 > 0 } == true && usedPercent.map { $0 >= 0 } == true && resetsAt != nil
    }

    public var windowKind: UsageLimitWindowKind {
        switch windowMinutes {
        case 300: .fiveHour
        case 10_080: .weekly
        case .some: .other
        case .none: .unknown
        }
    }

    public init(slot: UsageLimitWindowSlot, windowMinutes: Int64?, usedPercent: Double?, resetsAt: Date?) {
        self.slot = slot
        self.windowMinutes = windowMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public enum UsageLimitWindowKind: String, Codable, CaseIterable, Sendable {
    case fiveHour
    case weekly
    case other
    case unknown
}

/// One source event. Its rollout session context is provenance, not proof that the session owns the quota.
public struct UsageLimitSnapshotObservation: Codable, Equatable, Identifiable, Sendable {
    public let eventIdentity: String
    public let timestamp: Date
    public let sourceLine: Int
    public let sourceContextSessionID: String?
    public let adapterVersion: Int
    public let sourceSchema: String?
    public let state: UsageLimitSnapshotState
    public let scope: UsageLimitScope
    public let scopeIdentifier: String?
    public let limitID: String?
    public let limitName: String?
    public let planType: String?
    public let windows: [UsageLimitWindowObservation]
    public let duplicateSourceRecords: Int

    public var id: String { eventIdentity }

    public init(
        eventIdentity: String, timestamp: Date, sourceLine: Int, sourceContextSessionID: String?,
        adapterVersion: Int = 1, sourceSchema: String?, state: UsageLimitSnapshotState,
        scope: UsageLimitScope = .unknown, scopeIdentifier: String? = nil,
        limitID: String?, limitName: String?, planType: String?,
        windows: [UsageLimitWindowObservation], duplicateSourceRecords: Int = 0
    ) {
        self.eventIdentity = eventIdentity
        self.timestamp = timestamp
        self.sourceLine = sourceLine
        self.sourceContextSessionID = sourceContextSessionID
        self.adapterVersion = adapterVersion
        self.sourceSchema = sourceSchema
        self.state = state
        self.scope = scope
        self.scopeIdentifier = scopeIdentifier
        self.limitID = limitID
        self.limitName = limitName
        self.planType = planType
        self.windows = windows
        self.duplicateSourceRecords = duplicateSourceRecords
    }
}

public enum UsageLimitTelemetryCoverageState: String, Codable, Sendable {
    case observed
    case partial
    case unknown
}

public enum UsageLimitTelemetryUnknownReason: String, Codable, Sendable {
    case noSnapshotInPeriod
    case unsupportedSchema
    case noWindowData
}

public struct UsageLimitTelemetryCoverage: Codable, Equatable, Sendable {
    public let state: UsageLimitTelemetryCoverageState
    public let unknownReason: UsageLimitTelemetryUnknownReason?
    public let supportedWindowObservations: Int
    public let partialSnapshots: Int
    public let unsupportedSnapshots: Int
    public let snapshotsWithoutWindowData: Int
    public let latestObservedAt: Date?

    public init(snapshots: [UsageLimitSnapshotObservation]) {
        supportedWindowObservations = snapshots.reduce(0) { $0 + $1.windows.count }
        partialSnapshots = snapshots.filter { $0.state == .partial }.count
        unsupportedSnapshots = snapshots.filter { $0.state == .unsupportedSchema }.count
        snapshotsWithoutWindowData = snapshots.filter { $0.state == .noWindowData }.count
        latestObservedAt = snapshots.map(\.timestamp).max()
        if supportedWindowObservations == 0 {
            state = .unknown
            if unsupportedSnapshots > 0 {
                unknownReason = .unsupportedSchema
            } else if snapshotsWithoutWindowData > 0 {
                unknownReason = .noWindowData
            } else {
                unknownReason = .noSnapshotInPeriod
            }
        } else if partialSnapshots > 0 || unsupportedSnapshots > 0 || snapshotsWithoutWindowData > 0 {
            state = .partial
            unknownReason = nil
        } else {
            state = .observed
            unknownReason = nil
        }
    }
}

public struct UsageLimitSnapshotReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let query: UsageQuery
    public let generatedAt: Date
    public let snapshots: [UsageLimitSnapshotObservation]
    public let coverage: UsageLimitTelemetryCoverage

    public init(query: UsageQuery, generatedAt: Date, snapshots: [UsageLimitSnapshotObservation]) {
        schemaVersion = 1
        self.query = query
        self.generatedAt = generatedAt
        self.snapshots = snapshots
        coverage = UsageLimitTelemetryCoverage(snapshots: snapshots)
    }
}
