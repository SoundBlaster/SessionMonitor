import AppKit
import Foundation
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class ImportBusyHelpTests: XCTestCase {
    func testBusyImportKeepsReportAndSuccessfulSourceThenRetriesFailedFolder() async throws {
        let suite = "ImportBusyHelpTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ImportedDirectorySettings(defaults: defaults)
        let previous = URL(fileURLWithPath: "/tmp/previous", isDirectory: true)
        let selected = URL(fileURLWithPath: "/tmp/2026", isDirectory: true)
        settings.save(previous)
        let original = UsageReport(totals: UsageTotals(requests: 1), sessions: [], diagnostics: [:])
        let runtime = StubExplorerRuntime(report: original)
        let model = SessionExplorerModel(runtimeFactory: { runtime }, importedDirectorySettings: settings)
        await model.loadIfNeeded()
        await runtime.setImportBusy(true)

        await model.importDirectory(selected)

        XCTAssertEqual(model.report, original)
        XCTAssertEqual(model.importedDirectory, previous)
        XCTAssertEqual(settings.directory, previous)
        XCTAssertEqual(model.importRecoveryDirectory, selected)
        XCTAssertTrue(model.errorMessage?.contains("2026") == true)
        XCTAssertEqual(model.activity, .idle)

        await runtime.setImportBusy(false)
        await model.retryImport()

        let imports = await runtime.importedDirectories
        XCTAssertEqual(imports, [selected])
        XCTAssertEqual(model.importedDirectory, selected)
        XCTAssertEqual(settings.directory, selected)
        XCTAssertNil(model.importRecoveryDirectory)
        XCTAssertNil(model.errorMessage)
    }

    func testDismissOrReplacementClearsRecoveryAndRetryDoesNothing() async throws {
        let suite = "ImportBusyHelpTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = StubExplorerRuntime(report: UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:]))
        let model = SessionExplorerModel(
            runtimeFactory: { runtime }, importedDirectorySettings: ImportedDirectorySettings(defaults: defaults)
        )
        let selected = URL(fileURLWithPath: "/tmp/2026", isDirectory: true)
        await runtime.setImportBusy(true)
        await model.importDirectory(selected)
        model.dismissError()
        XCTAssertNil(model.importRecoveryDirectory)
        XCTAssertNil(model.errorMessage)

        await model.importDirectory(selected)
        model.reportError("A different failure")
        await runtime.setImportBusy(false)
        await model.retryImport()

        let imports = await runtime.importedDirectories
        XCTAssertTrue(imports.isEmpty)
        XCTAssertNil(model.importRecoveryDirectory)
        XCTAssertEqual(model.errorMessage, "A different failure")
    }

    func testOtherImportErrorsDoNotOfferBusyRecovery() async throws {
        let suite = "ImportBusyHelpTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let runtime = StubExplorerRuntime(report: UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:]))
        let model = SessionExplorerModel(
            runtimeFactory: { runtime }, importedDirectorySettings: ImportedDirectorySettings(defaults: defaults)
        )
        await runtime.failImports()

        await model.importDirectory(URL(fileURLWithPath: "/tmp/2026", isDirectory: true))

        XCTAssertNil(model.importRecoveryDirectory)
        XCTAssertTrue(model.errorMessage?.contains("Fixture import failure") == true)
        XCTAssertEqual(model.activity, .idle)
    }

    func testNativeHelpLightDarkAndNarrow() throws {
        for (name, scheme, width) in [
            ("light", ColorScheme.light, CGFloat(640)),
            ("dark", ColorScheme.dark, CGFloat(640)),
            ("narrow", ColorScheme.light, CGFloat(320))
        ] {
            let content = SessionImportBusyBanner(
                directory: URL(fileURLWithPath: "/tmp/September 2026 Codex sessions", isDirectory: true),
                isBusy: false, retry: {}, dismiss: {}
            )
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, name == "narrow" ? .accessibility1 : .large)
            .frame(width: width)
            .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: content)
            host.frame.size = NSSize(width: width, height: host.fittingSize.height)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size)
            image.addRepresentation(bitmap)
            let attachment = XCTAttachment(image: image)
            attachment.name = "import-busy-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
