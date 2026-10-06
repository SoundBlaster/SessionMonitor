import Foundation
import MonitorCore
import MonitorPolicies
@testable import MonitorRuntime
import MonitorStore
import Testing

struct AlertWatchdogTests {
    @Test func raisesExistingAnomalyOnceAndResolvesWhenSessionLeavesWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "usage.sqlite")
        let now = Date()
        let start = now.timeIntervalSince1970 - 300
        var rollout = ParsedRollout()
        rollout.records = [
            Self.record(id: "S1", turn: "first", at: start, input: 1_000, line: 1),
            Self.record(id: "S2", turn: "first", at: start + 1, input: 1_000, line: 2),
            Self.record(id: "S3", turn: "later", at: start + 2, input: 100, line: 3)
        ]
        rollout.provenance = SessionProvenance(sessionID: "busy", models: ["fixture"])
        try UsageStore(url: url).replace(source: "busy", rollout: rollout)

        let monitor = try SessionMonitor(databaseURL: url)
        let sink = RecordingSink()
        let watchdog = AlertWatchdog(
            monitor: monitor, center: AlertCenter(monitor: monitor, sinks: [sink]),
            options: AlertWatchdogOptions(lookback: 3_600)
        )

        let raised = try await watchdog.evaluate(now: now)
        let startup = try #require(raised.first { $0.record.id == "anomaly|excessive_startup_overhead|busy" })
        #expect(startup.transition == .raised)
        #expect(startup.notify)
        #expect(!raised.contains { $0.record.candidate.source == .cacheThreshold })

        #expect(try await watchdog.evaluate(now: now.addingTimeInterval(60)).isEmpty)

        let later = try await watchdog.evaluate(now: now.addingTimeInterval(7_200))
        #expect(later.contains { $0.record.id == startup.record.id && $0.transition == .resolved })
        #expect(await sink.events.contains { $0.record.id == startup.record.id && $0.transition == .raised })
        #expect(try await monitor.pendingAlertEvents().isEmpty)
    }

    @Test func watchHealthRaisesWhileRecoveringAndResolvesWhenWatching() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = try SessionMonitor(databaseURL: directory.appending(path: "usage.sqlite"))
        let watchdog = AlertWatchdog(monitor: monitor, center: AlertCenter(monitor: monitor))
        let root = URL(fileURLWithPath: "/tmp/sessions", isDirectory: true)

        var status = WatchStatus()
        status.phase = .recovering
        status.error = "Permission denied"
        let raised = try await watchdog.handle(status, root: root)
        #expect(raised.map(\.transition) == [.raised])
        #expect(raised.first?.record.candidate.source == .watch)
        #expect(raised.first?.record.candidate.message.contains("Permission denied") == true)

        #expect(try await watchdog.handle(status, root: root).isEmpty)

        status.phase = .watching
        status.error = nil
        let resolved = try await watchdog.handle(status, root: root)
        #expect(resolved.map(\.transition) == [.resolved])
    }

    @Test func newWatchStartsImportCountingAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = try SessionMonitor(databaseURL: directory.appending(path: "usage.sqlite"))
        let watchdog = AlertWatchdog(monitor: monitor, center: AlertCenter(monitor: monitor))
        let first = URL(fileURLWithPath: "/tmp/first", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/second", isDirectory: true)

        var status = WatchStatus()
        status.phase = .watching
        status.completedImports = 5
        _ = try await watchdog.handle(status, root: first)
        #expect(await watchdog.evaluatedImports == 5)

        status.completedImports = 1
        _ = try await watchdog.handle(status, root: second)
        #expect(await watchdog.evaluatedImports == 1)

        status.completedImports = 3
        _ = try await watchdog.handle(status, root: second)
        #expect(await watchdog.evaluatedImports == 3)

        // Same root restarted: its counter goes back down, so it is a new watch as well.
        status.completedImports = 1
        _ = try await watchdog.handle(status, root: second)
        #expect(await watchdog.evaluatedImports == 1)
    }

    /// 90% cache hit keeps the fixture above the default cache threshold.
    private static func record(
        id: String, turn: String, at seconds: TimeInterval, input: Int64, line: Int
    ) -> UsageRecord {
        UsageRecord(
            responseID: id, sessionID: "busy", turnID: turn, timestamp: Date(timeIntervalSince1970: seconds),
            model: "fixture", inputTokens: input, cachedInputTokens: input * 9 / 10, outputTokens: 10,
            sourceLine: line
        )
    }
}

private actor RecordingSink: AlertSink {
    private(set) var events: [AlertEvent] = []

    func deliver(_ events: [AlertEvent]) async {
        self.events.append(contentsOf: events)
    }
}
