import AppKit
import MonitorCore
import QuartzCore
import SwiftUI
import XCTest
@testable import SessionMonitor

/// Opt-in Release measurement: the same fixture, viewport and pointer path before/after a change.
/// The timings include the event callback and a run-loop/layout flush, not physical display latency.
@MainActor
final class ContextAnatomyHoverPerformanceTests: XCTestCase {
    func testHoverReplay() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SM723_HOVER_BENCHMARK"] == "1",
                          "Enable SM723_HOVER_BENCHMARK=1 in a local Release test scheme.")
        let anatomy = try fixture(count: 7_196)
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let inspection = ContextAnatomyInspection()
        let host = NSHostingView(rootView: ContextAnatomyChart(
            anatomy: anatomy, timeZone: timeZone, palette: .system, inspection: inspection))
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 900, height: 380),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "SM-723 Hover Benchmark"
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
        let interaction = try XCTUnwrap(findInteraction(in: host))
        XCTAssertGreaterThan(interaction.bounds.width, 500)
        // Warm up chart layout and snapshot formatting before the measured rounds.
        for offset in 0..<20 { replay(x: 100 + CGFloat(offset), in: interaction, host: host, window: window) }
        try measureHover(in: interaction, host: host, window: window, inspection: inspection)
        try verifyViewportAndLiveData(in: interaction, host: host, window: window, inspection: inspection)
        if let pause = ProcessInfo.processInfo.environment["SM723_VISUAL_PAUSE"].flatMap(Double.init), pause > 0 {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: min(pause, 30)))
        }
    }

    private func measureHover(in interaction: ContextAnatomyInteractionView, host: NSView, window: NSWindow,
                              inspection: ContextAnatomyInspection) throws {
        let stationaryX = try stationaryCoordinate(in: interaction, host: host, window: window, inspection: inspection)
        for round in 0..<3 {
            for scenario in ["same-request", "cross-request"] {
                var milliseconds: [Double] = []
                var transitions = 0
                for offset in 0..<240 {
                    let pointX = scenario == "same-request" ? stationaryX + CGFloat(offset % 10) * 0.02
                        : 20 + CGFloat(offset % 120) / 120 * (interaction.bounds.width - 40)
                    let start = CACurrentMediaTime()
                    let previous = inspection.index
                    replay(x: pointX, in: interaction, host: host, window: window)
                    milliseconds.append((CACurrentMediaTime() - start) * 1_000)
                    if inspection.index != previous { transitions += 1 }
                }
                XCTAssertNotNil(inspection.index)
                if scenario == "same-request" { XCTAssertLessThanOrEqual(transitions, 1) }
                if scenario == "cross-request" { XCTAssertGreaterThan(transitions, 200) }
                let sorted = milliseconds.sorted()
                print("SM723 round=\(round) scenario=\(scenario) samples=\(sorted.count) "
                      + "p50_ms=\(sorted[sorted.count / 2]) p95_ms=\(sorted[Int(Double(sorted.count) * 0.95)]) "
                      + "max_ms=\(sorted.last ?? 0)")
            }
        }
    }

    private func verifyViewportAndLiveData(in interaction: ContextAnatomyInteractionView,
                                           host: NSHostingView<ContextAnatomyChart>, window: NSWindow,
                                           inspection: ContextAnatomyInspection) throws {
        let midpoint = interaction.bounds.midX
        replay(x: midpoint, in: interaction, host: host, window: window)
        let before = inspection.index
        interaction.onZoom?(2, 0.5)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertTrue(interaction.onPan?(100) == true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        replay(x: midpoint, in: interaction, host: host, window: window)
        XCTAssertNotEqual(inspection.index, before, "Hover must use the moved viewport's mapping.")
        for name in [NSAppearance.Name.darkAqua, .aqua] {
            host.appearance = NSAppearance(named: name)
            replay(x: midpoint, in: interaction, host: host, window: window)
            XCTAssertNotNil(inspection.index)
        }
        host.rootView = ContextAnatomyChart(anatomy: try fixture(count: 200),
                                          timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)),
                                          palette: .system, inspection: inspection)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(inspection.index, 200, "Live shrinkage must clamp the inspected request.")
        replay(x: midpoint, in: try XCTUnwrap(findInteraction(in: host)), host: host, window: window)
        XCTAssertTrue((1...200).contains(try XCTUnwrap(inspection.index)))
    }

    /// Find a subpixel path entirely within one request using the chart's actual mapping, including its insets.
    private func stationaryCoordinate(in view: ContextAnatomyInteractionView, host: NSView, window: NSWindow,
                                      inspection: ContextAnatomyInspection) throws -> CGFloat {
        for candidate in stride(from: 100.0, through: 110.0, by: 0.5) {
            var indices = Set<Int>()
            for offset in 0..<10 {
                replay(x: candidate + CGFloat(offset) * 0.02, in: view, host: host, window: window)
                if let index = inspection.index { indices.insert(index) }
            }
            if indices.count == 1 { return candidate }
        }
        return try XCTUnwrap(nil as CGFloat?, "Could not find a stationary hover path in this layout.")
    }

    private func replay(x coordinate: CGFloat, in view: ContextAnatomyInteractionView,
                        host: NSView, window: NSWindow) {
        let location = view.convert(NSPoint(x: coordinate, y: view.bounds.midY), to: nil)
        if let event = NSEvent.mouseEvent(with: .mouseMoved, location: location, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         eventNumber: 0, clickCount: 0, pressure: 0) {
            view.mouseMoved(with: event)
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
    }

    private func findInteraction(in view: NSView) -> ContextAnatomyInteractionView? {
        if let interaction = view as? ContextAnatomyInteractionView { return interaction }
        return view.subviews.lazy.compactMap { self.findInteraction(in: $0) }.first
    }

    private func fixture(count: Int) throws -> ContextAnatomy {
        let points = (0..<count).map { index in
            let input = Int64(10_000 + index % 200 * 700)
            return RequestTimelinePoint(
                id: "request-\(index)", sessionID: "synthetic", timestamp: Date(timeIntervalSince1970: Double(index)),
                kind: .usageRequest, inputTokens: input, cachedInputTokens: input - 1_000,
                uncachedInputTokens: 1_000, outputTokens: 900, reasoningOutputTokens: 400, model: "fixture-model")
        }
        return ContextAnatomyBuilder.build(RequestTimeline(sessionID: "synthetic", query: try UsageQuery(),
                                                          points: points))
    }
}
