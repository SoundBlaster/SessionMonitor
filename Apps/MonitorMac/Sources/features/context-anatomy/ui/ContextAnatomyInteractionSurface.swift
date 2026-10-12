import AppKit
import SwiftUI

/// SM-722: a plot-sized responder for the context-anatomy chart. It reports hover from its own tracking area,
/// zooms on pinch and ⌘-scroll, moves the window on sideways scroll or drag, and hands vertical scrolling back
/// to the page. Locations are in plot coordinates.
struct ContextAnatomyInteractionSurface: NSViewRepresentable {
    let onHover: (CGFloat?) -> Void
    let onZoom: (_ factor: Double, _ anchor: Double) -> Void
    /// Returns whether the window moved; an unmoved window lets the event scroll the page instead.
    let onPan: (_ translation: Double) -> Bool

    func makeNSView(context: Context) -> ContextAnatomyInteractionView {
        ContextAnatomyInteractionView()
    }

    func updateNSView(_ view: ContextAnatomyInteractionView, context: Context) {
        view.onHover = onHover
        view.onZoom = onZoom
        view.onPan = onPan
    }
}

final class ContextAnatomyInteractionView: NSView {
    var onHover: ((CGFloat?) -> Void)?
    var onZoom: ((Double, Double) -> Void)?
    var onPan: ((Double) -> Bool)?
    private var lastDragX: CGFloat?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.inVisibleRect` follows the view's visible rect, so hover covers the whole plot after any relayout.
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp,
                                                 .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { onHover?(location(of: event).x) }
    override func mouseEntered(with event: NSEvent) { onHover?(location(of: event).x) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }

    override func mouseDown(with event: NSEvent) { lastDragX = location(of: event).x }

    override func mouseDragged(with event: NSEvent) {
        let pointX = location(of: event).x
        if let lastDragX { _ = onPan?(Double(pointX - lastDragX)) }
        lastDragX = pointX
        onHover?(pointX)
    }

    override func mouseUp(with event: NSEvent) { lastDragX = nil }

    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        if event.modifierFlags.contains(.command) {
            let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY
                : event.scrollingDeltaX
            onZoom?(ContextAnatomyViewport.zoomFactor(forScrollDelta: Double(delta), precise: precise),
                    anchorFraction(of: event))
            return
        }
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            let translation = Double(event.scrollingDeltaX) * (precise ? 1 : ContextAnatomyViewport.wheelStep)
            if onPan?(translation) == true { return }
        }
        if let enclosingScrollView {
            enclosingScrollView.scrollWheel(with: event)
        } else {
            nextResponder?.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        guard event.phase != .cancelled else { return }
        onZoom?(1 + Double(event.magnification), anchorFraction(of: event))
    }

    override func isAccessibilityElement() -> Bool { false }

    private func location(of event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    private func anchorFraction(of event: NSEvent) -> Double {
        guard bounds.width > 0 else { return 0.5 }
        return Double(location(of: event).x / bounds.width)
    }
}
