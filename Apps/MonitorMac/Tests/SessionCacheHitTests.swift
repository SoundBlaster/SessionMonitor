import Foundation
import MonitorCore
import MonitorRuntime
import XCTest
@testable import SessionMonitor

@MainActor
final class SessionCacheHitTests: XCTestCase {
    func testPresentationUsesTotalsForZeroFiftyAndFullHit() {
        for (cachedInputTokens, expectedRatio) in [(Int64(0), 0.0), (Int64(50), 0.5), (Int64(100), 1.0)] {
            let presentation = SessionCacheHitPresentation(totals: UsageTotals(
                requests: 2, inputTokens: 100, cachedInputTokens: cachedInputTokens
            ))

            XCTAssertEqual(presentation.ratio, expectedRatio)
            XCTAssertEqual(presentation.value, expectedRatio.formatted(.percent.precision(.fractionLength(1))))
            XCTAssertTrue(presentation.explanation.contains("cached input tokens"))
        }
    }

    func testPresentationExplainsPartialUnknownAndZeroInput() {
        let partial = SessionCacheHitPresentation(totals: UsageTotals(
            requests: 2, inputTokens: 100, cachedInputTokens: 50, unknownCacheRequests: 1
        ))
        XCTAssertEqual(partial.state, .unavailable(reason: .partialCoverage(unknownRequests: 1)))
        XCTAssertNil(partial.ratio)
        XCTAssertEqual(partial.value, "—")
        XCTAssertTrue(partial.explanation.contains("partial"))
        XCTAssertTrue(partial.explanation.contains("unknown"))

        let zeroInput = SessionCacheHitPresentation(totals: UsageTotals(
            requests: 1, inputTokens: 0, cachedInputTokens: 0
        ))
        XCTAssertEqual(zeroInput.state, .unavailable(reason: .zeroInput))
        XCTAssertNil(zeroInput.ratio)
        XCTAssertEqual(zeroInput.value, "—")
        XCTAssertTrue(zeroInput.explanation.contains("input tokens are zero"))
    }

    func testPeriodChangeReplacesSidebarCacheHitForSameSessionIdentity() async throws {
        let allTimeSession = session("same", model: "model-a", inputTokens: 100, cachedInputTokens: 0)
        let runtime = StubExplorerRuntime(report: report([allTimeSession]))
        let model = makeModel(runtime)
        await model.loadIfNeeded()
        let initialSession = try XCTUnwrap(model.selectedSession)
        XCTAssertEqual(SessionCacheHitPresentation(totals: initialSession.totals).ratio, 0)

        let period = try UsageQuery(
            since: Date(timeIntervalSince1970: 100), until: Date(timeIntervalSince1970: 200),
            timeZoneIdentifier: "Europe/Moscow"
        )
        let periodSession = session("same", model: "model-a", inputTokens: 100, cachedInputTokens: 100)
        await runtime.replaceReportWithoutAdvancingWatermark(report([periodSession]))
        await model.loadIfNeeded(query: period)
        let updatedSession = try XCTUnwrap(model.selectedSession)

        XCTAssertEqual(model.query, period)
        XCTAssertEqual(updatedSession.id, "same")
        XCTAssertEqual(SessionCacheHitPresentation(totals: updatedSession.totals).ratio, 1)
    }

    func testSnapshotUpdateRefreshesSidebarCacheHitWithoutImport() async throws {
        let runtime = StubExplorerRuntime(report: report([
            session("live", model: "model-a", inputTokens: 100, cachedInputTokens: 0)
        ]))
        let model = makeModel(runtime)
        await model.loadIfNeeded()
        let observation = Task { await model.observe() }
        defer { observation.cancel() }
        for _ in 0..<100 where await runtime.observerCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        await runtime.replaceReport(report([
            session("live", model: "model-a", inputTokens: 100, cachedInputTokens: 50)
        ]))
        for _ in 0..<100 where model.selectedSession?.totals.cachedInputTokens != 50 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let updatedSession = try XCTUnwrap(model.selectedSession)

        XCTAssertEqual(SessionCacheHitPresentation(totals: updatedSession.totals).ratio, 0.5)
        XCTAssertNil(model.importSummary)
        observation.cancel()
        await observation.value
    }

    func testSidebarAndDetailUseSameSelectedSessionTotals() async throws {
        let first = session("first", model: "model-a", inputTokens: 100, cachedInputTokens: 0)
        let second = session("second", model: "model-b", inputTokens: 100, cachedInputTokens: 100)
        let runtime = StubExplorerRuntime(report: report([first, second]))
        let model = makeModel(runtime)
        await model.loadIfNeeded()
        model.selectSession(second.id)

        let sidebarPresentation = SessionCacheHitPresentation(totals: second.totals)
        let detailTotals = model.contextProvider.currentContext().displayedTotals
        let detailPresentation = SessionCacheHitPresentation(totals: detailTotals)

        XCTAssertEqual(detailTotals, second.totals)
        XCTAssertEqual(sidebarPresentation, detailPresentation)
        XCTAssertEqual(sidebarPresentation.value, "100.0%")
    }

    private func session(
        _ id: String, model: String, inputTokens: Int64, cachedInputTokens: Int64,
        unknownCacheRequests: Int64 = 0
    ) -> SessionSummary {
        SessionSummary(id: id, model: model, totals: UsageTotals(
            requests: 1, inputTokens: inputTokens, cachedInputTokens: cachedInputTokens,
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
    private func makeModel(_ runtime: StubExplorerRuntime) -> SessionExplorerModel {
        let suiteName = "SessionCacheHitTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return SessionExplorerModel(runtimeFactory: { runtime })
        }
        return SessionExplorerModel(
            runtimeFactory: { runtime },
            importedDirectorySettings: ImportedDirectorySettings(defaults: defaults)
        )
    }

}
