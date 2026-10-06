import Foundation
import MonitorCore
import MonitorPolicies
import Testing

struct AlertTrackerTests {
    @Test func raisesOnceAndStaysSilentWhileUnchanged() throws {
        let tracker = AlertTracker()
        let first = tracker.apply(Self.evaluation([Self.alert("A")], at: 0), to: [])
        #expect(first.events.map(\.transition) == [.raised])
        #expect(first.events.first?.notify == true)

        let second = tracker.apply(Self.evaluation([Self.alert("A", message: "new count")], at: 60),
                                   to: first.changedRecords)
        #expect(second.events.isEmpty)
        let record = try #require(second.changedRecords.first)
        #expect(record.lastSeenAt == Date(timeIntervalSince1970: 60))
        #expect(record.raisedAt == Date(timeIntervalSince1970: 0))
        #expect(record.candidate.message == "new count")
    }

    @Test func escalationNotifiesAndDowngradeIsRecordedSilently() {
        let tracker = AlertTracker(configuration: AlertPolicyConfiguration(cooldown: 0))
        let raised = tracker.apply(Self.evaluation([Self.alert("A", severity: .warning)], at: 0), to: [])
        let escalated = tracker.apply(Self.evaluation([Self.alert("A", severity: .error)], at: 10),
                                      to: raised.changedRecords)
        #expect(escalated.events.map(\.transition) == [.escalated])
        #expect(escalated.events.first?.notify == true)

        let downgraded = tracker.apply(Self.evaluation([Self.alert("A", severity: .warning)], at: 20),
                                       to: escalated.changedRecords)
        #expect(downgraded.events.map(\.transition) == [.updated])
        #expect(downgraded.events.first?.notify == false)
        #expect(downgraded.events.first?.suppression == .notEscalated)
    }

    @Test func resolvesOnlyAlertsInsideEvaluatedScopes() {
        let tracker = AlertTracker()
        let raised = tracker.apply(Self.evaluation([
            Self.alert("A", scope: "anomaly:session:one"), Self.alert("B", scope: "anomaly:session:two")
        ], at: 0), to: [])

        let partial = tracker.apply(
            AlertEvaluation(scopes: [AlertScope("anomaly:session:one")], candidates: [],
                            observedAt: Date(timeIntervalSince1970: 30)),
            to: raised.changedRecords
        )
        #expect(partial.events.map(\.transition) == [.resolved])
        #expect(partial.events.first?.record.id == "A")
        #expect(partial.events.first?.record.resolvedAt == Date(timeIntervalSince1970: 30))
        #expect(partial.events.first?.notify == false)
        #expect(partial.events.first?.suppression == .resolutionNotRequested)
    }

    @Test func cooldownSuppressesFlappingAndKeepsOccurrenceHistory() {
        let tracker = AlertTracker(configuration: AlertPolicyConfiguration(cooldown: 300))
        let scope = AlertScope("anomaly:session:session")
        var records = tracker.apply(Self.evaluation([Self.alert("A")], at: 0), to: []).changedRecords
        records = tracker.apply(AlertEvaluation(scopes: [scope], candidates: [],
                                                observedAt: Date(timeIntervalSince1970: 10)), to: records)
            .changedRecords

        let flapped = tracker.apply(Self.evaluation([Self.alert("A")], at: 20), to: records)
        #expect(flapped.events.map(\.transition) == [.raised])
        #expect(flapped.events.first?.notify == false)
        #expect(flapped.events.first?.suppression == .cooldown)
        #expect(flapped.events.first?.record.occurrences == 2)
        #expect(flapped.events.first?.record.firstSeenAt == Date(timeIntervalSince1970: 0))
        #expect(flapped.events.first?.record.raisedAt == Date(timeIntervalSince1970: 20))

        records = tracker.apply(AlertEvaluation(scopes: [scope], candidates: [],
                                                observedAt: Date(timeIntervalSince1970: 30)),
                                to: flapped.changedRecords).changedRecords
        let later = tracker.apply(Self.evaluation([Self.alert("A")], at: 400), to: records)
        #expect(later.events.first?.notify == true)
        #expect(later.events.first?.record.occurrences == 3)
    }

    @Test func rateLimitKeepsTheMostSevereAlerts() {
        let tracker = AlertTracker(configuration: AlertPolicyConfiguration(maximumNotificationsPerWindow: 2))
        let result = tracker.apply(Self.evaluation([
            Self.alert("a-warning", severity: .warning), Self.alert("b-error", severity: .error),
            Self.alert("c-warning", severity: .warning)
        ], at: 0), to: [])

        let notified = result.events.filter(\.notify).map(\.record.id)
        #expect(notified == ["b-error", "a-warning"])
        #expect(result.events.first { $0.record.id == "c-warning" }?.suppression == .rateLimited)
        #expect(result.events.count == 3)
    }

    @Test func rateLimitCountsNotificationsFromEarlierEvaluations() {
        let tracker = AlertTracker(configuration: AlertPolicyConfiguration(
            rateLimitWindow: 600, maximumNotificationsPerWindow: 1
        ))
        let first = tracker.apply(Self.evaluation([Self.alert("A", scope: "s1")], at: 0), to: [])
        let second = tracker.apply(Self.evaluation([Self.alert("B", scope: "s2")], at: 60), to: first.changedRecords)
        #expect(second.events.first?.suppression == .rateLimited)

        let afterWindow = tracker.apply(Self.evaluation([Self.alert("C", scope: "s3")], at: 700),
                                        to: first.changedRecords + second.changedRecords)
        #expect(afterWindow.events.first?.notify == true)
    }

    @Test func suppressionNamesTheFirstBlockingRule() {
        let tracker = AlertTracker(configuration: AlertPolicyConfiguration(mutedKinds: ["muted_kind"]))
        let result = tracker.apply(Self.evaluation([
            Self.alert("info", severity: .info),
            Self.alert("muted", kind: "muted_kind"),
            Self.alert("unknown", coverage: .unknown(reason: "No cache values."))
        ], at: 0), to: [])
        let suppression = Dictionary(uniqueKeysWithValues: result.events.map { ($0.record.id, $0.suppression) })

        #expect(suppression["info"] == .belowMinimumSeverity)
        #expect(suppression["muted"] == .muted)
        #expect(suppression["unknown"] == .uncertainCoverage)
        #expect(result.events.allSatisfy { !$0.notify })
        #expect(result.changedRecords.allSatisfy { $0.status == .active && $0.lastNotifiedAt == nil })
    }

    @Test func resolutionNotifiesOnlyWhenRequestedAndPreviouslyNotified() {
        let tracker = AlertTracker(configuration: AlertPolicyConfiguration(notifyResolutions: true))
        let raised = tracker.apply(Self.evaluation([
            Self.alert("loud"), Self.alert("quiet", severity: .info)
        ], at: 0), to: [])
        let resolved = tracker.apply(
            AlertEvaluation(scopes: [AlertScope("anomaly:session:session")], candidates: [],
                            observedAt: Date(timeIntervalSince1970: 60)),
            to: raised.changedRecords
        )
        let notify = Dictionary(uniqueKeysWithValues: resolved.events.map { ($0.record.id, $0.notify) })
        #expect(notify == ["loud": true, "quiet": false])
    }

    @Test func resolutionNotificationsShareTheRateLimit() {
        let tracker = AlertTracker(configuration: AlertPolicyConfiguration(
            cooldown: 0, rateLimitWindow: 60, maximumNotificationsPerWindow: 1, notifyResolutions: true
        ))
        var records: [AlertRecord] = []
        for (index, key) in ["A", "B", "C"].enumerated() {
            let evaluation = Self.evaluation([Self.alert(key, scope: key)], at: Double(index) * 100)
            records += tracker.apply(evaluation, to: records).changedRecords
        }
        let resolved = tracker.apply(
            AlertEvaluation(scopes: [AlertScope("A"), AlertScope("B"), AlertScope("C")], candidates: [],
                            observedAt: Date(timeIntervalSince1970: 1_000)),
            to: records
        )
        #expect(resolved.events.filter(\.notify).map(\.record.id) == ["A"])
        #expect(resolved.events.filter { !$0.notify }.allSatisfy { $0.suppression == .rateLimited })
    }

    @Test func duplicateKeysInOneEvaluationProduceOneAlert() {
        let result = AlertTracker().apply(Self.evaluation([Self.alert("A"), Self.alert("A")], at: 0), to: [])
        #expect(result.events.count == 1)
        #expect(result.changedRecords.count == 1)
    }

    static func alert(
        _ key: String, scope: String = "anomaly:session:session", kind: String = "fixture_kind",
        severity: DiagnosticSeverity = .warning, message: String = "Fixture message.",
        coverage: AnomalyCoverage = .observed
    ) -> AlertCandidate {
        AlertCandidate(
            key: key, scope: AlertScope(scope), source: .anomaly, kind: kind, severity: severity,
            title: "Fixture \(key)", message: message, sessionIDs: ["session"], coverage: coverage
        )
    }

    static func evaluation(_ candidates: [AlertCandidate], at seconds: TimeInterval) -> AlertEvaluation {
        AlertEvaluation(scopes: [], candidates: candidates, observedAt: Date(timeIntervalSince1970: seconds))
    }
}
