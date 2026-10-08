import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

final class SessionSortOrderTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testEveryKeyHasBothDirectionsAndSurvivesStorage() {
        XCTAssertEqual(SessionSortOrder.all.count, SessionSortKey.allCases.count * 2)
        for order in SessionSortOrder.all {
            XCTAssertEqual(SessionSortOrder(rawValue: order.rawValue), order)
        }
        XCTAssertNil(SessionSortOrder(rawValue: "nonsense"))
        XCTAssertNil(SessionSortOrder(rawValue: "tokens.sideways"))
        XCTAssertEqual(SessionSortOrder.default, SessionSortOrder(key: .tokens, direction: .descending))
        XCTAssertEqual(SessionSortOrder(key: .lastRequest, direction: .descending).title,
                       "Last request · newest first")
    }

    func testDatesSortBothWaysAndUnknownDatesStayLast() {
        let sessions = [
            session("old", first: 100, last: 400), session("new", first: 300, last: 200),
            session("none", first: nil, last: nil)
        ]
        XCTAssertEqual(ids(.firstRequest, .ascending, sessions), ["old", "new", "none"])
        XCTAssertEqual(ids(.firstRequest, .descending, sessions), ["new", "old", "none"])
        XCTAssertEqual(ids(.lastRequest, .descending, sessions), ["old", "new", "none"])
        XCTAssertEqual(ids(.lastRequest, .ascending, sessions), ["new", "old", "none"])
    }

    func testCacheHitSortsBothWaysAndUnknownCoverageIsNotZero() {
        let sessions = [
            session("high", totals: totals(input: 100, cached: 90)),
            session("low", totals: totals(input: 100, cached: 10)),
            session("partial", totals: totals(input: 100, cached: 0, unknown: 1)),
            session("zero", totals: totals(input: 100, cached: 0))
        ]
        XCTAssertEqual(ids(.cacheHit, .descending, sessions), ["high", "low", "zero", "partial"])
        XCTAssertEqual(ids(.cacheHit, .ascending, sessions), ["zero", "low", "high", "partial"])
    }

    func testRequestsAndTokensSortBothWaysByInputPlusOutput() {
        let sessions = [
            session("few", totals: totals(requests: 2, input: 900, output: 100)),
            session("many", totals: totals(requests: 9, input: 100, output: 50)),
            session("big", totals: totals(requests: 5, input: 500, output: 700))
        ]
        XCTAssertEqual(ids(.requests, .descending, sessions), ["many", "big", "few"])
        XCTAssertEqual(ids(.requests, .ascending, sessions), ["few", "big", "many"])
        XCTAssertEqual(ids(.tokens, .descending, sessions), ["big", "few", "many"])
        XCTAssertEqual(ids(.tokens, .ascending, sessions), ["many", "few", "big"])
    }

    func testTiesKeepAStableOrderByID() {
        let sessions = [session("b", totals: totals(requests: 3)), session("a", totals: totals(requests: 3))]
        XCTAssertEqual(ids(.requests, .descending, sessions), ["a", "b"])
        XCTAssertEqual(ids(.requests, .ascending, sessions), ["a", "b"])
    }

    func testChildrenAreSortedInsideTheirParentAndTheTreeIsKept() {
        let child1 = SessionTreeNode(session: session("c1", totals: totals(requests: 1)), state: .attached)
        let child2 = SessionTreeNode(session: session("c2", totals: totals(requests: 8)), state: .attached)
        let root = SessionTreeNode(session: session("r", totals: totals(requests: 4)), state: .knownRoot,
                                   children: [child1, child2])
        let sorted = SessionSortOrder(key: .requests, direction: .descending).sorted([root])
        XCTAssertEqual(sorted.map(\.id), ["r"])
        XCTAssertEqual(sorted[0].children.map(\.id), ["c2", "c1"])
        XCTAssertEqual(sorted[0].state, .knownRoot)
    }

    func testRowDetailNamesTheSortedValueOnlyWhenTheRowDoesNotShowIt() throws {
        let item = session("x", first: 1_790_000_000, last: nil, totals: totals(input: 1_200, output: 300))
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let detail = { (key: SessionSortKey) in
            SessionSortOrder(key: key, direction: .descending).detail(for: item, timeZone: utc, locale: self.english)
        }
        XCTAssertTrue(try XCTUnwrap(detail(.firstRequest)).hasPrefix("First request: "))
        XCTAssertEqual(detail(.lastRequest), "Last request: unknown")
        XCTAssertEqual(detail(.tokens), "Tokens: 1,500")
        XCTAssertNil(detail(.cacheHit))
        XCTAssertNil(detail(.requests))
    }

    private func ids(
        _ key: SessionSortKey, _ direction: SessionSortOrder.Direction, _ sessions: [SessionSummary]
    ) -> [String] {
        SessionSortOrder(key: key, direction: direction)
            .sorted(sessions.map { SessionTreeNode(session: $0, state: .knownRoot) }).map(\.id)
    }

    private func totals(
        requests: Int64 = 1, input: Int64 = 0, cached: Int64 = 0, output: Int64 = 0, unknown: Int64 = 0
    ) -> UsageTotals {
        UsageTotals(requests: requests, inputTokens: input, cachedInputTokens: cached,
                    outputTokens: output, unknownCacheRequests: unknown)
    }

    private func session(
        _ id: String, first: TimeInterval? = nil, last: TimeInterval? = nil, totals: UsageTotals = UsageTotals()
    ) -> SessionSummary {
        SessionSummary(id: id, model: "m", totals: totals,
                       firstRequestAt: first.map { Date(timeIntervalSince1970: $0) },
                       lastRequestAt: last.map { Date(timeIntervalSince1970: $0) })
    }
}
