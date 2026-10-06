import Foundation
import MonitorCore
import MonitorRuntime
import Testing

struct AlertCenterTests {
    @Test func deliversEachCommittedTransitionToEverySinkOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = try SessionMonitor(databaseURL: directory.appending(path: "usage.sqlite"))
        let first = CollectingAlertSink()
        let lines = LineCollector()
        let center = AlertCenter(monitor: monitor, sinks: [
            first, JSONLinesAlertSink { await lines.append($0) }
        ])
        let candidate = AlertCandidate(
            key: "watch|recovering", scope: AlertScope("watch:root"), source: .watch, kind: "recovering",
            severity: .warning, title: "Watch recovering", message: "Watch is reconciling after an error."
        )

        try await center.submit(AlertEvaluation(
            scopes: [], candidates: [candidate], observedAt: Date(timeIntervalSince1970: 0)
        ))
        try await center.submit(AlertEvaluation(
            scopes: [], candidates: [candidate], observedAt: Date(timeIntervalSince1970: 30)
        ))
        try await center.submit(AlertEvaluation(
            scopes: [candidate.scope], candidates: [], observedAt: Date(timeIntervalSince1970: 60)
        ))

        #expect(await first.events.map(\.transition) == [.raised, .resolved])
        #expect(await first.events.map(\.notify) == [true, false])
        let decoded = try await lines.values.map { line -> AlertEvent in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AlertEvent.self, from: line)
        }
        #expect(decoded == (await first.events))
        #expect(await lines.values.allSatisfy { $0.last == 10 })
        #expect(try await monitor.alerts(status: .resolved).map(\.id) == ["watch|recovering"])
    }
}

private actor CollectingAlertSink: AlertSink {
    private(set) var events: [AlertEvent] = []

    func deliver(_ events: [AlertEvent]) async {
        self.events.append(contentsOf: events)
    }
}

private actor LineCollector {
    private(set) var values: [Data] = []

    func append(_ line: Data) {
        values.append(line)
    }
}
