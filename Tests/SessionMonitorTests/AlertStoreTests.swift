import Foundation
import MonitorCore
import MonitorPolicies
import MonitorStore
import Testing

struct AlertStoreTests {
    @Test func persistsTransitionsWithoutChangingCanonicalWatermark() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "usage.sqlite")
        let store = try UsageStore(url: url)
        let query = try UsageQuery()
        let before = try #require(try store.snapshot(query: query)).watermark

        let candidate = AlertCandidate(
            key: "anomaly|fixture|session", scope: AlertScope("anomaly:session:session"), source: .anomaly,
            kind: "fixture", severity: .warning, title: "Fixture", message: "Fixture message.",
            sessionIDs: ["session"], evidence: DiagnosticEvidence(
                observed: [DiagnosticEvidenceItem(source: "confirmed", detail: "Fixture.", sourceLines: [3])]
            )
        )
        let raised = try store.applyAlertEvaluation(AlertEvaluation(
            scopes: [], candidates: [candidate], observedAt: Date(timeIntervalSince1970: 100)
        ))
        #expect(raised.map(\.transition) == [.raised])

        // Reopening the database must keep dedup state, so an unchanged signal stays silent.
        let reopened = try UsageStore(url: url)
        let repeated = try reopened.applyAlertEvaluation(AlertEvaluation(
            scopes: [], candidates: [candidate], observedAt: Date(timeIntervalSince1970: 160)
        ))
        #expect(repeated.isEmpty)
        let active = try reopened.alertRecords(status: .active)
        #expect(active.count == 1)
        #expect(active.first?.candidate == candidate)
        #expect(active.first?.lastSeenAt == Date(timeIntervalSince1970: 160))
        #expect(active.first?.lastNotifiedAt == Date(timeIntervalSince1970: 100))

        let resolved = try reopened.applyAlertEvaluation(AlertEvaluation(
            scopes: [candidate.scope], candidates: [], observedAt: Date(timeIntervalSince1970: 200)
        ))
        #expect(resolved.map(\.transition) == [.resolved])
        #expect(try reopened.alertRecords(status: .active).isEmpty)
        #expect(try reopened.alertRecords(status: .resolved).map(\.id) == [candidate.key])
        #expect(try reopened.alertRecords().count == 1)

        let pending = try reopened.pendingAlertEvents()
        #expect(pending.map(\.event.transition) == [.raised, .resolved])
        try reopened.acknowledgeAlertEvents(ids: pending.map(\.id))
        #expect(try reopened.pendingAlertEvents().isEmpty)

        let after = try #require(try reopened.snapshot(query: query)).watermark
        #expect(after == before)
    }
}
