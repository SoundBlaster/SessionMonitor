import CodexSource
import Foundation
import MonitorCore
import MonitorRuntime
import MonitorStore
import Testing

struct SessionStorageTests {
    @Test func sizeFollowsAppendReplacementAndUnchangedImport() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let content = fixture.native + fixture.record() + "{\"partial\":"
        try fixture.write(content)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let initial = try #require(try await runtime.report().sessions.first?.sourceStorage)
        #expect(initial.totalBytes == Int64(content.utf8.count))
        #expect(initial.fileCount == 1)
        let store = try UsageStore(url: fixture.database)
        let beforeWatermark = try watermark(store)
        let skipped = try await runtime.importDirectory(fixture.file)
        #expect(skipped.ioMetrics.bytesRead == 0)
        #expect(try watermark(store) == beforeWatermark)
        try fixture.append("1}\n" + fixture.record(id: "R2"))
        _ = try await runtime.importDirectory(fixture.file)
        let appended = try #require(try await runtime.report().sessions.first?.sourceStorage)
        #expect(appended.totalBytes == Int64(try Data(contentsOf: fixture.file).count))
        #expect(appended.knownBytes > initial.knownBytes)
        try fixture.overwrite(fixture.native + fixture.record())
        _ = try await runtime.importDirectory(fixture.file)
        #expect(try await runtime.report().sessions.first?.sourceStorage?.totalBytes
                == Int64((fixture.native + fixture.record()).utf8.count))
    }

    @Test func oldCheckpointBackfillsSizeWithoutReadingBodyAndQueriesDoNotReadFiles() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let original = try RolloutDecoder().parseIncrementally(fixture.file)
        var oldRollout = original.rollout
        oldRollout.sourceFile = nil
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source, update: SourceImport(
            rollout: oldRollout, checkpoint: original.checkpoint, mode: .replaced, bytesRead: original.bytesRead
        ), expectedCheckpoint: nil)
        #expect(try store.report(since: nil, until: nil).sessions.first?.sourceStorage == nil)
        let before = try watermark(store)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        let update = try await runtime.importDirectory(fixture.file)
        #expect(update.ioMetrics.bytesRead == 0)
        #expect(try watermark(store) != before)
        let report = try await runtime.report()
        #expect(report.sessions.first?.sourceStorage?.totalBytes == Int64(original.bytesRead))
        try FileManager.default.removeItem(at: fixture.file)
        #expect(try await runtime.report() == report)
        #expect(try await runtime.listSessions(query: UsageQuery()).sessions.first?.sourceStorage
                == report.sessions.first?.sourceStorage)
        #expect(try await runtime.inspect(sessionID: "S", query: UsageQuery())?.sourceStorage
                == report.sessions.first?.sourceStorage)
    }

    @Test func physicalLinksCountOnceButCopiesCountSeparatelyWithoutChangingTokens() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let bytes = Int64(try Data(contentsOf: fixture.file).count)
        try FileManager.default.linkItem(at: fixture.file, to: fixture.directory.appending(path: "hard.jsonl"))
        try FileManager.default.createSymbolicLink(at: fixture.directory.appending(path: "symbolic.jsonl"),
                                                  withDestinationURL: fixture.file)
        try FileManager.default.copyItem(at: fixture.file, to: fixture.directory.appending(path: "copy.jsonl.1"))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        let report = try await runtime.report()
        let size = try #require(report.sessions.first?.sourceStorage)
        #expect(size.fileCount == 2)
        #expect(size.totalBytes == bytes * 2)
        #expect(report.totals.requests == 1)
    }

    @Test func periodDoesNotProrateStorageAndSubagentsStaySeparate() throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try addSource(store, source: "parent", session: "P", bytes: 900, times: [100, 200])
        try addSource(store, source: "child", session: "C", bytes: 300, times: [100, 200], parent: "P")
        let query = try UsageQuery(since: Date(timeIntervalSince1970: 150))
        let report = try #require(try store.snapshot(query: query)).report
        #expect(report.sessions.first(where: { $0.id == "P" })?.sourceStorage?.totalBytes == 900)
        #expect(report.sessions.first(where: { $0.id == "C" })?.sourceStorage?.totalBytes == 300)
        #expect(report.totals.requests == 2)
    }

    @Test func accountScopeAndPartialSourcesAreExplicit() throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        let personal = fixture.directory.appending(path: "personal").path
        let work = fixture.directory.appending(path: "work").path
        _ = try store.assignAccountProfile(sourceRoot: URL(fileURLWithPath: personal),
                                           profileID: "p", label: "Personal")
        _ = try store.assignAccountProfile(sourceRoot: URL(fileURLWithPath: work), profileID: "w", label: "Work")
        try addSource(store, source: personal + "/one", session: "S", bytes: 500)
        try addSource(store, source: work + "/two", session: "S", bytes: 700)
        try addSource(store, source: personal + "/old", session: "S", bytes: nil)
        let personalReport = try #require(try store.snapshot(
            query: UsageQuery(accountScope: UsageAccountScope(profileID: "p"))))
        let size = try #require(personalReport.report.sessions.first?.sourceStorage)
        #expect(size.knownBytes == 500)
        #expect(size.totalBytes == nil)
        #expect(size.unknownSizeFileCount == 1)
        #expect(size.fileCount == 2)
        let workReport = try #require(try store.snapshot(
            query: UsageQuery(accountScope: UsageAccountScope(profileID: "w"))))
        #expect(workReport.report.sessions.first?.sourceStorage?.totalBytes == 700)
        #expect(try store.report(since: nil, until: nil).sessions.first?.sourceStorage?.knownBytes == 1_200)
        try addSource(store, source: "unmapped", session: "S", bytes: 200)
        let unknown = try #require(try store.snapshot(query: UsageQuery(accountScope: .unknownOrMixed)))
        #expect(unknown.report.sessions.first?.sourceStorage?.totalBytes == 200)
    }

    @Test func latestPhysicalFileOwnerWinsAcrossHardLinkedHistories() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let linked = fixture.directory.appending(path: "linked.jsonl")
        try FileManager.default.linkItem(at: fixture.file, to: linked)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let next = (fixture.native + fixture.record(id: "R2"))
            .replacingOccurrences(of: "\"S\"", with: "\"C\"")
        try fixture.append(next)
        _ = try await runtime.importDirectory(linked)
        let report = try await runtime.report()
        #expect(report.sessions.first(where: { $0.id == "S" })?.sourceStorage == nil)
        #expect(report.sessions.first(where: { $0.id == "C" })?.sourceStorage?.totalBytes
                == Int64(try Data(contentsOf: fixture.file).count))
        #expect(report.totals.requests == 2)
        _ = try await runtime.importDirectory(fixture.file)
        let refreshed = try await runtime.report()
        #expect(refreshed.totals == report.totals)
        #expect(refreshed.sessions == report.sessions)
    }

    @Test func observedZeroDiffersFromUnknownAndInvalidSizeRollsBack() throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try addSource(store, source: "zero", session: "S", bytes: 0)
        let before = try store.report(since: nil, until: nil)
        #expect(before.sessions.first?.sourceStorage?.totalBytes == 0)
        #expect(throws: (any Error).self) {
            try addSource(store, source: "zero", session: "S", bytes: -1)
        }
        #expect(try store.report(since: nil, until: nil) == before)
    }

    @Test func sourceSizeIsAdditiveJSONAndOlderSessionJSONStillDecodes() throws {
        let old = SessionSummary(id: "S", model: "fixture", totals: UsageTotals())
        let data = try JSONEncoder().encode(old)
        #expect(try JSONDecoder().decode(SessionSummary.self, from: data).sourceStorage == nil)
        let bytes = SessionStorageSummary(knownBytes: 100, fileCount: 2, unknownSizeFileCount: 1, lastModifiedAt: nil)
        #expect(try JSONDecoder().decode(SessionStorageSummary.self, from: JSONEncoder().encode(bytes)) == bytes)
        #expect(bytes.totalBytes == nil)
    }

    private func watermark(_ store: UsageStore) throws -> QueryWatermark {
        try #require(try store.snapshot(query: UsageQuery())).watermark
    }

    private func addSource(
        _ store: UsageStore, source: String, session: String, bytes: Int64?,
        times: [TimeInterval] = [100], parent: String? = nil
    ) throws {
        var rollout = ParsedRollout()
        rollout.provenance = SessionProvenance(sessionID: session,
            relationship: parent.map { SessionRelationship(kind: .subagent, parentSessionID: $0) })
        if let bytes {
            rollout.sourceFile = SourceFileObservation(sessionID: session, identity: source, byteCount: bytes,
                                                      modifiedAt: Date(timeIntervalSince1970: 500))
        }
        rollout.records = times.enumerated().map { index, time in
            UsageRecord(responseID: "\(source)-\(index)", sessionID: session, turnID: "T",
                        timestamp: Date(timeIntervalSince1970: time), model: "fixture", inputTokens: 100,
                        cachedInputTokens: 80, outputTokens: 10, sourceLine: index + 1)
        }
        try store.replace(source: source, rollout: rollout)
    }
}
