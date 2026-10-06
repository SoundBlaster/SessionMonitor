import Foundation
import MonitorCore
import SpecificationCore

/// Delivery thresholds. Transitions are always recorded; these values only decide interruption.
public struct AlertPolicyConfiguration: Equatable, Sendable {
    public let minimumSeverity: DiagnosticSeverity
    public let cooldown: TimeInterval
    public let rateLimitWindow: TimeInterval
    public let maximumNotificationsPerWindow: Int
    public let mutedKinds: Set<String>
    public let notifyUncertainCoverage: Bool
    public let notifyResolutions: Bool

    public init(
        minimumSeverity: DiagnosticSeverity = .warning, cooldown: TimeInterval = 900,
        rateLimitWindow: TimeInterval = 600, maximumNotificationsPerWindow: Int = 5,
        mutedKinds: Set<String> = [], notifyUncertainCoverage: Bool = false, notifyResolutions: Bool = false
    ) {
        self.minimumSeverity = minimumSeverity
        self.cooldown = cooldown.isFinite && cooldown >= 0 ? cooldown : 900
        self.rateLimitWindow = rateLimitWindow.isFinite && rateLimitWindow > 0 ? rateLimitWindow : 600
        self.maximumNotificationsPerWindow = max(1, maximumNotificationsPerWindow)
        self.mutedKinds = mutedKinds
        self.notifyUncertainCoverage = notifyUncertainCoverage
        self.notifyResolutions = notifyResolutions
    }
}

extension DiagnosticSeverity {
    var alertRank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .error: 2
        }
    }
}

/// Context for one notification decision inside a tracker batch.
struct AlertNotificationContext {
    let candidate: AlertCandidate
    let previousNotification: Date?
    let notificationsInWindow: Int
    let now: Date
    let configuration: AlertPolicyConfiguration
}

struct MeetsMinimumSeveritySpec: Specification {
    func isSatisfiedBy(_ candidate: AlertNotificationContext) -> Bool {
        candidate.candidate.severity.alertRank >= candidate.configuration.minimumSeverity.alertRank
    }
}

struct IsNotMutedSpec: Specification {
    func isSatisfiedBy(_ candidate: AlertNotificationContext) -> Bool {
        !candidate.configuration.mutedKinds.contains(candidate.candidate.kind)
    }
}

/// Unknown coverage stays visible in state, but does not interrupt by default.
struct HasCertainCoverageSpec: Specification {
    func isSatisfiedBy(_ candidate: AlertNotificationContext) -> Bool {
        if case .unknown = candidate.candidate.coverage { return candidate.configuration.notifyUncertainCoverage }
        return true
    }
}

struct IsOutsideCooldownSpec: Specification {
    func isSatisfiedBy(_ candidate: AlertNotificationContext) -> Bool {
        guard let previous = candidate.previousNotification else { return true }
        return candidate.now.timeIntervalSince(previous) >= candidate.configuration.cooldown
    }
}

struct IsWithinRateLimitSpec: Specification {
    func isSatisfiedBy(_ candidate: AlertNotificationContext) -> Bool {
        candidate.notificationsInWindow < candidate.configuration.maximumNotificationsPerWindow
    }
}

/// Ordered so the reported suppression names the first rule that blocked delivery.
struct AlertNotificationDecision: DecisionSpec {
    typealias Context = AlertNotificationContext
    typealias Result = AlertSuppression

    func decide(_ context: Context) -> AlertSuppression? {
        if !MeetsMinimumSeveritySpec().isSatisfiedBy(context) { return .belowMinimumSeverity }
        if !IsNotMutedSpec().isSatisfiedBy(context) { return .muted }
        if !HasCertainCoverageSpec().isSatisfiedBy(context) { return .uncertainCoverage }
        if !IsOutsideCooldownSpec().isSatisfiedBy(context) { return .cooldown }
        if !IsWithinRateLimitSpec().isSatisfiedBy(context) { return .rateLimited }
        return nil
    }
}

public struct AlertTrackerResult: Equatable, Sendable {
    /// Records whose stored state changed, including silent `lastSeenAt` refreshes.
    public let changedRecords: [AlertRecord]
    public let events: [AlertEvent]

    public init(changedRecords: [AlertRecord], events: [AlertEvent]) {
        self.changedRecords = changedRecords
        self.events = events
    }
}

/// Pure alert state machine: raise, escalate, update and resolve with dedup, cooldown and rate limit.
/// The rate limit counts distinct alerts notified within the window, using stored `lastNotifiedAt`.
public struct AlertTracker: Sendable {
    public let configuration: AlertPolicyConfiguration

    public init(configuration: AlertPolicyConfiguration = .init()) {
        self.configuration = configuration
    }

    // swiftlint:disable:next function_body_length
    public func apply(_ evaluation: AlertEvaluation, to existing: [AlertRecord]) -> AlertTrackerResult {
        let now = evaluation.observedAt
        let records = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        var notified = existing.filter { record in
            record.lastNotifiedAt.map { now.timeIntervalSince($0) < configuration.rateLimitWindow } == true
        }.count
        var changed: [AlertRecord] = []
        var events: [AlertEvent] = []

        let candidates = Self.prioritized(evaluation.candidates)

        for candidate in candidates {
            let previous = records[candidate.key]
            let transition: AlertTransition?
            if let previous, previous.status == .active {
                if candidate.severity.alertRank > previous.candidate.severity.alertRank {
                    transition = .escalated
                } else if candidate.severity != previous.candidate.severity
                            || candidate.title != previous.candidate.title
                            || candidate.coverage != previous.candidate.coverage {
                    transition = .updated
                } else {
                    transition = nil
                }
            } else {
                transition = .raised
            }

            var suppression: AlertSuppression?
            if transition == .raised || transition == .escalated {
                suppression = AlertNotificationDecision().decide(AlertNotificationContext(
                    candidate: candidate, previousNotification: previous?.lastNotifiedAt,
                    notificationsInWindow: notified, now: now, configuration: configuration
                ))
            } else if transition == .updated {
                suppression = .notEscalated
            }
            let notify = transition != nil && suppression == nil
            if notify { notified += 1 }

            let isNewOccurrence = previous?.status != .active
            let record = AlertRecord(
                candidate: candidate, status: .active,
                firstSeenAt: previous?.firstSeenAt ?? now,
                raisedAt: isNewOccurrence ? now : previous?.raisedAt ?? now,
                lastSeenAt: now, resolvedAt: nil,
                lastNotifiedAt: notify ? now : previous?.lastNotifiedAt,
                occurrences: (previous?.occurrences ?? 0) + (isNewOccurrence ? 1 : 0)
            )
            changed.append(record)
            if let transition {
                events.append(AlertEvent(
                    transition: transition, record: record, notify: notify, suppression: suppression
                ))
            }
        }

        let currentKeys = Set(candidates.map { (candidate: AlertCandidate) in candidate.key })
        let resolvable = existing.filter { record in
            record.status == .active && evaluation.scopes.contains(record.candidate.scope)
                && !currentKeys.contains(record.id)
        }.sorted { $0.id < $1.id }
        for previous in resolvable {
            let requested = configuration.notifyResolutions && previous.lastNotifiedAt != nil
            let withinLimit = notified < configuration.maximumNotificationsPerWindow
            let notify = requested && withinLimit
            if notify { notified += 1 }
            let record = AlertRecord(
                candidate: previous.candidate, status: .resolved, firstSeenAt: previous.firstSeenAt,
                raisedAt: previous.raisedAt, lastSeenAt: previous.lastSeenAt, resolvedAt: now,
                lastNotifiedAt: notify ? now : previous.lastNotifiedAt, occurrences: previous.occurrences
            )
            changed.append(record)
            events.append(AlertEvent(
                transition: .resolved, record: record, notify: notify,
                suppression: requested ? .rateLimited : .resolutionNotRequested
            ))
        }
        return AlertTrackerResult(changedRecords: changed, events: events)
    }

    /// One candidate per key; higher severity first so the rate limit keeps the most serious alerts.
    static func prioritized(_ candidates: [AlertCandidate]) -> [AlertCandidate] {
        var unique: [String: AlertCandidate] = [:]
        for candidate in candidates where unique[candidate.key] == nil {
            unique[candidate.key] = candidate
        }
        return unique.values.sorted { (lhs: AlertCandidate, rhs: AlertCandidate) -> Bool in
            let left = lhs.severity.alertRank
            let right = rhs.severity.alertRank
            return left == right ? lhs.key < rhs.key : left > right
        }
    }
}
