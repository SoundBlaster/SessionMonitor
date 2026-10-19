import AppKit
import MonitorCore
import MonitorPolicies
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class ContextInsightPresentationTests: XCTestCase {
    private func presentation(count: Int = 80) throws -> ContextInsightPresentation {
        let points = (0..<count).map { offset in
            RequestTimelinePoint(
                id: "request-\(offset)", sessionID: "fixture",
                timestamp: Date(timeIntervalSince1970: Double(offset) * 600), kind: .usageRequest,
                inputTokens: offset.isMultiple(of: 2) ? 20_000 : 95_000,
                cachedInputTokens: offset.isMultiple(of: 2) ? 18_000 : 0,
                outputTokens: offset == 10 ? nil : 100, model: "model", contextWindowTokens: 100_000
            )
        }
        return ContextInsightPresentation(report: ContextInsightPolicy.evaluate(
            RequestTimeline(sessionID: "fixture", query: try UsageQuery(), points: points)))
    }

    func testDenseMarkersRespectWidthAndKeepStableRequestIdentity() throws {
        let value = try presentation(count: 7_196)
        let first = value.visibleMarkers(in: 0.5...300.5, width: 280)
        let second = value.visibleMarkers(in: 20.5...320.5, width: 280)
        XCTAssertLessThanOrEqual(first.count, 11)
        XCTAssertLessThanOrEqual(second.count, 11)
        for marker in first {
            XCTAssertEqual(marker.requestID, "request-\(marker.index - 1)")
        }
        let shared = Set(first.map(\.id)).intersection(second.map(\.id))
        XCTAssertFalse(shared.isEmpty)
        for identifier in shared {
            XCTAssertEqual(first.first { $0.id == identifier }, second.first { $0.id == identifier })
        }
        XCTAssertTrue(value.visibleMarkers(in: 1...80, width: .nan).isEmpty)
    }

    func testCriticalSignalWinsItsDensityBinButAllSignalsRemainInspectable() throws {
        let value = try presentation()
        let selected = value.visibleMarkers(in: 0.5...80.5, width: 56)
        XCTAssertTrue(selected.allSatisfy { $0.kind == .criticalEntry })
        XCTAssertTrue(value.report.insightsByRequest[2]?.contains { $0.kind == .cacheDropAfterPause } == true)
        XCTAssertTrue(value.report.insightsByRequest[2]?.contains { $0.kind == .contextGrowth } == true)
    }

    func testZoneSummaryPreservesCountsAndUnknownOutput() throws {
        let value = try presentation()
        XCTAssertEqual(value.zones.reduce(0) { $0 + $1.requests }, 80)
        XCTAssertEqual(value.zones.reduce(0) { $0 + $1.phases }, value.report.phases.count)
        XCTAssertNil(value.zones.first { $0.zone == .low }?.output)
        XCTAssertEqual(value.zones.first { $0.zone == .critical }?.output, 4_000)
    }

    func testInspectionTitlesMatchAccessibleMarkerEvidence() throws {
        let value = try presentation()
        let marker = try XCTUnwrap(value.markers.first { $0.index == 2 })
        for insight in value.report.insightsByRequest[2] ?? [] {
            XCTAssertTrue(marker.titles.contains(insight.title))
            XCTAssertFalse(insight.evidence.observed.isEmpty)
        }
    }

    func testEvidenceSurvivesPointerExitAndReconcilesLiveShrink() {
        let inspection = ContextAnatomyInspection()
        inspection.select(x: 20, stepCount: 80)
        inspection.select(x: nil, stepCount: 80)
        XCTAssertNil(inspection.index)
        XCTAssertEqual(inspection.lastInspectedIndex, 20)
        inspection.reconcile(stepCount: 10)
        XCTAssertEqual(inspection.lastInspectedIndex, 10)
        inspection.reconcile(stepCount: 0)
        XCTAssertNil(inspection.lastInspectedIndex)
    }

    func testLightDarkAndNarrowSummaryRenderFromDeterministicData() throws {
        let value = try presentation(count: 12)
        let inspection = ContextAnatomyInspection()
        inspection.select(x: 2, stepCount: 12)
        for scheme in [ColorScheme.light, .dark] {
            let content = VStack(alignment: .leading, spacing: 12) {
                ContextAnatomyChart(anatomy: value.report.anatomy, timeZone: .gmt,
                                   palette: .system, inspection: inspection, insights: value)
                ContextInsightsSummary(presentation: value, inspection: inspection, isExpanded: true)
            }
            .padding(20)
            .frame(width: 760)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
            let image = try nativeImage(content, width: 760)
            XCTAssertGreaterThan(image.size.width, 0)
            let attachment = XCTAttachment(image: image)
            attachment.name = "SM-718-context-insights-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let summary = ContextInsightsSummary(presentation: value, inspection: inspection, isExpanded: true)
            .padding(12).frame(width: 360)
            .background(Color.white).environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .accessibility2)
        let image = try nativeImage(summary, width: 360)
        XCTAssertEqual(image.size.width, 360)
        let attachment = XCTAttachment(image: image)
        attachment.name = "SM-718-context-insights-narrow-large-type"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testSignalCardsUseObservedValuesAndKeepUnknownCache() throws {
        let value = try presentation(count: 12)
        let cards = try XCTUnwrap(value.cardsByRequest[2])
        let cache = try XCTUnwrap(cards.first { $0.insight.kind == .cacheDropAfterPause })
        XCTAssertEqual(cache.metrics.first { $0.id == "before" }?.value,
                       0.9.formatted(.percent.precision(.fractionLength(0...1))))
        XCTAssertEqual(cache.metrics.first { $0.id == "after" }?.value,
                       0.0.formatted(.percent.precision(.fractionLength(0...1))))
        XCTAssertTrue(cache.insight.isHypothesis)
        let growth = try XCTUnwrap(cards.first { $0.insight.kind == .contextGrowth })
        XCTAssertEqual(growth.metrics.map(\.value), ["20.0k", "95.0k"])
        XCTAssertFalse(growth.insight.isHypothesis)
        let point = RequestTimelinePoint(id: "unknown", sessionID: "unknown", timestamp: Date(), kind: .usageRequest,
                                         inputTokens: 10_000, cachedInputTokens: nil, model: "model")
        let anatomy = ContextAnatomyBuilder.build(RequestTimeline(sessionID: "unknown",
                                                                  query: try UsageQuery(), points: [point]))
        let step = try XCTUnwrap(anatomy.steps.first)
        let card = ContextInsightCardPresentation(insight: cache.insight, step: step, previous: nil)
        XCTAssertTrue(card.metrics.allSatisfy { $0.value == "Unknown" })
    }

    func testStructuredCardsRenderMultipleSignalsAndExpandedEvidence() throws {
        let value = try presentation(count: 12)
        let step = value.report.anatomy.steps[1]
        let insights = value.report.insightsByRequest[step.index] ?? []
        XCTAssertGreaterThan(insights.count, 1)
        for scheme in [ColorScheme.light, .dark] {
            let content = HStack(alignment: .top, spacing: 20) {
                ContextAnatomySnapshotCard(step: step, requestCount: 12, timeZone: .gmt,
                                          palette: .system, insights: insights)
                    .frame(width: 340)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(value.cardsByRequest[step.index] ?? []) { card in
                        ContextInsightSignalCard(presentation: card,
                                                 isEvidenceExpanded: card.insight.kind == .cacheDropAfterPause)
                    }
                }.frame(width: 420)
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
            let image = try nativeImage(content, width: 820)
            let attachment = XCTAttachment(image: image)
            attachment.name = "SM-718-structured-cards-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let narrow = ContextAnatomySnapshotCard(step: step, requestCount: 12, timeZone: .gmt,
                                               palette: .monochrome, insights: insights)
            .frame(width: 188).padding(12)
            .background(Color.white).environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .accessibility2)
        let attachment = XCTAttachment(image: try nativeImage(narrow, width: 212))
        attachment.name = "SM-718-structured-preview-narrow"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func nativeImage(_ content: some View, width: CGFloat) throws -> NSImage {
        // Swift Charts has native drawing that ImageRenderer does not faithfully capture.
        let host = NSHostingView(rootView: content)
        host.frame.size = NSSize(width: width, height: host.fittingSize.height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
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
        return image
    }
}
