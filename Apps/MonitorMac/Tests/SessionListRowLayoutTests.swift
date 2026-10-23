import AppKit
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class SessionListRowLayoutTests: XCTestCase {
    func testReferenceRowsUseThreeCompactLinesAtSidebarWidths() throws {
        for width: CGFloat in [280, 360, 600] {
            let host = NSHostingView(rootView: SessionListRow(node: root, provenance: rootProvenance)
                .frame(width: width).environment(\.locale, Locale(identifier: "en_US")))
            XCTAssertLessThanOrEqual(host.fittingSize.height, 64, "Standard rows must stay compact at \(width)")
            XCTAssertEqual(host.fittingSize.width, width, accuracy: 1)
        }
    }

    func testLightDarkNativeListAndChildFixtures() throws {
        for scheme in [ColorScheme.light, .dark] {
            try capture(name: "sidebar-reference-\(scheme)", width: 600, scheme: scheme) {
                List {
                    SessionListRow(node: root, provenance: rootProvenance).tag(root.id)
                        .listRowSeparator(.visible)
                    SessionListRow(node: child, provenance: childProvenance).tag(child.id)
                        .listRowSeparator(.visible)
                }
                .listStyle(.sidebar)
                .frame(height: 185)
            }
        }
    }

    func testNarrowLongNamesUnknownCacheAndDateRemainBounded() throws {
        let session = SessionSummary(id: "01a0fbef-874a-7a12-a6eb-0efc0c0e2ff8",
                                     model: "a-very-long-model-name-with-provider-and-version",
                                     totals: UsageTotals(requests: 6_622, inputTokens: 1_152_474_701,
                                                         outputTokens: 5_330_521, unknownCacheRequests: 1))
        let node = SessionTreeNode(session: session, state: .orphan)
        let provenance = SessionProvenance(
            sessionID: session.id,
            sessionTitle: "A very long session title that must never cover cache or relationship"
        )
        for scheme in [ColorScheme.light, .dark] {
            try capture(name: "sidebar-narrow-unknown-\(scheme)", width: 260, scheme: scheme) {
                SessionListRow(node: node, provenance: provenance,
                               sortDetail: "Last request: Oct 23, 2026 at 9:15 PM")
                    .padding(8)
            }
        }
    }

    func testDeepChildAtMinimumSidebarWidthKeepsTrailingCache() throws {
        try capture(name: "sidebar-deep-child-minimum-width", width: 180, scheme: .light) {
            SessionListRow(node: child, provenance: childProvenance)
        }
    }

    func testLargeCountsDoNotOverflowAndAllowAnAccessibleLayout() throws {
        let session = SessionSummary(id: "large-counts", model: "mixed",
                                     totals: UsageTotals(requests: Int64.max, inputTokens: Int64.max,
                                                         outputTokens: Int64.max, unknownCacheRequests: 1))
        try capture(name: "sidebar-large-counts", width: 260, scheme: .light) {
            SessionListRow(node: SessionTreeNode(session: session, state: .unknown), provenance: nil)
                .environment(\.dynamicTypeSize, .accessibility1)
                .padding(8)
        }
    }

    func testTrailingCacheColumnHighlightsOnlyKnownLowValues() throws {
        for scheme in [ColorScheme.light, .dark] {
            try capture(name: "sidebar-cache-emphasis-\(scheme)", width: 340, scheme: scheme) {
                VStack(spacing: 8) {
                    SessionListRow(node: root, provenance: rootProvenance)
                    emphasisRow(name: "Low cache", cached: 700)
                    emphasisRow(name: "At threshold", cached: 800)
                    emphasisRow(name: "Partial cache", cached: 100, unknown: 1)
                    emphasisRow(name: "Zero input", cached: 0, input: 0)
                }
                .padding(8)
            }
        }
    }

    private func emphasisRow(name: String, cached: Int64, input: Int64 = 1_000,
                             unknown: Int64 = 0) -> some View {
        let summary = SessionSummary(id: name, model: "mixed", totals: UsageTotals(
            requests: 10, inputTokens: input, cachedInputTokens: cached, unknownCacheRequests: unknown
        ))
        return SessionListRow(node: SessionTreeNode(session: summary, state: .knownRoot),
                              provenance: SessionProvenance(sessionID: name, sessionTitle: name))
    }

    private var root: SessionTreeNode {
        SessionTreeNode(session: SessionSummary(id: "01a0fbef-874a-7a12-a6eb-0efc0c0e2ff8", model: "mixed",
                                                totals: UsageTotals(requests: 6_622, inputTokens: 1_152_474_701,
                                                                    cachedInputTokens: 1_121_582_848,
                                                                    outputTokens: 5_330_521)), state: .knownRoot)
    }

    private var rootProvenance: SessionProvenance {
        SessionProvenance(sessionID: root.id, sessionTitle: "NormLab")
    }

    private var child: SessionTreeNode {
        SessionTreeNode(session: SessionSummary(id: "01a1548d-ee81-7731-a878-696eab144ea8", model: "gpt-6-luna",
                                                totals: UsageTotals(requests: 35, inputTokens: 3_100_000,
                                                                    cachedInputTokens: 2_997_700,
                                                                    outputTokens: 31_714)), state: .attached)
    }

    private var childProvenance: SessionProvenance {
        SessionProvenance(sessionID: child.id, displayName: "Aristotle",
                          relationship: SessionRelationship(kind: .subagent, parentSessionID: root.id))
    }

    private func capture<Content: View>(
        name: String, width: CGFloat, scheme: ColorScheme, @ViewBuilder content: () -> Content
    ) throws {
        let host = NSHostingView(rootView: content().frame(width: width)
            .environment(\.colorScheme, scheme)
            .environment(\.locale, Locale(identifier: "en_US"))
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame.size = NSSize(width: width, height: host.fittingSize.height)
        XCTAssertEqual(host.fittingSize.width, width, accuracy: 1, "No row may widen its sidebar")
        if !name.hasPrefix("sidebar-cache-emphasis") {
            XCTAssertLessThan(host.fittingSize.height, 200, "Long text must not create a tall card")
        }
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
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
