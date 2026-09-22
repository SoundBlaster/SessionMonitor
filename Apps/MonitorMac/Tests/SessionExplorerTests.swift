import Combine
import Foundation
import MonitorCore
import MonitorRuntime
import XCTest
@testable import SessionMonitor

@MainActor
final class SessionExplorerTests: XCTestCase {
    func testNavigationPreservesVisibleSelectionAndClearsStaleSelection() {
        let first = session("first", model: "model-a")
        let second = session("second", model: "model-b")
        var navigation = SessionNavigationState()

        navigation.reconcile(with: [first, second])
        XCTAssertEqual(navigation.selectedSessionID, first.id)
        navigation.select(second.id, among: [first, second])
        navigation.reconcile(with: [first, second])
        XCTAssertEqual(navigation.selectedSessionID, second.id)
        navigation.reconcile(with: [first])
        XCTAssertEqual(navigation.selectedSessionID, first.id)
        navigation.reconcile(with: [])
        XCTAssertNil(navigation.selectedSessionID)
    }

    func testFilteringSynchronizesSelectionAndSpecificationSnapshot() async {
        let first = session("first", model: "model-a")
        let second = session("second", model: "model-b")
        let runtime = StubExplorerRuntime(report: report([first, second]))
        let model = SessionExplorerModel { runtime }
        await model.loadIfNeeded()
        model.selectSession(second.id)

        model.setFilter("model-b")
        XCTAssertEqual(model.selectedSession?.id, second.id)
        model.setFilter("model-a")
        XCTAssertEqual(model.selectedSession?.id, first.id)
        XCTAssertEqual(model.contextProvider.currentContext().selectedSessionID, first.id)
        model.setFilter("missing")
        XCTAssertNil(model.selectedSession)
        XCTAssertNil(model.contextProvider.currentContext().selectedSessionID)
        model.setFilter("")
        XCTAssertEqual(model.selectedSession?.id, first.id)
    }

    func testWindowsKeepNavigationAndProvidersIndependent() async {
        let first = session("first", model: "model-a")
        let second = session("second", model: "model-b")
        let runtime = StubExplorerRuntime(report: report([first, second]))
        let left = SessionExplorerModel { runtime }
        let right = SessionExplorerModel { runtime }
        await left.loadIfNeeded()
        await right.loadIfNeeded()

        left.selectSession(second.id)
        left.setFilter("model-b")
        left.navigation.showsInspector = true

        XCTAssertFalse(left.contextProvider === right.contextProvider)
        XCTAssertEqual(left.selectedSession?.id, second.id)
        XCTAssertEqual(right.selectedSession?.id, first.id)
        XCTAssertEqual(right.filter, "")
        XCTAssertFalse(right.navigation.showsInspector)
        XCTAssertEqual(right.contextProvider.currentContext().selectedSessionID, first.id)
    }

    func testRefreshPublishesNewSnapshotBeforeSignallingAndReevaluatesCoverage() async {
        let incomplete = session("one", model: "model-a", unknownCacheRequests: 1)
        let runtime = StubExplorerRuntime(report: report([incomplete]))
        let model = SessionExplorerModel { runtime }
        await model.loadIfNeeded()
        let specification = DisplayedCacheCoverageSpec()
        XCTAssertFalse(specification.isSatisfiedBy(model.contextProvider.currentContext()))

        let provider = model.contextProvider
        var observed: [SessionReportSnapshot] = []
        let subscription = provider.contextUpdates.sink {
            observed.append(provider.currentContext())
        }
        let complete = session("one", model: "model-a")
        await runtime.replaceReport(report([complete]))
        await model.refresh()

        XCTAssertEqual(observed.count, 1)
        XCTAssertEqual(observed.last?.displayedTotals.unknownCacheRequests, 0)
        XCTAssertTrue(specification.isSatisfiedBy(provider.currentContext()))
        XCTAssertEqual(model.selectedSession?.id, complete.id)
        withExtendedLifetime(subscription) {}
    }

    func testImportFailureReturnsToIdleAndPreservesPreviousReport() async {
        let original = report([session("one", model: "model-a")])
        let runtime = StubExplorerRuntime(report: original)
        let model = SessionExplorerModel { runtime }
        await model.loadIfNeeded()
        await runtime.failImports()

        await model.importDirectory(URL(fileURLWithPath: "/tmp/session-monitor-test"))

        XCTAssertEqual(model.activity, .idle)
        XCTAssertEqual(model.report, original)
        XCTAssertTrue(model.errorMessage?.contains("Fixture import failure") == true)
        XCTAssertNil(model.importSummary)
        XCTAssertNil(model.importedDirectory)
    }

    func testInitialFailureCanBeRetried() async {
        let runtime = StubExplorerRuntime(report: report([session("one", model: "model-a")]))
        await runtime.failReports(true)
        let model = SessionExplorerModel { runtime }
        await model.loadIfNeeded()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isBusy)

        await runtime.failReports(false)
        await model.refresh()

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.report.sessions.count, 1)
    }

    func testQueryChangeAtSameWatermarkReplacesReportAndRejectsLateOldQuery() async throws {
        let original = report([session("all", model: "model-a")])
        let runtime = StubExplorerRuntime(report: original)
        let model = SessionExplorerModel { runtime }
        let allTime = try UsageQuery()
        await model.loadIfNeeded(query: allTime)
        let observation = Task { await model.observe(query: allTime) }
        defer { observation.cancel() }
        for _ in 0..<100 where await runtime.observerCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        let period = try UsageQuery(
            since: Date(timeIntervalSince1970: 100),
            until: Date(timeIntervalSince1970: 200),
            timeZoneIdentifier: "Europe/Moscow"
        )
        let selected = report([session("period", model: "model-b")])
        await runtime.replaceReportWithoutAdvancingWatermark(selected)
        await model.loadIfNeeded(query: period)

        XCTAssertEqual(model.query, period)
        XCTAssertEqual(model.snapshot?.query, period)
        XCTAssertEqual(model.report, selected)
        XCTAssertEqual(model.selectedSession?.id, "period")

        await runtime.yield(report([session("stale", model: "model-c")]), query: allTime, revision: 10)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(model.query, period)
        XCTAssertEqual(model.report, selected)
    }

    func testObservedWritesUpdateReportPreserveFilterAndPublishCoverage() async throws {
        let runtime = StubExplorerRuntime(report: report([session("one", model: "model-a")]))
        let model = SessionExplorerModel { runtime }
        await model.loadIfNeeded()
        model.setFilter("model-a")
        let observation = Task { await model.observe() }
        defer { observation.cancel() }
        for _ in 0..<100 where await runtime.observerCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let count = await runtime.observerCount
        XCTAssertEqual(count, 1)
        await runtime.replaceReport(report([session("one", model: "model-a", unknownCacheRequests: 1)]))
        for _ in 0..<100 where model.report.totals.unknownCacheRequests == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.filter, "model-a")
        XCTAssertEqual(model.selectedSession?.id, "one")
        XCTAssertEqual(model.snapshot?.coverage.cache, .partial)
        XCTAssertEqual(model.contextProvider.currentContext().displayedTotals.unknownCacheRequests, 1)
        observation.cancel()
        await observation.value
    }

    func testSelectedSessionTimelineUsesTheSameQueryAndSelection() async throws {
        let first = session("first", model: "model-a")
        let second = session("second", model: "model-b")
        let runtime = StubExplorerRuntime(report: report([first, second]))
        let model = SessionExplorerModel { runtime }
        let query = try UsageQuery(since: Date(timeIntervalSince1970: 100),
                                   until: Date(timeIntervalSince1970: 200),
                                   timeZoneIdentifier: "Europe/Moscow")
        await model.loadIfNeeded(query: query)
        model.selectSession(second.id)
        await model.loadTimeline(sessionID: second.id)

        XCTAssertEqual(model.selectedSession?.id, second.id)
        XCTAssertEqual(model.timelineModel.timeline?.sessionID, second.id)
        XCTAssertEqual(model.timelineModel.timeline?.query, query)

        model.selectSession(first.id)
        XCTAssertEqual(model.selectedSession?.id, first.id)
        XCTAssertNil(model.timelineModel.timeline)
    }

    func testQuotaPresentationUsesCurrentQuery() async throws {
        let runtime = StubExplorerRuntime(report: report([session("one", model: "model-a")]))
        let model = SessionExplorerModel { runtime }
        let query = try UsageQuery(
            since: Date(timeIntervalSince1970: 100),
            until: Date(timeIntervalSince1970: 200),
            timeZoneIdentifier: "Europe/Moscow"
        )

        await model.loadIfNeeded(query: query)
        let generatedAt = Date(timeIntervalSince1970: 300)
        await model.loadQuotaPresentation(generatedAt: generatedAt)

        XCTAssertEqual(model.quotaPresentationReport?.query, query)
        XCTAssertEqual(model.quotaPresentationReport?.generatedAt, generatedAt)
    }

    func testGUIObservesExternalProcessCommit() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appending(path: "usage.sqlite")
        let runtime = try MonitorRuntime.SessionMonitor(databaseURL: database)
        let model = SessionExplorerModel { runtime }
        await model.loadIfNeeded()
        let observation = Task { await model.observe() }
        defer { observation.cancel() }
        // A separate SQLite process publishes diagnostics and the marker in the same transaction.
        // The CLI process harness separately verifies that production imports publish this marker.
        let writer = Process()
        writer.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        writer.arguments = ["-c", """
            import sqlite3, sys, time
            with sqlite3.connect(sys.argv[1]) as db:
                db.execute("INSERT INTO source_diagnostics VALUES ('fixture', 'partialTails', 1)")
                db.execute("UPDATE query_watermark SET revision = revision + 1, committed_at = ?", (time.time(),))
            """, database.path]
        try writer.run()
        writer.waitUntilExit()
        XCTAssertEqual(writer.terminationStatus, 0)
        for _ in 0..<200 where model.report.diagnostics["partialTails"] != 1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.report.diagnostics["partialTails"], 1)
        XCTAssertEqual(model.snapshot?.watermark.revision, 1)
        observation.cancel()
        await observation.value
    }

    private func session(_ id: String, model: String, unknownCacheRequests: Int64 = 0) -> SessionSummary {
        SessionSummary(id: id, model: model, totals: UsageTotals(
            requests: 1, inputTokens: 100, cachedInputTokens: 60,
            outputTokens: 20, unknownCacheRequests: unknownCacheRequests
        ))
    }

    private func report(_ sessions: [SessionSummary]) -> UsageReport {
        let totals = sessions.reduce(into: UsageTotals()) { result, session in
            result.requests += session.totals.requests
            result.inputTokens += session.totals.inputTokens
            result.cachedInputTokens += session.totals.cachedInputTokens
            result.outputTokens += session.totals.outputTokens
            result.unknownCacheRequests += session.totals.unknownCacheRequests
        }
        return UsageReport(totals: totals, sessions: sessions, diagnostics: [:])
    }
}

actor StubExplorerRuntime: SessionExplorerRuntime {
    private struct Observer {
        let query: UsageQuery
        let continuation: AsyncThrowingStream<UsageSnapshot, Error>.Continuation
    }

    private var storedReport: UsageReport
    private var importFailure = false
    private var reportFailure = false
    private var revision: Int64 = 0
    private var observers: [UUID: Observer] = [:]
    var observerCount: Int { observers.count }

    init(report: UsageReport) {
        storedReport = report
    }

    func replaceReport(_ report: UsageReport) {
        storedReport = report
        revision += 1
        for observer in observers.values {
            if let value = try? snapshot(query: observer.query) {
                observer.continuation.yield(value)
            }
        }
    }
    func replaceReportWithoutAdvancingWatermark(_ report: UsageReport) { storedReport = report }
    func yield(_ report: UsageReport, query: UsageQuery, revision: Int64) {
        let value = UsageSnapshot(
            query: query,
            watermark: QueryWatermark(databaseID: "fixture", revision: revision, committedAt: Date()),
            report: report
        )
        for observer in observers.values { observer.continuation.yield(value) }
    }
    func failImports() { importFailure = true }
    func failReports(_ value: Bool) { reportFailure = value }

    func importDirectory(_ directory: URL) throws -> ImportSummary {
        if importFailure { throw StubFailure.importFailed }
        return ImportSummary(files: 1, records: 1, diagnostics: [:])
    }

    func snapshot(query: UsageQuery) throws -> UsageSnapshot {
        if reportFailure { throw StubFailure.reportFailed }
        return UsageSnapshot(query: query,
                             watermark: QueryWatermark(databaseID: "fixture", revision: revision, committedAt: Date()),
                             report: storedReport)
    }

    func timeline(sessionID: String, query: UsageQuery) throws -> RequestTimeline {
        RequestTimeline(sessionID: sessionID, query: query, points: [])
    }

    func cacheHitRateWidget(
        period: CacheHitRateWidgetPeriod, referenceDate: Date, timeZone: TimeZone
    ) -> CacheHitRateWidgetReport {
        CacheHitRateWidgetBuilder.build(
            observations: [], period: period, referenceDate: referenceDate, timeZone: timeZone
        )
    }

    func quotaPresentation(query: UsageQuery, generatedAt: Date) -> QuotaPresentationReport {
        QuotaPresentationReport(
            query: query, generatedAt: generatedAt, freshnessThresholdSeconds: 900,
            coverage: UsageLimitTelemetryCoverage(snapshots: []), windows: []
        )
    }

    func snapshots(query: UsageQuery) -> AsyncThrowingStream<UsageSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let identifier = UUID()
            do {
                continuation.yield(try snapshot(query: query))
                observers[identifier] = Observer(query: query, continuation: continuation)
                continuation.onTermination = { [weak self] _ in
                    Task { await self?.removeObserver(identifier) }
                }
            } catch { continuation.finish(throwing: error) }
        }
    }

    private func removeObserver(_ identifier: UUID) { observers[identifier] = nil }

    private enum StubFailure: LocalizedError {
        case importFailed
        case reportFailed

        var errorDescription: String? {
            switch self {
            case .importFailed: "Fixture import failure"
            case .reportFailed: "Fixture report failure"
            }
        }
    }
}
