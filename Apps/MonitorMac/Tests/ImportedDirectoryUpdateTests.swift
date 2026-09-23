import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

@MainActor
final class ImportedDirectoryUpdateTests: XCTestCase {
    func testUpdateReimportsPersistedDirectoryAndPublishesNewSessions() async throws {
        let suiteName = "ImportedDirectoryUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = URL(fileURLWithPath: "/tmp/codex-rollouts", isDirectory: true)
        let settings = ImportedDirectorySettings(defaults: defaults)
        let original = report([session("existing")])
        let runtime = StubExplorerRuntime(report: original)
        let firstModel = SessionExplorerModel(runtimeFactory: { runtime }, importedDirectorySettings: settings)
        await firstModel.importDirectory(directory)
        await runtime.replaceReportAfterNextImport(report([session("today"), session("existing")]))

        let reopenedModel = SessionExplorerModel(
            runtimeFactory: { runtime }, importedDirectorySettings: ImportedDirectorySettings(defaults: defaults)
        )
        await reopenedModel.loadIfNeeded()
        XCTAssertEqual(reopenedModel.importedDirectory, directory)

        await reopenedModel.update()

        let importedDirectories = await runtime.importedDirectories
        XCTAssertEqual(importedDirectories, [directory, directory])
        XCTAssertEqual(Set(reopenedModel.report.sessions.map(\.id)), ["existing", "today"])
        XCTAssertEqual(reopenedModel.importSummary?.files, 1)
    }

    func testUpdateWithoutImportSourceReadsStoredSnapshot() async {
        let runtime = StubExplorerRuntime(report: report([session("stored")]))
        let model = SessionExplorerModel(runtimeFactory: { runtime })

        await model.update()

        let importedDirectories = await runtime.importedDirectories
        XCTAssertTrue(importedDirectories.isEmpty)
        XCTAssertEqual(model.selectedSession?.id, "stored")
    }

    func testUpdateImportFailurePreservesStoredReportAndImportSource() async throws {
        let suiteName = "ImportedDirectoryUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = URL(fileURLWithPath: "/tmp/codex-rollouts", isDirectory: true)
        let settings = ImportedDirectorySettings(defaults: defaults)
        settings.save(directory)
        let original = report([session("stored")])
        let runtime = StubExplorerRuntime(report: original)
        let model = SessionExplorerModel(runtimeFactory: { runtime }, importedDirectorySettings: settings)
        await model.loadIfNeeded()
        await runtime.failImports()

        await model.update()

        XCTAssertEqual(model.report, original)
        XCTAssertEqual(model.importedDirectory, directory)
        XCTAssertEqual(model.activity, .idle)
        XCTAssertTrue(model.errorMessage?.contains("Fixture import failure") == true)
    }

    private func session(_ id: String) -> SessionSummary {
        SessionSummary(id: id, model: "model", totals: UsageTotals(requests: 1, inputTokens: 100))
    }

    private func report(_ sessions: [SessionSummary]) -> UsageReport {
        UsageReport(totals: UsageTotals(requests: Int64(sessions.count)), sessions: sessions, diagnostics: [:])
    }
}
