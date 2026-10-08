import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

@MainActor
final class FindingsAlertsTests: XCTestCase {
    func testWithoutFiltersThePanelShowsExactlyWhatDoctorAndAlertsReturn() async throws {
        let source = StubFindingsSource(report: report(), records: [record("a", .active), record("b", .resolved)])
        let model = FindingsAlertsModel()
        await model.load(query: try query(), source: source)

        XCTAssertEqual(model.visibleFindings, source.report.findings)
        XCTAssertEqual(model.visibleAlerts, source.records)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.summary, "3 findings · 2 alerts")
    }

    func testKindFilterNarrowsFindingsAndKindsComeFromTheFindingIDs() async throws {
        let source = StubFindingsSource(report: report(), records: [])
        let model = FindingsAlertsModel()
        await model.load(query: try query(), source: source)

        XCTAssertEqual(model.kinds, ["missing_provenance", "repetitive_polling", "uncached_burst"])
        model.kindFilter = "repetitive_polling"
        XCTAssertEqual(model.visibleFindings.map(\.id), ["repetitive_polling|s1|r1|3"])
        XCTAssertEqual(FindingsAlertsPresentation.kindTitle("repetitive_polling"), "Repetitive polling")
    }

    func testAlertStatusFilterSplitsActiveAndResolved() async throws {
        let source = StubFindingsSource(report: report(), records: [record("a", .active), record("b", .resolved)])
        let model = FindingsAlertsModel()
        await model.load(query: try query(), source: source)

        model.alertStatusFilter = .active
        XCTAssertEqual(model.visibleAlerts.map(\.id), ["a"])
        model.alertStatusFilter = .resolved
        XCTAssertEqual(model.visibleAlerts.map(\.id), ["b"])
    }

    func testAFailedReloadKeepsTheLastListsAndNamesTheProblem() async throws {
        let source = StubFindingsSource(report: report(), records: [record("a", .active)])
        let model = FindingsAlertsModel()
        await model.load(query: try query(), source: source)

        source.fail = true
        await model.load(query: try query(), source: source)
        XCTAssertEqual(model.visibleFindings.count, 3)
        XCTAssertEqual(model.visibleAlerts.count, 1)
        XCTAssertTrue(try XCTUnwrap(model.errorMessage).hasPrefix("Could not load findings."))

        source.fail = false
        await model.load(query: try query(), source: source)
        XCTAssertNil(model.errorMessage)
    }

    func testAKindFilterThatDisappearsAfterReloadIsDropped() async throws {
        let source = StubFindingsSource(report: report(), records: [])
        let model = FindingsAlertsModel()
        await model.load(query: try query(), source: source)
        model.kindFilter = "uncached_burst"

        source.report = DiagnosticReport(query: try query(), findings: [])
        await model.load(query: try query(), source: source)
        XCTAssertNil(model.kindFilter)
        XCTAssertTrue(model.visibleFindings.isEmpty)
    }

    func testCoverageIsNamedOnlyWhenNotFullyObserved() {
        XCTAssertNil(FindingsAlertsPresentation.coverageText(nil))
        XCTAssertNil(FindingsAlertsPresentation.coverageText(.observed))
        XCTAssertEqual(FindingsAlertsPresentation.coverageText(.partial(reason: "no cache")),
                       "Partial coverage: no cache")
        XCTAssertEqual(FindingsAlertsPresentation.coverageText(.unknown(reason: "no input")),
                       "Unknown coverage: no input")
    }

    private func query() throws -> UsageQuery { try UsageQuery() }

    private func report() -> DiagnosticReport {
        let query = (try? UsageQuery()) ?? { preconditionFailure("default query") }()
        return DiagnosticReport(query: query, findings: [
            finding("repetitive_polling|s1|r1|3"), finding("uncached_burst|s2||"), finding("missing_provenance")
        ])
    }

    private func finding(_ id: String) -> DiagnosticFinding {
        DiagnosticFinding(
            id: id, severity: .warning, title: "Title \(id)", explanation: "Because \(id)",
            evidence: DiagnosticEvidence(observed: [DiagnosticEvidenceItem(source: "fixture", detail: "seen")]),
            confidence: .medium, affectedSessions: ["s1"], suggestedNextAction: "Look"
        )
    }

    private func record(_ key: String, _ status: AlertStatus) -> AlertRecord {
        let candidate = AlertCandidate(
            key: key, scope: AlertScope("scope:\(key)"), source: .anomaly, kind: "uncached_burst",
            severity: .warning, title: "Alert \(key)", message: "Message"
        )
        let moment = Date(timeIntervalSince1970: 1_790_000_000)
        return AlertRecord(candidate: candidate, status: status, firstSeenAt: moment, raisedAt: moment,
                           lastSeenAt: moment, resolvedAt: status == .resolved ? moment : nil)
    }
}

private final class StubFindingsSource: FindingsAlertsSource, @unchecked Sendable {
    var report: DiagnosticReport
    var records: [AlertRecord]
    var fail = false

    init(report: DiagnosticReport, records: [AlertRecord]) {
        self.report = report
        self.records = records
    }

    func diagnosticReport(query: UsageQuery) async throws -> DiagnosticReport {
        if fail { throw FindingsAlertsError.unsupportedRuntime }
        return report
    }

    func alertRecords(status: AlertStatus?) async throws -> [AlertRecord] {
        if fail { throw FindingsAlertsError.unsupportedRuntime }
        return records.filter { status == nil || $0.status == status }
    }
}
