import Foundation
import MonitorCore
import MonitorRuntime
import Testing

struct SandboxWatchFixtureTests {
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
