import Foundation
import MonitorCore
import MonitorPolicies

public struct AlertWatchdogOptions: Sendable {
    /// Session signals are evaluated over this recent window; older sessions are history, not live.
    public var lookback: TimeInterval
    public var signals: AlertSignalConfiguration

    public init(lookback: TimeInterval = 6 * 3_600, signals: AlertSignalConfiguration = .init()) {
        self.lookback = lookback.isFinite && lookback > 0 ? lookback : 6 * 3_600
        self.signals = signals
    }
}

/// Connects existing analytics to the alert pipeline: evaluates after each committed import and
/// reports watch health. It adds no new detection rules.
public actor AlertWatchdog {
    private let monitor: SessionMonitor
    private let center: AlertCenter
    public let options: AlertWatchdogOptions
    private var lastPhase: WatchStatus.Phase?
    private var lastError: String?
    private var completedImports = 0

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
        let quota = try await monitor.quotaPresentation(query: query, generatedAt: now)

        var batch = AlertSignals.diagnostics(report, evaluatedSessions: sessions.map(\.id))
        batch.merge(AlertSignals.quotaShifts(report.quotaAssessments, now: now, configuration: options.signals))
        batch.merge(AlertSignals.quotaRemaining(quota, configuration: options.signals))
        batch.merge(AlertSignals.cacheThreshold(sessions, configuration: options.signals))
        let sessionSources: Set<AlertSource> = [.anomaly, .cacheThreshold]
        for record in try await monitor.alerts(status: .active)
        where sessionSources.contains(record.candidate.source) {
            batch.scopes.insert(record.candidate.scope)
        }
        return try await center.submit(batch.evaluation(at: now))
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
