import Foundation
import MonitorCore
import MonitorStore
import Testing

struct QuerySnapshotTests {
    @Test func independentConnectionsReadAtomicWatermarkAndTotals() async throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let writer = try UsageStore(url: fixture.database)
        let reader = try UsageStore(url: fixture.database)
        let query = try UsageQuery()
        let writing = Task.detached {
            for revision in 1...40 {
                var rollout = ParsedRollout()
                rollout.records = [UsageRecord(
                    responseID: "R", sessionID: "S", turnID: "T",
                    timestamp: Date(timeIntervalSince1970: 100), model: "fixture",
                    inputTokens: 100, cachedInputTokens: Int64(revision), outputTokens: 10, sourceLine: 1
                )]
                try writer.replace(source: "source", rollout: rollout)
                await Task.yield()
            }
        }
        do {
            for _ in 0..<160 {
                let snapshot = try #require(try reader.snapshot(query: query))
                // Each committed replacement has exactly one request and cached tokens equal to its revision.
                #expect(snapshot.report.totals.cachedInputTokens == snapshot.watermark.revision)
                #expect(snapshot.report.totals.requests == (snapshot.watermark.revision == 0 ? 0 : 1))
                await Task.yield()
            }
            try await writing.value
            let final = try #require(try reader.snapshot(query: query))
            #expect(final.watermark.revision == 40)
            #expect(final.report.totals.cachedInputTokens == 40)
        } catch {
            // Join before removing the database, including when a read or requirement fails.
            _ = try? await writing.value
            throw error
        }
    }

    @Test func periodCoverageAndCodableRoundTrip() throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        var rollout = ParsedRollout()
        rollout.records = [fixture.record(line: 1, timestamp: 100),
                           fixture.record(line: 2, timestamp: 101, cached: nil),
                           fixture.record(line: 3, timestamp: 102)]
        rollout.diagnostics = ["legacySnapshotsNotCounted": 2]
        try store.replace(source: "source", rollout: rollout)
        let query = try UsageQuery(since: Date(timeIntervalSince1970: 100),
                                   until: Date(timeIntervalSince1970: 102),
                                   timeZoneIdentifier: "Europe/Moscow")
        let snapshot = try #require(try store.snapshot(query: query))
        #expect(snapshot.schemaVersion == 2)
        #expect(snapshot.query == query)
        #expect(snapshot.report.totals.requests == 2)
        #expect(snapshot.coverage.cache == .partial)
        #expect(snapshot.coverage.knownCacheRequests == 1)
        #expect(snapshot.coverage.unknownCacheRequests == 1)
        #expect(snapshot.report.diagnostics["legacySnapshotsNotCounted"] == 2)
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: encoded) == snapshot)
        let emptyQuery = try UsageQuery(until: Date(timeIntervalSince1970: 100))
        let empty = try #require(try store.snapshot(query: emptyQuery))
        #expect(empty.coverage.cache == .empty)
        #expect(empty.report.diagnostics["legacySnapshotsNotCounted"] == 2)
    }

    @Test func watermarkTracksCorrectionsDiagnosticsAndRollback() throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        let query = try UsageQuery()
        let initial = try #require(try store.snapshot(query: query))
        #expect(initial.watermark.revision == 0)
        #expect(initial.watermark.committedAt == nil)
        var rollout = ParsedRollout()
        rollout.records = [fixture.record(line: 1, timestamp: 100)]
        try store.replace(source: "source", rollout: rollout)
        let imported = try #require(try store.snapshot(query: query, after: initial.watermark))
        #expect(imported.watermark.revision > initial.watermark.revision)
        #expect(imported.watermark.committedAt != nil)
        #expect(imported.coverage.cache == .complete)
        #expect(try store.snapshot(query: query, after: imported.watermark) == nil)
        // Correct historical usage without moving the event timestamp forward.
        rollout.records = [fixture.record(line: 1, timestamp: 100, cached: nil)]
        try store.replace(source: "source", rollout: rollout)
        let corrected = try #require(try store.snapshot(query: query, after: imported.watermark))
        #expect(corrected.watermark.revision > imported.watermark.revision)
        #expect(corrected.coverage.cache == .partial)
        rollout.diagnostics = ["partialTails": 1]
        try store.replace(source: "source", rollout: rollout)
        let diagnosed = try #require(try store.snapshot(query: query, after: corrected.watermark))
        #expect(diagnosed.report.totals == corrected.report.totals)
        #expect(diagnosed.report.diagnostics["partialTails"] == 1)
        rollout.records.append(rollout.records[0])
        #expect(throws: (any Error).self) { try store.replace(source: "source", rollout: rollout) }
        #expect(try store.snapshot(query: query) == diagnosed)
        let reopened = try UsageStore(url: fixture.database)
        #expect(try reopened.snapshot(query: query) == diagnosed)
    }

    @Test func unchangedCheckpointDoesNotAdvanceWatermark() throws {
        let fixture = try SnapshotFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        let query = try UsageQuery()
        let checkpoint = Data("checkpoint".utf8)
        let replaced = SourceImport(rollout: ParsedRollout(), checkpoint: checkpoint,
                                    mode: .replaced, bytesRead: 0)
        try store.apply(source: "source", update: replaced, expectedCheckpoint: nil)
        let before = try #require(try store.snapshot(query: query))
        let unchanged = SourceImport(rollout: ParsedRollout(), checkpoint: checkpoint,
                                     mode: .unchanged, bytesRead: 0)
        try store.apply(source: "source", update: unchanged, expectedCheckpoint: checkpoint)
        #expect(try store.snapshot(query: query, after: before.watermark) == nil)
    }

    @Test func rejectsInvalidQueryIncludingDecodedInput() throws {
        let date = Date(timeIntervalSince1970: 100)
        #expect(throws: (any Error).self) { try UsageQuery(since: date, until: date) }
        #expect(throws: (any Error).self) { try UsageQuery(timeZoneIdentifier: "invalid/timezone") }
        #expect(throws: (any Error).self) { try UsageQuery(since: Date(timeIntervalSince1970: .infinity)) }
        let invalid = Data(#"{"since":100,"until":99,"timeZoneIdentifier":"UTC"}"#.utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(UsageQuery.self, from: invalid) }
    }

    @Test func legacyQueryWithoutAccountScopeDefaultsToAllAccounts() throws {
        let legacy = Data(#"{"timeZoneIdentifier":"UTC"}"#.utf8)
        let query = try JSONDecoder().decode(UsageQuery.self, from: legacy)
        #expect(query.accountScope == .allAccounts)
    }

    @Test func periodPresetsResolveUTCWindowsAndRemainCodable() throws {
        let reference = try instant("2026-09-12T14:30:00Z")
        let today = try UsagePeriodPreset.today.resolve(referenceDate: reference, timeZoneIdentifier: "UTC")
        let todayStart = try instant("2026-09-12T00:00:00Z")
        let nextDay = try instant("2026-09-13T00:00:00Z")
        #expect(today.since == todayStart)
        #expect(today.until == nextDay)
        #expect(today.timeZoneIdentifier == "UTC")

        let sevenDays = try UsagePeriodPreset.lastSevenDays.resolve(
            referenceDate: reference, timeZoneIdentifier: "UTC"
        )
        let sevenDaysStart = try instant("2026-09-06T00:00:00Z")
        #expect(sevenDays.since == sevenDaysStart)
        #expect(sevenDays.until == today.until)
        let thirtyDays = try UsagePeriodPreset.lastThirtyDays.resolve(
            referenceDate: reference, timeZoneIdentifier: "UTC"
        )
        let thirtyDaysStart = try instant("2026-08-14T00:00:00Z")
        #expect(thirtyDays.since == thirtyDaysStart)
        #expect(thirtyDays.until == today.until)

        let all = try UsagePeriodPreset.all.resolve(referenceDate: reference, timeZoneIdentifier: "UTC")
        #expect(all.since == nil)
        #expect(all.until == nil)
        let encoded = try JSONEncoder().encode(UsagePeriodPreset.lastSevenDays)
        #expect(try JSONDecoder().decode(UsagePeriodPreset.self, from: encoded) == .lastSevenDays)
        #expect(Set([today, sevenDays, thirtyDays, all]).count == 4)
    }

    @Test func berlinTodayUsesDSTSafeSpringAndFallCalendarWindows() throws {
        let spring = try UsagePeriodPreset.today.resolve(
            referenceDate: try instant("2026-03-29T12:00:00Z"),
            timeZoneIdentifier: "Europe/Berlin"
        )
        let springStart = try instant("2026-03-28T23:00:00Z")
        let springEnd = try instant("2026-03-29T22:00:00Z")
        #expect(spring.since == springStart)
        #expect(spring.until == springEnd)
        #expect(springEnd.timeIntervalSince(springStart) == 23 * 60 * 60)

        let fall = try UsagePeriodPreset.today.resolve(
            referenceDate: try instant("2026-10-25T12:00:00Z"),
            timeZoneIdentifier: "Europe/Berlin"
        )
        let fallStart = try instant("2026-10-24T22:00:00Z")
        let fallEnd = try instant("2026-10-25T23:00:00Z")
        #expect(fall.since == fallStart)
        #expect(fall.until == fallEnd)
        #expect(fallEnd.timeIntervalSince(fallStart) == 25 * 60 * 60)
    }
}

private func instant(_ value: String) throws -> Date {
    try Date.ISO8601FormatStyle().parse(value)
}

private struct SnapshotFixture {
    let directory: URL
    var database: URL { directory.appending(path: "usage.sqlite") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func record(line: Int, timestamp: TimeInterval, cached: Int64? = 80) -> UsageRecord {
        UsageRecord(responseID: "R\(line)", sessionID: "S", turnID: "T",
                    timestamp: Date(timeIntervalSince1970: timestamp), model: "fixture",
                    inputTokens: 100, cachedInputTokens: cached, outputTokens: 10, sourceLine: line)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
