import Foundation
import MonitorCore
import MonitorRuntime
import Testing

struct SandboxWatchFixtureTests {
    @Test func preservesExplicitAccountTotalsWhenSourceFolderMoves() async throws {
        let fixture = try SandboxWatchFixture(parent: .temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let database = fixture.index.appending(path: "usage.sqlite")
        do {
            let monitor = try MonitorRuntime.SessionMonitor(databaseURL: database)
            _ = try await monitor.importDirectory(fixture.source)
        }
        let moved = fixture.root.appending(path: "moved-rollouts", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: fixture.source, to: moved)
        try fixture.append(request: 2, directory: moved)
        let restarted = try MonitorRuntime.SessionMonitor(databaseURL: database)
        _ = try await restarted.importDirectory(moved)
        let report = try await restarted.snapshot(query: UsageQuery()).report
        #expect(report.totals.requests == 2)
        #expect(report.totals.inputTokens == 300)
        #expect(report.totals.outputTokens == 30)
    }

    @Test func producesCanonicalNativeUsageAndAppend() async throws {
        let fixture = try SandboxWatchFixture(parent: .temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let monitor = try MonitorRuntime.SessionMonitor(databaseURL: fixture.index.appending(path: "usage.sqlite"))
        let first = try await monitor.importDirectory(fixture.source)
        let query = try UsageQuery()
        let initial = try await monitor.snapshot(query: query)
        #expect(initial.report.totals.requests == 1, "Import: \(first)")
        #expect(initial.report.totals.inputTokens == 100)
        #expect(initial.report.totals.cachedInputTokens == 80)
        #expect(initial.report.totals.outputTokens == 10)
        try fixture.append(request: 2)
        _ = try await monitor.importDirectory(fixture.source)
        let appended = try await monitor.snapshot(query: query)
        #expect(appended.report.totals.requests == 2)
        #expect(appended.report.totals.inputTokens == 300)
        #expect(appended.report.totals.outputTokens == 30)
    }
}
