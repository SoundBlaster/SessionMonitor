import Foundation

/// Compact, privacy-safe status for an agent working in a session: canonical usage, recent activity,
/// relevant active alerts and quota windows. It contains no prompt text, tool output or file names.
public struct AgentStatusReport: Codable, Equatable, Sendable {
    public struct Index: Codable, Equatable, Sendable {
        public let revision: Int64
        public let committedAt: Date?
        /// Seconds since the index was last committed; it says nothing about unimported source files.
        public let ageSeconds: Double?

        public init(revision: Int64, committedAt: Date?, ageSeconds: Double?) {
            self.revision = revision
            self.committedAt = committedAt
            self.ageSeconds = ageSeconds
        }
    }

    public struct Session: Codable, Equatable, Sendable {
        public let id: String
        public let model: String
        public let requests: Int64
        public let inputTokens: Int64
        public let cachedInputTokens: Int64
        public let outputTokens: Int64
        public let cacheHitRatio: Double?
        public let cacheCoverage: QueryCoverage.Cache
        public let firstRequestAt: Date?
        public let lastRequestAt: Date?
        public let idleSeconds: Double?

        public init(
            id: String, model: String, totals: UsageTotals, firstRequestAt: Date?, lastRequestAt: Date?,
            idleSeconds: Double?
        ) {
            self.id = id
            self.model = model
            requests = totals.requests
            inputTokens = totals.inputTokens
            cachedInputTokens = totals.cachedInputTokens
            outputTokens = totals.outputTokens
            cacheHitRatio = totals.cacheHitRatio
            cacheCoverage = QueryCoverage(totals: totals).cache
            self.firstRequestAt = firstRequestAt
            self.lastRequestAt = lastRequestAt
            self.idleSeconds = idleSeconds
        }
    }

    /// Activity inside the recent window. Input is `nil` when any recent request lacks it.
    public struct Recent: Codable, Equatable, Sendable {
        public let windowSeconds: Double
        public let requests: Int
        public let inputTokens: Int64?
        public let waits: Int
        public let compactions: Int

        public init(windowSeconds: Double, requests: Int, inputTokens: Int64?, waits: Int, compactions: Int) {
            self.windowSeconds = windowSeconds
            self.requests = requests
            self.inputTokens = inputTokens
            self.waits = waits
            self.compactions = compactions
        }
    }

    public struct Alert: Codable, Equatable, Sendable {
        public let key: String
        public let source: AlertSource
        public let kind: String
        public let severity: DiagnosticSeverity
        public let title: String
        public let message: String
        public let coverage: AnomalyCoverage
        public let raisedAt: Date
        public let lastSeenAt: Date

        /// Watch alerts carry the watched folder in their key and message; agents get a path-free form.
        public init(_ record: AlertRecord) {
            let isWatch = record.candidate.source == .watch
            key = isWatch ? "watch|\(record.candidate.kind)" : record.candidate.key
            source = record.candidate.source
            kind = record.candidate.kind
            severity = record.candidate.severity
            title = record.candidate.title
            message = isWatch
                ? "The session watch is not healthy; open SessionMonitor for details."
                : record.candidate.message
            coverage = record.candidate.coverage
            raisedAt = record.raisedAt
            lastSeenAt = record.lastSeenAt
        }
    }

    public struct Quota: Codable, Equatable, Sendable {
        public let window: UsageLimitWindowKind
        public let accountProfile: String?
        public let remainingPercent: Double?
        public let resetsAt: Date?
        public let freshness: QuotaFreshnessState

        public init(_ window: QuotaWindowPresentation) {
            self.window = window.windowKind
            accountProfile = window.accountProfileLabel ?? window.accountProfileID
            remainingPercent = window.remainingPercent
            resetsAt = window.resetsAt
            freshness = window.freshness.state
        }
    }

    public let schemaVersion: Int
    public let generatedAt: Date
    /// Session usage totals and activity cover only this window before `generatedAt`.
    public let lookbackSeconds: Double
    public let index: Index
    /// `nil` when no session with canonical usage was found for the request.
    public let session: Session?
    public let recent: Recent?
    public let alerts: [Alert]
    public let quota: [Quota]

    public init(
        generatedAt: Date, lookbackSeconds: Double, index: Index, session: Session?, recent: Recent?,
        alerts: [Alert], quota: [Quota]
    ) {
        schemaVersion = 1
        self.generatedAt = generatedAt
        self.lookbackSeconds = lookbackSeconds
        self.index = index
        self.session = session
        self.recent = recent
        self.alerts = alerts
        self.quota = quota
    }

    /// Highest severity among the reported active alerts.
    public var highestSeverity: DiagnosticSeverity? {
        alerts.map(\.severity).max { lhs, rhs in lhs.rank < rhs.rank }
    }
}

extension DiagnosticSeverity {
    /// Ordering for thresholds: info < warning < error.
    public var rank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .error: 2
        }
    }
}
