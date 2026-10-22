import AppKit
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class SessionSummaryLayoutTests: XCTestCase {
    func testSummaryLightDarkAndNarrowLayoutFromDeterministicData() throws {
        var wideHeight: CGFloat = 0
        for scheme in [ColorScheme.light, .dark] {
            let window = summaryWindow(session: fixture(), width: 1_040, scheme: scheme)
            defer { window.orderOut(nil) }
            let height = try XCTUnwrap(window.contentView).bounds.height
            XCTAssertLessThan(height, 230, "Compact summary must leave room for the chart")
            if wideHeight > 0 { XCTAssertEqual(height, wideHeight, accuracy: 1) }
            wideHeight = height
            try attach(window, name: "session-summary-\(scheme)")
        }
        let session = SessionSummary(
            id: "fixture-session-with-a-long-selectable-identifier", model: "Long model name with additional context",
            totals: UsageTotals(requests: 999_999, inputTokens: 9_999_999_999, cachedInputTokens: 8_888_888_888,
                                outputTokens: 1_111_111_111, unknownCacheRequests: 1)
        )
        let narrow = summaryWindow(session: session, width: 360, scheme: .light, largeType: true)
        defer { narrow.orderOut(nil) }
        XCTAssertGreaterThan(try XCTUnwrap(narrow.contentView).bounds.height, wideHeight)
        try attach(narrow, name: "session-summary-narrow-large-type-partial")
    }

    func testUnavailableSummaryFixturesAndKnownZero() throws {
        typealias Fixture = (totals: UsageTotals, expected: SessionCacheHitPresentation.Availability)
        let fixtures: [String: Fixture] = [
            "no-requests": (UsageTotals(), .unavailable(reason: .noCanonicalRequests)),
            "zero-input": (UsageTotals(requests: 1), .unavailable(reason: .zeroInput)),
            "partial": (UsageTotals(requests: 2, inputTokens: 100, cachedInputTokens: 50, unknownCacheRequests: 1),
                        .unavailable(reason: .partialCoverage(unknownRequests: 1))),
            "known-zero": (UsageTotals(requests: 1, inputTokens: 100), .known(ratio: 0))
        ]
        for name in fixtures.keys.sorted() {
            let fixture = try XCTUnwrap(fixtures[name])
            XCTAssertEqual(SessionCacheHitPresentation(totals: fixture.totals).state, fixture.expected)
            let session = SessionSummary(id: "fixture", model: "", totals: fixture.totals)
            let window = summaryWindow(session: session, width: 800, scheme: .light)
            defer { window.orderOut(nil) }
            try attach(window, name: "session-summary-\(name)")
        }
    }

    private func fixture() -> SessionSummary {
        SessionSummary(id: "fixture-session-0001", model: "gpt-6-luna", totals: UsageTotals(
            requests: 34, inputTokens: 3_703_836, cachedInputTokens: 3_429_179, outputTokens: 41_198
        ))
    }

    private func summaryWindow(session: SessionSummary, width: CGFloat,
                               scheme: ColorScheme, largeType: Bool = false) -> NSWindow {
        let provider = SessionReportContextProvider(snapshot: SessionReportSnapshot(
            report: UsageReport(totals: session.totals, sessions: [session], diagnostics: [:]),
            selectedSessionID: session.id
        ))
        let content = SessionSummaryView(session: session, provider: provider)
            .padding(DesignTokens.Layout.pageInset)
            .frame(width: width, alignment: .leading)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.dynamicTypeSize, largeType ? .accessibility2 : .large)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: content)
        host.frame.size = NSSize(width: width, height: host.fittingSize.height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        settle()
        return window
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    private func attach(_ window: NSWindow, name: String) throws {
        let host = try XCTUnwrap(window.contentView)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(bitmap)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
