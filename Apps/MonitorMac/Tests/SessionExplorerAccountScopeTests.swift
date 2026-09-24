import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

@MainActor
final class SessionExplorerAccountScopeTests: XCTestCase {
    func testTimelineLoadIdentityChangesWhenAccountScopeChanges() throws {
        let sessionID = "same-session"
        let personal = try UsageQuery(accountScope: UsageAccountScope(profileID: "personal"))
        let work = try UsageQuery(accountScope: UsageAccountScope(profileID: "work"))

        XCTAssertNotEqual(
            SessionTimelineLoadID(sessionID: sessionID, query: personal),
            SessionTimelineLoadID(sessionID: sessionID, query: work)
        )
    }

    func testLateQuotaResultCannotReplaceNewAccountReport() async throws {
        let report = UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:])
        let runtime = StubExplorerRuntime(report: report)
        let model = SessionExplorerModel(runtimeFactory: { runtime })
        let oldQuery = try UsageQuery(accountScope: UsageAccountScope(profileID: "personal"))
        let newQuery = try UsageQuery(accountScope: UsageAccountScope(profileID: "work"))
        await model.loadIfNeeded(query: oldQuery)
        await runtime.delayQuota(for: oldQuery)

        let oldLoad = Task { await model.loadQuotaPresentation() }
        await runtime.waitForDelayedQuotaRequest()
        await model.loadIfNeeded(query: newQuery)
        await model.loadQuotaPresentation()
        XCTAssertEqual(model.quotaPresentationReport?.query, newQuery)

        await runtime.releaseDelayedQuota()
        await oldLoad.value
        XCTAssertEqual(model.quotaPresentationReport?.query, newQuery)
    }
}
