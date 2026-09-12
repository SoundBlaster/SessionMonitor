import Combine
import Foundation
import MonitorCore
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

private actor StubExplorerRuntime: SessionExplorerRuntime {
    private var storedReport: UsageReport
    private var importFailure = false
    private var reportFailure = false

    init(report: UsageReport) {
        storedReport = report
    }

    func replaceReport(_ report: UsageReport) { storedReport = report }
    func failImports() { importFailure = true }
    func failReports(_ value: Bool) { reportFailure = value }

    func importDirectory(_ directory: URL) throws -> ImportSummary {
        if importFailure { throw StubFailure.importFailed }
        return ImportSummary(files: 1, records: 1, diagnostics: [:])
    }

    func report(since: Date?, until: Date?) throws -> UsageReport {
        if reportFailure { throw StubFailure.reportFailed }
        return storedReport
    }

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
