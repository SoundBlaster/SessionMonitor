import AppKit
import MonitorCore
import Observation
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class SessionImportLayoutTests: XCTestCase {
    func testImportNoticeStaysBelowToolbarAndOutsideScrollingContent() throws {
        let state = ImportFixtureState()
        let measurements = ImportFixtureMeasurements()
        let host = NSHostingView(rootView: ImportFixturePage(state: state, measurements: measurements))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 760, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.toolbar = NSToolbar(identifier: "ImportLayoutFixture")
        window.toolbarStyle = .unified
        window.contentView = host
        window.isReleasedWhenClosed = false
        defer { window.close() }

        for scheme in [ColorScheme.light, .dark] {
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            for width: CGFloat in [760, 1_280] {
                window.setContentSize(NSSize(width: width, height: 600))
                window.orderFrontRegardless()
                settle(window)
                let sidebar = try XCTUnwrap(measurements.frames["sidebar"])
                let summary = try XCTUnwrap(measurements.frames["summary"])
                state.progress = ImportProgress(
                    completedFiles: 2, totalFiles: 87,
                    currentFileName: "rollout-2026-10-24T21-25-44-long-session-identifier-for-layout-regression.jsonl",
                    currentFileBytesProcessed: 12_345_678, currentFileSize: 123_456_789
                )
                settle(window)
                let notice = try XCTUnwrap(measurements.frames["notice"])
                let importingSummary = try XCTUnwrap(measurements.frames["summary"])
                XCTAssertGreaterThan(notice.height, 0)
                XCTAssertGreaterThanOrEqual(notice.minY, host.safeAreaInsets.top - 1)
                XCTAssertLessThanOrEqual(notice.maxY, host.bounds.height - host.safeAreaInsets.bottom + 1)
                XCTAssertGreaterThanOrEqual(importingSummary.minY, notice.maxY - 1)
                XCTAssertEqual(measurements.frames["sidebar"], sidebar)
                try attach(window, name: "import-progress-\(scheme)-\(Int(width))")
                state.progress = nil
                settle(window)
                XCTAssertEqual(measurements.frames["summary"], summary)
            }
        }
    }

    private func settle(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    private func attach(_ window: NSWindow, name: String) throws {
        let view = try XCTUnwrap(window.contentView?.superview)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor @Observable
private final class ImportFixtureState {
    var progress: ImportProgress?
}

@MainActor
private final class ImportFixtureMeasurements {
    var frames: [String: NSRect] = [:]
}

private struct ImportFixturePage: View {
    let state: ImportFixtureState
    let measurements: ImportFixtureMeasurements

    var body: some View {
        NavigationSplitView {
            Color.gray.opacity(0.1)
                .background(ImportFrameProbe(name: "sidebar", measurements: measurements))
                .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 240)
        } detail: {
            SessionExplorerDetailLayout {
                ScrollView {
                    Text("Session overview")
                        .padding(24)
                        .background(ImportFrameProbe(name: "summary", measurements: measurements))
                    Color.clear.frame(height: 1_500)
                }
            } notices: {
                if let progress = state.progress {
                    SessionImportProgressBanner(progress: progress, cancel: {})
                        .background(ImportFrameProbe(name: "notice", measurements: measurements))
                }
            }
        }
    }
}

private struct ImportFrameProbe: View {
    let name: String
    let measurements: ImportFixtureMeasurements

    var body: some View {
        Color.clear.onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .global)
        } action: { frame in
            measurements.frames[name] = frame
        }
    }
}
