import Foundation
import MonitorCore
import MonitorPolicies
import MonitorStore

/// A delivery channel. Every sink receives every transition; interrupting channels (system
/// notifications) should act only on events with `notify == true`.
public protocol AlertSink: Sendable {
    func deliver(_ events: [AlertEvent]) async
}

/// Encodes each event as one compact JSON line for CLI pipes and agent tools.
public struct JSONLinesAlertSink: AlertSink {
    private let write: @Sendable (Data) async -> Void

    public init(write: @escaping @Sendable (Data) async -> Void) {
        self.write = write
    }

    public func deliver(_ events: [AlertEvent]) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        for event in events {
            guard var line = try? encoder.encode(event) else { continue }
            line.append(10)
            await write(line)
        }
    }
}

/// Signal-agnostic alert pipeline: persists transitions with an outbox atomically, then fans them out.
/// Signal adapters (anomalies, quota, diagnostics, watch) submit `AlertEvaluation`s separately.
public actor AlertCenter {
    private let monitor: SessionMonitor
    private var sinks: [any AlertSink]
    public private(set) var configuration: AlertPolicyConfiguration

    public init(
        monitor: SessionMonitor, configuration: AlertPolicyConfiguration = .init(), sinks: [any AlertSink] = []
    ) {
        self.monitor = monitor
        self.configuration = configuration
        self.sinks = sinks
    }

    public func add(_ sink: any AlertSink) {
        sinks.append(sink)
    }

    public func update(configuration: AlertPolicyConfiguration) {
        self.configuration = configuration
    }

    /// Commits the evaluation, then drains the outbox. Returns the transitions this evaluation committed.
    @discardableResult
    public func submit(_ evaluation: AlertEvaluation) async throws -> [AlertEvent] {
        let events = try await monitor.applyAlertEvaluation(evaluation, configuration: configuration)
        try await deliverPending()
        return events
    }

    /// At-least-once delivery: entries are acknowledged only after every sink returned. Without sinks
    /// the outbox is kept, so events committed earlier (or before a crash) reach sinks added later.
    @discardableResult
    public func deliverPending() async throws -> [AlertEvent] {
        guard !sinks.isEmpty else { return [] }
        let pending = try await monitor.pendingAlertEvents()
        guard !pending.isEmpty else { return [] }
        let events = pending.map(\.event)
        for sink in sinks {
            await sink.deliver(events)
        }
        try await monitor.acknowledgeAlertEvents(ids: pending.map(\.id))
        return events
    }
}

extension SessionMonitor {
    public func applyAlertEvaluation(
        _ evaluation: AlertEvaluation, configuration: AlertPolicyConfiguration = .init()
    ) throws -> [AlertEvent] {
        try store.applyAlertEvaluation(evaluation, tracker: AlertTracker(configuration: configuration))
    }

    public func alerts(status: AlertStatus? = nil) throws -> [AlertRecord] {
        try store.alertRecords(status: status)
    }

    public func pendingAlertEvents() throws -> [PendingAlertEvent] {
        try store.pendingAlertEvents()
    }

    public func acknowledgeAlertEvents(ids: [Int64]) throws {
        try store.acknowledgeAlertEvents(ids: ids)
    }
}
