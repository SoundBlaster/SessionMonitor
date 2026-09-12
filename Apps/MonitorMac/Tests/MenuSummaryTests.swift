import AppKit
import Foundation
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class MenuSummaryTests: XCTestCase {
    func testRefreshUpdatesSnapshotAndFailurePreservesPreviousValue() async throws {
        let source = SnapshotStreamStub()
        let model = MenuSummaryModel { await source.makeStream() }
        let value = try snapshot(databaseID: "refresh", revision: 4, inputTokens: 40)
        await model.refresh { value }
        XCTAssertEqual(model.snapshot, value)
        XCTAssertFalse(model.isRefreshing)
        await model.refresh { throw FixtureError.disconnected }
        XCTAssertEqual(model.snapshot, value)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isRefreshing)
        let subscriptions = await source.callCount
        XCTAssertEqual(subscriptions, 0)
    }

    func testSummaryRendersEmptyPartialAndCompleteCoverage() async throws {
        for state in ["empty", "partial", "complete"] {
            let source = SnapshotStreamStub()
            let model = MenuSummaryModel { await source.makeStream() }
            let observation = Task { await model.observe() }
            defer { observation.cancel() }
            try await eventually { await source.callCount == 1 }
            let totals = state == "empty" ? UsageTotals() : UsageTotals(
                requests: 2, inputTokens: 2_469_135_780, cachedInputTokens: 1_000_000_000,
                outputTokens: 46_913_578, unknownCacheRequests: state == "partial" ? 1 : 0
            )
            await source.yield(UsageSnapshot(
                query: try UsageQuery(),
                watermark: QueryWatermark(databaseID: "render", revision: 1, committedAt: nil),
                report: UsageReport(totals: totals, sessions: [], diagnostics: [:])
            ))
            try await eventually { model.snapshot != nil }
            let noop: () -> Void = {}
            let actions = MenuSummaryActions(openWindow: noop, refresh: noop, startWatch: noop,
                                             togglePause: noop, stopWatch: noop, openSettings: noop, quit: noop)
            let watch = MenuWatchPresentation(title: state == "empty" ? "Watch not started" : "Watching",
                                              symbol: "folder", isRunning: state != "empty")
            let renderer = ImageRenderer(content: MenuSummaryPage(model: model, watch: watch, actions: actions)
                .background(.white).environment(\.colorScheme, .light))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, 340)
            XCTAssertGreaterThan(image.size.height, 100)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let url = FileManager.default.temporaryDirectory.appending(path: "sm201-menu-\(state).png")
            try png.write(to: url)
            print("Menu render: \(url.path)")
            observation.cancel()
            await observation.value
        }
    }

    func testObservationAcceptsNewGenerationsAndIgnoresStaleRevision() async throws {
        let source = SnapshotStreamStub()
        let model = MenuSummaryModel { await source.makeStream() }
        let observation = Task { await model.observe() }
        defer { observation.cancel() }
        try await eventually { await source.callCount == 1 }

        await source.yield(try snapshot(databaseID: "first", revision: 3, inputTokens: 30))
        try await eventually { model.snapshot?.report.totals.inputTokens == 30 }

        await source.yield(try snapshot(databaseID: "first", revision: 2, inputTokens: 20))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.snapshot?.watermark.revision, 3)
        XCTAssertEqual(model.snapshot?.report.totals.inputTokens, 30)

        await source.yield(try snapshot(databaseID: "first", revision: 4, inputTokens: 40))
        try await eventually { model.snapshot?.watermark.revision == 4 }

        await source.yield(try snapshot(databaseID: "replacement", revision: 1, inputTokens: 10))
        try await eventually { model.snapshot?.watermark.databaseID == "replacement" }
        XCTAssertEqual(model.snapshot?.watermark.revision, 1)
        XCTAssertEqual(model.snapshot?.report.totals.inputTokens, 10)
    }

    func testConcurrentObserveUsesOneStreamFactory() async throws {
        let source = SnapshotStreamStub()
        let model = MenuSummaryModel { await source.makeStream() }
        let first = Task { await model.observe() }
        defer { first.cancel() }
        try await eventually {
            let callCount = await source.callCount
            return model.isObserving && callCount == 1
        }

        await model.observe()

        XCTAssertTrue(model.isObserving)
        let callCount = await source.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testCancellationAllowsReopeningWithANewStream() async throws {
        let source = SnapshotStreamStub()
        let model = MenuSummaryModel { await source.makeStream() }
        let first = Task { await model.observe() }
        try await eventually {
            let callCount = await source.callCount
            return model.isObserving && callCount == 1
        }

        first.cancel()
        await first.value
        XCTAssertFalse(model.isObserving)
        XCTAssertNil(model.errorMessage)

        let reopened = Task { await model.observe() }
        defer { reopened.cancel() }
        try await eventually {
            let callCount = await source.callCount
            return model.isObserving && callCount == 2
        }
        await source.yield(try snapshot(databaseID: "reopened", revision: 1, inputTokens: 12), connection: 2)
        try await eventually { model.snapshot?.watermark.databaseID == "reopened" }
    }

    func testStreamErrorPreservesLastSnapshot() async throws {
        let source = SnapshotStreamStub()
        let model = MenuSummaryModel { await source.makeStream() }
        let observation = Task { await model.observe() }
        try await eventually { await source.callCount == 1 }
        let last = try snapshot(databaseID: "fixture", revision: 7, inputTokens: 70)
        await source.yield(last)
        try await eventually { model.snapshot == last }

        await source.fail(FixtureError.disconnected)
        await observation.value

        XCTAssertEqual(model.snapshot, last)
        XCTAssertFalse(model.isObserving)
        XCTAssertEqual(model.errorMessage, "Could not read the index. Fixture stream disconnected")
    }

    private func snapshot(databaseID: String, revision: Int64, inputTokens: Int64) throws -> UsageSnapshot {
        UsageSnapshot(
            query: try UsageQuery(),
            watermark: QueryWatermark(
                databaseID: databaseID,
                revision: revision,
                committedAt: Date(timeIntervalSince1970: TimeInterval(revision + 1))
            ),
            report: UsageReport(
                totals: UsageTotals(requests: 1, inputTokens: inputTokens),
                sessions: [],
                diagnostics: [:]
            )
        )
    }

    private func eventually(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else { throw FixtureError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor SnapshotStreamStub {
    private var continuations: [Int: AsyncThrowingStream<UsageSnapshot, Error>.Continuation] = [:]
    private(set) var callCount = 0

    func makeStream() -> AsyncThrowingStream<UsageSnapshot, Error> {
        callCount += 1
        let connection = callCount
        let (stream, continuation) = AsyncThrowingStream<UsageSnapshot, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuations[connection] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(connection) }
        }
        return stream
    }

    func yield(_ snapshot: UsageSnapshot, connection: Int? = nil) {
        continuation(connection)?.yield(snapshot)
    }

    func fail(_ error: Error, connection: Int? = nil) {
        continuation(connection)?.finish(throwing: error)
    }

    private func continuation(
        _ connection: Int?
    ) -> AsyncThrowingStream<UsageSnapshot, Error>.Continuation? {
        continuations[connection ?? callCount]
    }

    private func remove(_ connection: Int) {
        continuations[connection] = nil
    }
}

private enum FixtureError: Error, LocalizedError {
    case disconnected
    case timeout

    var errorDescription: String? {
        switch self {
        case .disconnected: "Fixture stream disconnected"
        case .timeout: "Timed out waiting for fixture state"
        }
    }
}
