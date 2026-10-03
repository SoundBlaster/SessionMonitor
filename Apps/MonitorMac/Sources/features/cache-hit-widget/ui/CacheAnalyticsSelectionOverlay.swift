import AppKit
import Charts
import SwiftUI

/// Only a completed click commits a bucket. Hover and navigation preserve the choice.
struct CacheAnalyticsSelectionOverlay: View {
    let proxy: ChartProxy
    let plot: CGRect
    @Binding var selection: Double?
    let slotCount: Int
    var viewport: Binding<CacheAnalyticsViewport>?

    var body: some View {
        CacheAnalyticsInteractionSurface(
            onSelect: { location in
                guard let coordinate: Double = proxy.value(atX: location.x) else { return }
                selection = CacheAnalyticsViewport.committedSelection(
                    coordinate, previous: selection, slotCount: slotCount
                )
            },
            onPan: { translation in
                guard let viewport else { return }
                var updated = viewport.wrappedValue
                updated.pan(translation: translation, plotWidth: plot.width, slotCount: slotCount)
                viewport.wrappedValue = updated
            },
            onMagnify: { factor, anchor in
                guard let viewport else { return }
                var updated = viewport.wrappedValue
                updated.magnify(by: factor, anchor: anchor, slotCount: slotCount)
                viewport.wrappedValue = updated
            }
        )
        .frame(width: plot.width, height: plot.height)
        .position(x: plot.midX, y: plot.midY)
    }
}

/// A plot-local responder keeps mouse, trackpad and scroll-wheel navigation consistent.
private struct CacheAnalyticsInteractionSurface: NSViewRepresentable {
    let onSelect: (CGPoint) -> Void
    let onPan: (Double) -> Void
    let onMagnify: (Double, Double) -> Void

    func makeNSView(context: Context) -> CacheAnalyticsInteractionView {
        CacheAnalyticsInteractionView()
    }

    func updateNSView(_ view: CacheAnalyticsInteractionView, context: Context) {
        view.onSelect = onSelect
        view.onPan = onPan
        view.onMagnify = onMagnify
    }
}

private final class CacheAnalyticsInteractionView: NSView {
    var onSelect: ((CGPoint) -> Void)?
    var onPan: ((Double) -> Void)?
    var onMagnify: ((Double, Double) -> Void)?
    private var pressLocation: CGPoint?
    private var lastLocation: CGPoint?
    private var didDrag = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        pressLocation = location
        lastLocation = location
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressLocation, let lastLocation else { return }
        let location = convert(event.locationInWindow, from: nil)
        let distance = hypot(location.x - pressLocation.x, location.y - pressLocation.y)
        if !didDrag, distance >= CacheAnalyticsInteraction.clickDistance {
            didDrag = true
            onPan?(location.x - pressLocation.x)
        } else if didDrag {
            onPan?(location.x - lastLocation.x)
        }
        self.lastLocation = location
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let pressLocation, !didDrag, bounds.contains(location),
           hypot(location.x - pressLocation.x, location.y - pressLocation.y) < CacheAnalyticsInteraction.clickDistance {
            onSelect?(location)
        }
        pressLocation = nil
        lastLocation = nil
        didDrag = false
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        onPan?(delta * (event.hasPreciseScrollingDeltas ? 1 : CacheAnalyticsInteraction.wheelStep))
    }

    override func magnify(with event: NSEvent) {
        if event.phase == .cancelled {
            pressLocation = nil
            lastLocation = nil
            didDrag = false
            return
        }
        if pressLocation != nil { didDrag = true }
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0 else { return }
        onMagnify?(1 + event.magnification, location.x / bounds.width)
    }
}

private enum CacheAnalyticsInteraction {
    static let clickDistance: CGFloat = 4
    static let wheelStep: CGFloat = 12
}
