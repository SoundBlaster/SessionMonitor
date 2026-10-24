import CodexSource
import Foundation
import MonitorCore
import MonitorRuntime
import Testing

struct SessionTitleTests {
    @Test func importAndRenameWithoutReadingUnchangedRollouts() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let home = fixture.directory.appending(path: "codex")
        let file = try makeSource(home: home, content: fixture.native + fixture.record())
        let index = home.appending(path: "session_index.jsonl")
        try writeIndex(index, title: "Original chat")
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(file)
        let first = try await runtime.snapshot(query: UsageQuery())
        #expect(first.provenance["S"]?.sessionTitle == "Original chat")
        try writeIndex(index, title: "Renamed chat")
        let update = try await runtime.importDirectory(file)
        let renamed = try await runtime.snapshot(query: UsageQuery())
        #expect(update.ioMetrics.filesSkipped == 1)
        #expect(update.records == 0)
        #expect(renamed.provenance["S"]?.sessionTitle == "Renamed chat")
        #expect(renamed.watermark.revision > first.watermark.revision)
        #expect(renamed.report == first.report)
        _ = try await runtime.importDirectory(file)
        #expect(try await runtime.snapshot(query: UsageQuery()).watermark == renamed.watermark)
        let export = try #require(try await runtime.anonymizedSessionExport(sessionID: "S", query: UsageQuery()))
        let json = try #require(String(data: export.encodedJSON(), encoding: .utf8))
        #expect(!json.contains("Renamed chat"))
        try FileManager.default.removeItem(at: index)
        _ = try await runtime.importDirectory(file)
        #expect(try await runtime.snapshot(query: UsageQuery()).provenance["S"]?.sessionTitle == nil)
    }

    @Test func duplicateIDsAcrossAccountsDoNotLeakTitles() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let firstHome = fixture.directory.appending(path: "first")
        let secondHome = fixture.directory.appending(path: "second")
        let first = try makeSource(home: firstHome, content: fixture.native + fixture.record())
        let second = try makeSource(home: secondHome, content: fixture.native + fixture.record(id: "R2"))
        try writeIndex(firstHome.appending(path: "session_index.jsonl"), title: "Personal title")
        try writeIndex(secondHome.appending(path: "session_index.jsonl"), title: "Work title")
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(first)
        _ = try await runtime.importDirectory(second)
        _ = try await runtime.assignAccountProfile(root: firstHome, profileID: "personal", label: "Personal")
        _ = try await runtime.assignAccountProfile(root: secondHome, profileID: "work", label: "Work")
        let personal = try UsageQuery(accountScope: UsageAccountScope(profileID: "personal"))
        let work = try UsageQuery(accountScope: UsageAccountScope(profileID: "work"))
        #expect(try await runtime.snapshot(query: personal).provenance["S"]?.sessionTitle == "Personal title")
        #expect(try await runtime.snapshot(query: work).provenance["S"]?.sessionTitle == "Work title")
        #expect(try await runtime.snapshot(query: UsageQuery()).provenance["S"]?.sessionTitle == nil)
    }

    @Test func parserUsesLastValidNameAndIgnoresMalformedAndEmptyNames() throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let index = fixture.directory.appending(path: "session_index.jsonl")
        try writeIndex(index, title: "First")
        let data = try JSONSerialization.data(withJSONObject: ["id": "S", "thread_name": " Last "])
        let empty = try JSONSerialization.data(withJSONObject: ["id": "S", "thread_name": " "])
        let content = try Data(contentsOf: index) + data + Data("\ninvalid\n".utf8)
            + empty + Data("\n{".utf8)
        try content.write(to: index)
        #expect(SessionTitleIndex.read(index) == ["S": "Last"])
        #expect(SessionTitleIndex.indexURL(for: fixture.file) == nil)
        #expect(SessionTitleIndex.read(fixture.directory.appending(path: "missing")) == [:])
    }

    private func makeSource(home: URL, content: String) throws -> URL {
        let directory = home.appending(path: "sessions/2026/10")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "rollout.jsonl")
        try Data(content.utf8).write(to: file)
        return file
    }

    private func writeIndex(_ url: URL, title: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["id": "S", "thread_name": title])
        try (data + Data([10])).write(to: url, options: .atomic)
    }
}
