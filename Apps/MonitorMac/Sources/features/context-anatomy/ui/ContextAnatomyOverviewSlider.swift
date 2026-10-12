import MonitorCore
import SwiftUI

/// SM-722: a simplified preview of the whole session under the chart, with the visible window framed.
/// Dragging the frame moves the window; pressing elsewhere moves the window there and keeps dragging it.
struct ContextAnatomyOverviewSlider: View {
    let anatomy: ContextAnatomy
    let domain: ClosedRange<Double>
    let palette: UsageChartPalette
    /// Centre the window on a request-axis position.
    let onCenter: (Double) -> Void

    /// Axis distance between the pointer and the window centre while a drag is in progress.
    @State private var grabOffset: Double?

    private static let height: CGFloat = 32
    private static let pointsPerColumn = 2.0

    var body: some View {
        GeometryReader { geometry in
            let width = Double(geometry.size.width)
            let stepCount = anatomy.steps.count
            let frame = ContextAnatomyOverview.windowFrame(for: domain, stepCount: stepCount, width: width)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in drawPreview(in: &context, size: size) }
                    .background(palette.grid.opacity(0.25))
                outsideShade(frame: frame, width: width)
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(palette.accent, lineWidth: 1.5)
                    .frame(width: max(4, CGFloat(frame.upperBound - frame.lowerBound)), height: Self.height)
                    .offset(x: CGFloat(frame.lowerBound))
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in drag(value, frame: frame, width: width) }
                .onEnded { _ in grabOffset = nil })
        }
        .frame(height: Self.height)
        .accessibilityElement()
        .accessibilityLabel("Session overview")
        .accessibilityValue(ContextAnatomyPresentation.windowLabel(for: domain, stepCount: anatomy.steps.count)
            ?? "All requests are visible")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onCenter(ContextAnatomyOverview.pagedCenter(for: domain, by: 1))
            case .decrement: onCenter(ContextAnatomyOverview.pagedCenter(for: domain, by: -1))
            @unknown default: break
            }
        }
        .accessibilityIdentifier("contextAnatomy.overview")
    }

    private func drag(_ value: DragGesture.Value, frame: ClosedRange<Double>, width: Double) {
        let stepCount = anatomy.steps.count
        if grabOffset == nil {
            let start = Double(value.startLocation.x)
            let center = (domain.lowerBound + domain.upperBound) / 2
            grabOffset = frame.contains(start)
                ? ContextAnatomyOverview.axisPosition(atX: start, stepCount: stepCount, width: width) - center
                : 0
        }
        let position = ContextAnatomyOverview.axisPosition(atX: Double(value.location.x), stepCount: stepCount,
                                                           width: width)
        onCenter(position - (grabOffset ?? 0))
    }

    private func outsideShade(frame: ClosedRange<Double>, width: Double) -> some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.18).frame(width: CGFloat(frame.lowerBound))
            Spacer(minLength: 0)
            Color.black.opacity(0.18).frame(width: CGFloat(max(0, width - frame.upperBound)))
        }
        .allowsHitTesting(false)
    }

    private func drawPreview(in context: inout GraphicsContext, size: CGSize) {
        let stepCount = anatomy.steps.count
        guard stepCount > 0, size.width > 0 else { return }
        let peak = Double(max(1, anatomy.peakContextTokens))
        let scale = Double(size.width) / Double(stepCount)
        let usable = Double(size.height) - 2
        let buckets = ContextAnatomyOverview.buckets(of: anatomy.steps,
                                                     count: max(1, Int(Double(size.width) / Self.pointsPerColumn)))
        var line = Path()
        for bucket in buckets {
            let columnX = Double(bucket.firstIndex - 1) * scale
            let columnWidth = Double(bucket.lastIndex - bucket.firstIndex + 1) * scale
            let top = Double(size.height) - Double(bucket.peakContext) / peak * usable
            let column = CGRect(x: columnX, y: top, width: columnWidth, height: Double(size.height) - top)
            context.fill(Path(column), with: .color(palette.color(for: bucket.zone)))
            let start = CGPoint(x: columnX, y: top)
            if line.isEmpty { line.move(to: start) } else { line.addLine(to: start) }
            line.addLine(to: CGPoint(x: columnX + columnWidth, y: top))
        }
        context.stroke(line, with: .color(palette.accent), lineWidth: 1)
    }
}
