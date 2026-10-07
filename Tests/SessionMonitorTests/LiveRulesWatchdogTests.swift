import Foundation
import MonitorCore
import MonitorPolicies
@testable import MonitorRuntime
import MonitorStore
import Testing

struct LiveRulesWatchdogTests {
    @Test func burstAgainstOwnHistoryRaisesOnceReachesTheAgentAndResolvesWhenSessionEnds() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "usage.sqlite")
        let now = Date()
        let store = try UsageStore(url: url)
        // Six earlier sessions, each one busy 10-minute interval of 3 requests at 300 input tokens/min.
        let bucketStart = (now.timeIntervalSince1970 - 3 * 86_400).rounded(.down)
        let aligned = bucketStart - bucketStart.truncatingRemainder(dividingBy: 600)
        for index in 0..<6 {
            try Self.store(store, session: "history\(index)", input: 1_000, count: 3,
                           first: aligned - Double(index) * 7_200)
        }
        try Self.store(store, session: "live", input: 100_000, count: 5, first: now.timeIntervalSince1970 - 270)

        let monitor = try SessionMonitor(databaseURL: url)
        let options = AlertWatchdogOptions(
            lookback: 3_600, live: LiveRuleConfiguration(minimumBaselineBuckets: 5)
        )
        let watchdog = AlertWatchdog(monitor: monitor, center: AlertCenter(monitor: monitor), options: options)

        let raised = try await watchdog.evaluate(now: now)
        let burn = try #require(raised.first { $0.record.id == "live|burn_rate|live" })
        #expect(burn.transition == .raised)
        #expect(burn.notify)
        // Unknown history (too few completed turns / requests) must not produce loop or growth alerts.
        let unexpected: Set<String> = ["runaway_loop", "input_growth"]
        #expect(!raised.contains { unexpected.contains($0.record.candidate.kind) })
        #expect(!raised.contains { $0.record.candidate.sessionIDs.contains { $0.hasPrefix("history") }
            && $0.record.candidate.source == .liveRule })

        // The hook/agent surface sees the alert for its own session.
        let status = try await monitor.agentStatus(sessionID: "live", now: now, lookback: 3_600)
        #expect(status.alerts.contains { $0.key == "live|burn_rate|live" && $0.source == .liveRule })

        #expect(try await watchdog.evaluate(now: now.addingTimeInterval(30)).isEmpty)

        let later = try await watchdog.evaluate(now: now.addingTimeInterval(2_400))
        #expect(later.contains { $0.record.id == "live|burn_rate|live" && $0.transition == .resolved })
    }

    private static func store(
        _ store: UsageStore, session: String, input: Int64, count: Int, first: TimeInterval
    ) throws {
        var rollout = ParsedRollout()
        rollout.records = (0..<count).map { index in
            UsageRecord(
                responseID: "\(session)-\(index)", sessionID: session, turnID: "T",
                timestamp: Date(timeIntervalSince1970: first + Double(index) * 60), model: "fixture",
                inputTokens: input, cachedInputTokens: input * 9 / 10, outputTokens: 10, sourceLine: index + 1
            )
        }
        rollout.provenance = SessionProvenance(sessionID: session, models: ["fixture"])
        try store.replace(source: session, rollout: rollout)
    }
}
