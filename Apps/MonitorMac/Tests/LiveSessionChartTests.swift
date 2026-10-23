import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

@MainActor
final class LiveSessionChartTests: XCTestCase {
    func testSnapshotRevisionReloadsSameSelectedSessionEvenWhenCountDoesNotChange() throws {
        let empty = UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:])
        let runtime = StubExplorerRuntime(report: empty)
        let model = SessionExplorerModel(runtimeFactory: { runtime })
        let query = model.query
        func apply(_ revision: Int64, count: Int64, database: String = "one") {
            let totals = UsageTotals(requests: count, inputTokens: 100, outputTokens: 10)
            let report = UsageReport(totals: totals,
                                     sessions: [SessionSummary(id: "session", model: "model", totals: totals)],
                                     diagnostics: [:])
            model.apply(UsageSnapshot(query: query, watermark: QueryWatermark(
                databaseID: database, revision: revision, committedAt: nil
            ), report: report), expectedQuery: query)
        }
        apply(1, count: 55)
        model.selectSession("session")
        let original = try XCTUnwrap(model.timelineLoadID)
        apply(2, count: 72)
        let updated = try XCTUnwrap(model.timelineLoadID)
        XCTAssertEqual(original.sessionID, updated.sessionID)
        XCTAssertNotEqual(original, updated)
        XCTAssertEqual(model.selectedSession?.totals.requests, 72)
        apply(3, count: 72)
        XCTAssertNotEqual(updated, model.timelineLoadID)
        let corrected = model.timelineLoadID
        apply(3, count: 72, database: "replacement")
        XCTAssertNotEqual(corrected, model.timelineLoadID)
    }

    func testRefreshFrom55To72RebuildsChartWhilePreservingViewport() async throws {
        let model = RequestTimelineModel()
        let old = try timeline(count: 55)
        await model.load(sessionID: "session", query: old.query, source: LiveChartSource(value: old))
        model.zoom(by: 0.5)
        let viewport = model.customDomain
        let fresh = try timeline(count: 72)
        await model.load(sessionID: "session", query: fresh.query, source: LiveChartSource(value: fresh))
        XCTAssertEqual(model.timeline?.points.count, 72)
        XCTAssertEqual(model.pointIndex?.points.count, 72)
        XCTAssertEqual(model.customDomain, viewport)
        XCTAssertEqual(model.rangeMode, .custom)
    }

    func testLateSameSessionResponseCannotOverwriteNewerData() async throws {
        let model = RequestTimelineModel()
        let old = try timeline(count: 55)
        let source = DelayedLiveChartSource(value: old)
        let pending = Task { await model.load(sessionID: "session", query: old.query, source: source) }
        await source.waitUntilStarted()
        let fresh = try timeline(count: 72)
        await model.load(sessionID: "session", query: fresh.query, source: LiveChartSource(value: fresh))
        await source.release()
        await pending.value
        XCTAssertEqual(model.timeline?.points.count, 72)
        XCTAssertFalse(model.isLoading)
    }

    func testResetAndCancellationRejectInFlightResults() async throws {
        for cancel in [false, true] {
            let model = RequestTimelineModel()
            let value = try timeline(count: 55)
            let source = DelayedLiveChartSource(value: value)
            let pending = Task { await model.load(sessionID: "session", query: value.query, source: source) }
            await source.waitUntilStarted()
            if cancel { pending.cancel() } else { model.reset() }
            await source.release()
            await pending.value
            XCTAssertNil(model.timeline)
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(model.isLoading)
        }
    }

    private func timeline(count: Int) throws -> RequestTimeline {
        RequestTimeline(sessionID: "session", query: try UsageQuery(), points: (0..<count).map { index in
            RequestTimelinePoint(id: String(index), sessionID: "session",
                                 timestamp: Date(timeIntervalSince1970: Double(index * 60)),
                                 kind: .usageRequest, cachedInputTokens: 80, uncachedInputTokens: 20)
        })
    }
}

private struct LiveChartSource: RequestTimelineSource {
    let value: RequestTimeline
    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline { value }
}

private actor DelayedLiveChartSource: RequestTimelineSource {
    let value: RequestTimeline
    private var response: CheckedContinuation<RequestTimeline, Never>?
    private var started: CheckedContinuation<Void, Never>?
    init(value: RequestTimeline) { self.value = value }
    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline {
        await withCheckedContinuation { continuation in
            response = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() {
        response?.resume(returning: value)
        response = nil
    }
}
