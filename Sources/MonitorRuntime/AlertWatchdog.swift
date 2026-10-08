import Foundation
import MonitorCore
import MonitorPolicies

public struct AlertWatchdogOptions: Sendable {
    /// Session signals are evaluated over this recent window; older sessions are history, not live.
    public var lookback: TimeInterval
    public var signals: AlertSignalConfiguration
    /// Live rules (SM-327) compare running sessions with the user's own earlier history.
    public var live: LiveRuleConfiguration
    /// How far back the personal baseline reaches, and how often it is rebuilt.
    public var baselineHistory: TimeInterval
    public var baselineRefresh: TimeInterval
    public var maximumBaselineSessions: Int

    public init(
        lookback: TimeInterval = 6 * 3_600, signals: AlertSignalConfiguration = .init(),
        live: LiveRuleConfiguration = .init(), baselineHistory: TimeInterval = 14 * 86_400,
        baselineRefresh: TimeInterval = 1_800, maximumBaselineSessions: Int = 100
    ) {
        self.lookback = lookback.isFinite && lookback > 0 ? lookback : 6 * 3_600
        self.signals = signals
        self.live = live
        self.baselineHistory = baselineHistory.isFinite && baselineHistory > 0 ? baselineHistory : 14 * 86_400
        self.baselineRefresh = baselineRefresh.isFinite && baselineRefresh >= 0 ? baselineRefresh : 1_800
        self.maximumBaselineSessions = max(1, maximumBaselineSessions)
    }
}

/// A built baseline and the sessions it was built from.
private struct CachedBaseline {
    let builtAt: Date
    let baseline: LiveBaseline
    let contributors: Set<String>
}

/// Connects analytics to the alert pipeline: evaluates after each committed import and reports watch
/// health. Detection rules live in MonitorPolicies; this type only feeds them data.
public actor AlertWatchdog {
    private let monitor: SessionMonitor
    private let center: AlertCenter
    public let options: AlertWatchdogOptions
    private var lastPhase: WatchStatus.Phase?
    private var lastError: String?
    private var completedImports = 0
    /// Imports of the current watch already followed by an evaluation.
    var evaluatedImports: Int { completedImports }
    private var lastRoot: URL?
    private var cachedBaseline: CachedBaseline?

    public init(monitor: SessionMonitor, center: AlertCenter, options: AlertWatchdogOptions = .init()) {
        self.monitor = monitor
        self.center = center
        self.options = options
    }

    /// One evaluation of every existing signal. Session alerts outside the lookback window resolve,
    /// so the active set describes recent work only.
    @discardableResult
    public func evaluate(now: Date = Date()) async throws -> [AlertEvent] {
        let query = try UsageQuery(since: now.addingTimeInterval(-options.lookback))
        let snapshot = try await monitor.snapshot(query: query)
        let sessions = snapshot.report.sessions
        let report = try await monitor.doctor(query: query)
        // Latest observation per window regardless of age: a stale window keeps its alert uncertain.
        let quota = try await monitor.quotaPresentation(query: UsageQuery(), generatedAt: now)
        let active = try await monitor.alerts(status: .active)

        var batch = AlertSignals.diagnostics(report, evaluatedSessions: sessions.map(\.id))
        batch.merge(AlertSignals.quotaShifts(report.quotaAssessments, now: now, configuration: options.signals))
        batch.merge(AlertSignals.quotaRemaining(
            quota, activeKeys: Set(active.map(\.id)), configuration: options.signals
        ))
        batch.merge(AlertSignals.cacheThreshold(sessions, configuration: options.signals))
        batch.merge(try await liveSignals(sessions: sessions, query: query, now: now))
        let projectionQuery = try UsageQuery(
            since: now.addingTimeInterval(-(options.live.projectionWindow + options.live.projectionFreshness))
        )
        let projectionPrefix = "quota|projected_exhaustion|"
        batch.merge(LiveRules.quotaProjection(
            try await monitor.usageLimitSnapshots(query: projectionQuery, generatedAt: now), now: now,
            activeSeriesIDs: Set(active.map(\.id).filter { $0.hasPrefix(projectionPrefix) }
                .map { String($0.dropFirst(projectionPrefix.count)) }),
            configuration: options.live
        ))
        let evaluated = Set(sessions.map(\.id))
        for record in active {
            switch record.candidate.source {
            case .anomaly, .cacheThreshold:
                batch.scopes.insert(record.candidate.scope)
            case .liveRule:
                // Live rules decide per session (unknown keeps the alert); only a session that left the
                // lookback window is history and resolves here.
                if evaluated.isDisjoint(with: record.candidate.sessionIDs) {
                    batch.scopes.insert(record.candidate.scope)
                }
            case .quota, .importDiagnostics, .watch:
                break
            }
        }
        return try await center.submit(batch.evaluation(at: now))
    }

    private func liveSignals(
        sessions: [SessionSummary], query: UsageQuery, now: Date
    ) async throws -> AlertSignalBatch {
        var timelines: [RequestTimeline] = []
        for session in sessions { timelines.append(try await monitor.timeline(sessionID: session.id, query: query)) }
        let baseline = try await liveBaseline(excluding: Set(sessions.map(\.id)), now: now)
        return LiveRules.sessionSignals(timelines: timelines, baseline: baseline, now: now, configuration: options.live)
    }

    /// Personal baseline from the busiest earlier sessions, rebuilt at most every `baselineRefresh`.
    private func liveBaseline(excluding live: Set<String>, now: Date) async throws -> LiveBaseline {
        // A session that became live after the baseline was built must not remain part of its own baseline.
        if let cached = cachedBaseline, now.timeIntervalSince(cached.builtAt) >= 0,
           now.timeIntervalSince(cached.builtAt) < options.baselineRefresh,
           live.isDisjoint(with: cached.contributors) {
            return cached.baseline
        }
        let history = try UsageQuery(since: now.addingTimeInterval(-options.baselineHistory), until: now)
        let listed = try await monitor.listSessions(query: history, sort: .requests).sessions
            .filter { !live.contains($0.id) }.prefix(options.maximumBaselineSessions)
        var timelines: [RequestTimeline] = []
        for session in listed { timelines.append(try await monitor.timeline(sessionID: session.id, query: history)) }
        let baseline = LiveBaselineBuilder.build(
            timelines, bucket: options.live.burnWindow, configuration: options.live
        )
        cachedBaseline = CachedBaseline(builtAt: now, baseline: baseline, contributors: Set(listed.map(\.id)))
        return baseline
    }

    /// Reports watch health as its own scope: recovering or failing raises, watching resolves.
    @discardableResult
    public func report(_ status: WatchStatus, root: URL, now: Date = Date()) async throws -> [AlertEvent] {
        try await center.submit(Self.watchSignals(status, root: root).evaluation(at: now))
    }

    /// Feed every status from the single consumer of `SessionWatch.updates` (the stream allows only
    /// one). Phase changes and errors update watch health; each new committed import re-evaluates.
    @discardableResult
    public func handle(_ status: WatchStatus, root: URL, now: Date = Date()) async throws -> [AlertEvent] {
        var events: [AlertEvent] = []
        // A new watch (another root, or a restart of the same root) counts imports from zero again.
        if root != lastRoot || status.completedImports < completedImports {
            lastRoot = root
            lastPhase = nil
            lastError = nil
            completedImports = 0
        }
        if status.phase != lastPhase || status.error != lastError {
            lastPhase = status.phase
            lastError = status.error
            events += try await report(status, root: root, now: now)
        }
        if status.completedImports > completedImports {
            completedImports = status.completedImports
            events += try await evaluate(now: now)
        }
        return events
    }

    static func watchSignals(_ status: WatchStatus, root: URL) -> AlertSignalBatch {
        let scope = AlertScope("watch:\(root.standardizedFileURL.path)")
        var batch = AlertSignalBatch(scopes: [scope])
        guard status.phase == .recovering || status.error != nil else { return batch }
        batch.candidates.append(AlertCandidate(
            key: "watch|unhealthy|\(root.standardizedFileURL.path)", scope: scope, source: .watch,
            kind: "unhealthy", severity: .warning, title: "Session watch needs attention",
            message: "Watch for \(root.lastPathComponent) is \(status.phase.rawValue)"
                + (status.error.map { ": \($0)" } ?? "."),
            evidence: DiagnosticEvidence(observed: [DiagnosticEvidenceItem(
                source: "watch_status",
                detail: "Phase \(status.phase.rawValue) after \(status.completedImports) imports."
            )])
        ))
        return batch
    }
}
