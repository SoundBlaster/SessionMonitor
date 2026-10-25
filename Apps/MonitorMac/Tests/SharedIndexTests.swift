import Foundation
import MonitorCore
import MonitorRuntime
import Synchronization
import Testing
@testable import SessionMonitor

@MainActor
struct SharedIndexTests {
    @Test func firstStoreLaunchDoesNotCreateFallbackIndex() async throws {
        let fixture = try SharedIndexFixture()
        defer { fixture.remove() }
        await #expect(throws: SharedIndexError.self) { try await fixture.loader().load() }
        #expect(!FileManager.default.fileExists(atPath: fixture.fallback.path))
    }

    @Test func existingIndexRetainsHistoryWatermarkAndIncrementalCheckpoint() async throws {
        let fixture = try SharedIndexFixture()
        defer { fixture.remove() }
        let file = fixture.root.appending(path: "rollout.jsonl")
        let record = """
        {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta",\
        "payload":{"id":"S","timestamp":"1970-01-01T00:01:40Z"}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg",\
        "payload":{"type":"task_started","turn_id":"T","started_at":101}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"turn_context","payload":{"turn_id":"T","model":"fixture"}}
        {"timestamp":"1970-01-01T00:01:42Z","type":"token_usage_record",\
        "payload":{"thread_id":"S","turn_id":"T","response_id":"R",\
        "usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10}}}

        """
        try Data(record.utf8).write(to: file)
        let external = try MonitorRuntime.SessionMonitor(databaseURL: fixture.database)
        _ = try await external.importDirectory(file)
        _ = try await external.assignAccountProfile(root: fixture.root, profileID: "fixture", label: "Existing profile")
        let query = try UsageQuery()
        let before = try await external.snapshot(query: query)
        #expect(before.report.totals.requests == 1)
        let loader = fixture.loader()
        let selected = try await loader.selectIndex(fixture.root)
        #expect(selected.databaseURL == fixture.database)
        #expect(fixture.probe.state.withLock { $0.starts - $0.stops } == 1)
        let app = try await loader.load()
        let fromApp = try await app.snapshot(query: query)
        #expect(fromApp.watermark == before.watermark)
        #expect(fromApp.report == before.report)
        #expect(try await app.accountProfiles() == external.accountProfiles())
        let skipped = try await app.importDirectory(file, progress: nil)
        #expect(skipped.ioMetrics.filesSkipped == 1)
        #expect(skipped.ioMetrics.bytesRead == 0)
        let restarted = fixture.loader()
        #expect(try await restarted.restoreIndex().databaseURL == fixture.database)
        #expect(try await restarted.load().snapshot(query: query).report == before.report)
        #expect(!FileManager.default.fileExists(atPath: fixture.fallback.path))
    }

    @Test func selectingAnotherIndexKeepsActiveRuntimeUntilRestart() async throws {
        let fixture = try SharedIndexFixture()
        defer { fixture.remove() }
        let loader = fixture.loader()
        _ = try await loader.selectIndex(fixture.root)
        let active = try await loader.load()
        let next = fixture.root.appending(path: "next", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        let model = SharedIndexLocationModel(restore: { try await loader.restoreIndex() },
                                            select: { try await loader.selectIndex($0) })
        await model.restoreIfNeeded()
        await model.selectDirectory(next)
        #expect(model.isReady && model.needsRestart)
        #expect(model.connection?.databaseURL == fixture.database)
        #expect(model.connection?.selectedDirectory == next)
        #expect(try await loader.load() === active)
        #expect(!FileManager.default.fileExists(atPath: next.appending(path: "usage.sqlite").path))
        let restarted = try await fixture.loader().restoreIndex()
        #expect(restarted.databaseURL == next.appending(path: "usage.sqlite"))
    }

    @Test func revokedGrantDoesNotOpenFallbackAndReselectionRecovers() async throws {
        let fixture = try SharedIndexFixture()
        defer { fixture.remove() }
        _ = try await fixture.loader().selectIndex(fixture.root)
        fixture.probe.state.withLock { $0.rejectResolve = true }
        let loader = fixture.loader()
        let model = SharedIndexLocationModel(restore: { try await loader.restoreIndex() },
                                            select: { try await loader.selectIndex($0) })
        await model.restoreIfNeeded()
        #expect(!model.isReady)
        #expect(model.errorMessage?.contains("Choose the folder again") == true)
        #expect(!FileManager.default.fileExists(atPath: fixture.fallback.path))
        await model.selectDirectory(fixture.root)
        #expect(model.isReady)
        #expect(model.errorMessage == nil)
    }

    @Test func failedBookmarkOrDatabaseOpenPreservesPreviousSelection() async throws {
        let fixture = try SharedIndexFixture()
        defer { fixture.remove() }
        _ = try await fixture.loader().selectIndex(fixture.root)
        let saved = fixture.defaults.data(forKey: SharedIndexSettings.directoryKey + ".bookmark")
        let invalid = fixture.root.appending(path: "invalid", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
        try Data("not SQLite".utf8).write(to: invalid.appending(path: "usage.sqlite"))
        await #expect(throws: (any Error).self) { try await fixture.loader().selectIndex(invalid) }
        #expect(fixture.defaults.data(forKey: SharedIndexSettings.directoryKey + ".bookmark") == saved)
        fixture.probe.state.withLock { $0.rejectCreate = true }
        await #expect(throws: (any Error).self) { try await fixture.loader().selectIndex(invalid) }
        #expect(fixture.defaults.string(forKey: SharedIndexSettings.directoryKey) == fixture.root.path)
    }

    @Test func failedSelectionKeepsDisplayedConnection() async throws {
        let fixture = try SharedIndexFixture()
        defer { fixture.remove() }
        let loader = fixture.loader()
        let model = SharedIndexLocationModel(restore: { try await loader.restoreIndex() },
                                            select: { try await loader.selectIndex($0) })
        await model.selectDirectory(fixture.root)
        let previous = model.connection
        fixture.probe.state.withLock { $0.rejectCreate = true }
        await model.selectDirectory(fixture.root.appending(path: "bad"))
        #expect(model.connection == previous)
        #expect(model.errorMessage != nil)
        #expect(!model.isBusy)
    }

    @Test func cliCommandQuotesEntirePathIncludingApostrophes() {
        let url = URL(fileURLWithPath: "/tmp/Agent's index/$literal/usage.sqlite")
        #expect(SharedIndexSettings.reportCommand(databaseURL: url)
                == "codex-monitor report --database '/tmp/Agent'\\''s index/$literal/usage.sqlite'")
    }

    @Test func storePickerSuggestsRealSessionsWithoutPreGrantExistenceProbe() {
        let home = URL(fileURLWithPath: "/not-readable/home", isDirectory: true)
        #expect(RolloutDirectorySelection.initialDirectory(preferred: nil, home: home, year: 2026,
                                                          requiresBookmarks: true)
                == home.appending(path: ".codex/sessions/2026", directoryHint: .isDirectory))
    }
}

@MainActor
private struct SharedIndexFixture {
    let root = URL.temporaryDirectory.appending(path: "SharedIndexTests-\(UUID())", directoryHint: .isDirectory)
    let suite = "SharedIndexTests.\(UUID())"
    let defaults: UserDefaults
    let probe = SharedIndexBookmarkProbe()
    var database: URL { root.appending(path: "usage.sqlite") }
    var fallback: URL { root.appending(path: "private-fallback/usage.sqlite") }

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func loader() -> SessionMonitorRuntimeLoader {
        SessionMonitorRuntimeLoader(databaseURL: fallback, publishesWidgets: false, requiresSharedIndex: true,
                                    preferencesSuite: suite, indexBookmarks: probe.client)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class SharedIndexBookmarkProbe: Sendable {
    struct State {
        var rejectCreate = false
        var rejectResolve = false
        var starts = 0
        var stops = 0
    }
    let state = Mutex(State())
    var client: FolderBookmarkClient {
        FolderBookmarkClient(create: { [self] url in
            if state.withLock({ $0.rejectCreate }) { throw CocoaError(.fileWriteNoPermission) }
            return Data(url.path.utf8)
        }, resolve: { [self] data in
            if state.withLock({ $0.rejectResolve }) { throw CocoaError(.fileReadNoPermission) }
            let path = try #require(String(data: data, encoding: .utf8))
            return (URL(fileURLWithPath: path, isDirectory: true), false)
        }, startAccess: { [self] _ in state.withLock { $0.starts += 1 }; return true },
           stopAccess: { [self] _ in state.withLock { $0.stops += 1 } })
    }
}
