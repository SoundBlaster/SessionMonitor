import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

@MainActor
final class SharedReportRuntimeTests: XCTestCase {
    func testMatchingNondefaultSubscribersShareSourceCacheLatestAndRestartAfterLastCancellation() async throws {
        let source = StubSharedRuntime()
        let runtime = SharedReportRuntime(runtime: source)
        let query = try UsageQuery(
            since: Date(timeIntervalSince1970: 100),
            until: Date(timeIntervalSince1970: 200),
            timeZoneIdentifier: "Europe/Moscow"
        )

        let firstRecorder = SnapshotRecorder()
        let first = consume(await runtime.snapshots(query: query), into: firstRecorder)
        try await eventually { await source.snapshotsCalls == 1 }
        let initial = fixtureSnapshot(query: query, revision: 1)
        await source.yield(initial, connection: 1)
        try await eventually { await firstRecorder.values.count == 1 }

        let secondRecorder = SnapshotRecorder()
        let second = consume(await runtime.snapshots(query: query), into: secondRecorder)
        try await eventually { await secondRecorder.values == [initial] }
        let callsAfterSecondSubscriber = await source.snapshotsCalls
        XCTAssertEqual(callsAfterSecondSubscriber, 1)

        first.cancel()
        await first.value
        try await Task.sleep(for: .milliseconds(20))
        let terminationsAfterFirstCancellation = await source.terminations
        XCTAssertEqual(terminationsAfterFirstCancellation, 0)

        let update = fixtureSnapshot(query: query, revision: 2)
        await source.yield(update, connection: 1)
        try await eventually { await secondRecorder.values == [initial, update] }

        second.cancel()
        await second.value
        try await eventually { await source.terminations == 1 }

        let reopenedRecorder = SnapshotRecorder()
        let reopened = consume(await runtime.snapshots(query: query), into: reopenedRecorder)
        try await eventually { await source.snapshotsCalls == 2 }
        let reopenedValue = fixtureSnapshot(query: query, revision: 3)
        await source.yield(reopenedValue, connection: 2)
        try await eventually { await reopenedRecorder.values == [reopenedValue] }
        reopened.cancel()
        await reopened.value
        try await eventually { await source.terminations == 2 }

        let calls = await source.calls
        XCTAssertEqual(calls.imports, 0)
        XCTAssertEqual(calls.snapshotReads, 0)
        XCTAssertEqual(calls.snapshotStreams, 2)
    }

    func testDistinctQueriesOwnIndependentSourcesAndCleanup() async throws {
        let source = StubSharedRuntime()
        let runtime = SharedReportRuntime(runtime: source)
        let utc = try UsageQuery(since: Date(timeIntervalSince1970: 100),
                                 until: Date(timeIntervalSince1970: 200))
        let moscow = try UsageQuery(since: Date(timeIntervalSince1970: 100),
                                    until: Date(timeIntervalSince1970: 200),
                                    timeZoneIdentifier: "Europe/Moscow")
        let utcRecorder = SnapshotRecorder()
        let moscowRecorder = SnapshotRecorder()
        let utcConsumer = consume(await runtime.snapshots(query: utc), into: utcRecorder)
        let moscowConsumer = consume(await runtime.snapshots(query: moscow), into: moscowRecorder)
        try await eventually { await source.snapshotsCalls == 2 }

        let utcSnapshot = fixtureSnapshot(query: utc, revision: 1)
        let moscowSnapshot = fixtureSnapshot(query: moscow, revision: 1)
        await source.yield(utcSnapshot, connection: 1)
        await source.yield(moscowSnapshot, connection: 2)
        try await eventually { await utcRecorder.values == [utcSnapshot] }
        try await eventually { await moscowRecorder.values == [moscowSnapshot] }

        utcConsumer.cancel()
        await utcConsumer.value
        try await eventually { await source.terminations == 1 }

        let moscowUpdate = fixtureSnapshot(query: moscow, revision: 2)
        await source.yield(moscowUpdate, connection: 2)
        try await eventually { await moscowRecorder.values == [moscowSnapshot, moscowUpdate] }

        let reopenedUTCRecorder = SnapshotRecorder()
        let reopenedUTC = consume(await runtime.snapshots(query: utc), into: reopenedUTCRecorder)
        try await eventually { await source.snapshotsCalls == 3 }
        let reopenedUTCSnapshot = fixtureSnapshot(query: utc, revision: 2)
        await source.yield(reopenedUTCSnapshot, connection: 3)
        try await eventually { await reopenedUTCRecorder.values == [reopenedUTCSnapshot] }

        moscowConsumer.cancel()
        reopenedUTC.cancel()
        await moscowConsumer.value
        await reopenedUTC.value
        try await eventually { await source.terminations == 3 }
    }

    func testUnderlyingErrorPropagatesToEverySubscriberWithoutImporting() async throws {
        let source = StubSharedRuntime()
        let runtime = SharedReportRuntime(runtime: source)
        let query = try UsageQuery()
        let firstRecorder = SnapshotRecorder()
        let secondRecorder = SnapshotRecorder()
        let first = consume(await runtime.snapshots(query: query), into: firstRecorder)
        let second = consume(await runtime.snapshots(query: query), into: secondRecorder)
        try await eventually { await source.snapshotsCalls == 1 }

        await source.fail(SharedRuntimeFixtureError.disconnected, connection: 1)
        await first.value
        await second.value

        let firstError = await firstRecorder.errorDescription
        let secondError = await secondRecorder.errorDescription
        XCTAssertEqual(firstError, "Fixture stream disconnected")
        XCTAssertEqual(secondError, "Fixture stream disconnected")
        let calls = await source.calls
        XCTAssertEqual(calls.imports, 0)
        XCTAssertEqual(calls.snapshotReads, 0)
        XCTAssertEqual(calls.snapshotStreams, 1)
    }

    private func consume(
        _ stream: AsyncThrowingStream<UsageSnapshot, Error>,
        into recorder: SnapshotRecorder
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await value in stream { await recorder.append(value) }
            } catch {
                await recorder.record(error)
            }
        }
    }

    private func fixtureSnapshot(query: UsageQuery, revision: Int64) -> UsageSnapshot {
        UsageSnapshot(
            query: query,
            watermark: QueryWatermark(databaseID: "fixture", revision: revision, committedAt: Date()),
            report: UsageReport(
                totals: UsageTotals(requests: revision, inputTokens: revision * 10),
                sessions: [],
                diagnostics: [:]
            )
        )
    }

    private func eventually(
        timeout: Duration = .seconds(1),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else { throw SharedRuntimeFixtureError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor SnapshotRecorder {
    private(set) var values: [UsageSnapshot] = []
    private(set) var errorDescription: String?

    func append(_ value: UsageSnapshot) { values.append(value) }
    func record(_ error: Error) { errorDescription = error.localizedDescription }
}

private actor StubSharedRuntime: SessionExplorerRuntime {
    struct Calls: Equatable, Sendable {
        var imports = 0
        var snapshotReads = 0
        var snapshotStreams = 0
    }

    private var continuations: [Int: AsyncThrowingStream<UsageSnapshot, Error>.Continuation] = [:]
    private(set) var calls = Calls()
    private(set) var terminations = 0

    var snapshotsCalls: Int { calls.snapshotStreams }

    func importDirectory(_ directory: URL) async throws -> ImportSummary {
        calls.imports += 1
        return ImportSummary(files: 0, records: 0, diagnostics: [:])
    }

    func snapshot(query: UsageQuery) async throws -> UsageSnapshot {
        calls.snapshotReads += 1
        return UsageSnapshot(
            query: query,
            watermark: QueryWatermark(databaseID: "stub", revision: 0, committedAt: nil),
            report: UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:])
        )
    }

    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline {
        RequestTimeline(sessionID: sessionID, query: query, points: [])
    }

    func snapshots(query: UsageQuery) async -> AsyncThrowingStream<UsageSnapshot, Error> {
        calls.snapshotStreams += 1
        let connection = calls.snapshotStreams
        let (stream, continuation) = AsyncThrowingStream<UsageSnapshot, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuations[connection] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.terminated(connection) }
        }
        return stream
    }

    func yield(_ snapshot: UsageSnapshot, connection: Int) {
        continuations[connection]?.yield(snapshot)
    }

    func fail(_ error: Error, connection: Int) {
        continuations[connection]?.finish(throwing: error)
    }

    private func terminated(_ connection: Int) {
        guard continuations.removeValue(forKey: connection) != nil else { return }
        terminations += 1
    }
}

private enum SharedRuntimeFixtureError: Error, LocalizedError {
    case disconnected
    case timeout

    var errorDescription: String? {
        switch self {
        case .disconnected: "Fixture stream disconnected"
        case .timeout: "Timed out waiting for fixture state"
        }
    }
}
