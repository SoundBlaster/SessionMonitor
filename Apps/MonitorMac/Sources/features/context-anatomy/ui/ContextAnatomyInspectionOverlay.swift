import Charts
import MonitorCore
import SwiftUI

/// Observes inspection at the leaf: moving the pointer updates this overlay, never the chart's marks.
struct ContextAnatomyInspectionOverlay: View {
    let anatomy: ContextAnatomy
    let timeZone: TimeZone
    let palette: UsageChartPalette
    let inspection: ContextAnatomyInspection
    var insights: ContextInsightPresentation?
    let proxy: ChartProxy
    let plot: CGRect
    let onZoom: (Double, Double) -> Void
    let onPan: (Double) -> Bool

    var body: some View {
        let index = inspection.index
        let step = index.flatMap { anatomy.steps.indices.contains($0 - 1) ? anatomy.steps[$0 - 1] : nil }
        ZStack(alignment: .topLeading) {
            ContextAnatomyInteractionSurface(
                onHover: { pointX in
                    inspection.select(x: pointX.flatMap { proxy.value(atX: $0, as: Double.self) },
                                      stepCount: anatomy.steps.count)
                },
                onZoom: onZoom, onPan: onPan
            )
            .frame(width: plot.width, height: plot.height)
            .offset(x: plot.minX, y: plot.minY)
            if let index, let step, let position = proxy.position(forX: Double(index)),
               position >= 0, position <= plot.width {
                Rectangle()
                    .fill(palette.average.opacity(0.5))
                    .frame(width: 1, height: plot.height)
                    .offset(x: plot.minX + position - 0.5, y: plot.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                snapshotCard(step: step, position: position)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func snapshotCard(step: ContextAnatomyStep, position: CGFloat) -> some View {
        let placement = ContextAnatomyPresentation.snapshotCardPlacement(
            anchorX: Double(position), plotWidth: Double(plot.width))
        let gap = CGFloat(ContextAnatomyPresentation.snapshotCardGap)
        let ruleX = plot.minX + position
        return ContextAnatomySnapshotCard(step: step, requestCount: anatomy.steps.count,
                                          timeZone: timeZone, palette: palette,
                                          insights: insights?.report.insightsByRequest[step.index] ?? [])
            .frame(width: CGFloat(placement.width))
            .fixedSize(horizontal: false, vertical: true)
            .alignmentGuide(.leading) { dimensions in
                placement.side == .right ? -(ruleX + gap) : dimensions.width - (ruleX - gap)
            }
            .alignmentGuide(.top) { _ in -(plot.minY + gap) }
    }
}

/// Kept outside Charts' overlay so the chart's accessibility representation cannot absorb its identifier.
/// Always mounted, including without a pointer; only this leaf observes the selected request.
struct ContextAnatomyInspectionAccessibility: View {
    let anatomy: ContextAnatomy
    let timeZone: TimeZone
    let inspection: ContextAnatomyInspection
    var insights: ContextInsightPresentation?
    let onStep: (Int) -> KeyPress.Result

    var body: some View {
        let step = inspection.index.flatMap { anatomy.steps.indices.contains($0 - 1) ? anatomy.steps[$0 - 1] : nil }
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel("Request snapshot")
            .accessibilityValue(ContextAnatomyPresentation.snapshotAccessibilityValue(
                for: step, in: anatomy, timeZone: timeZone)
                + (step.flatMap { insights?.report.insightsByRequest[$0.index] }?
                    .map { ". \($0.title). \($0.explanation)" }.joined(separator: ". ") ?? ""))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: _ = onStep(1)
                case .decrement: _ = onStep(-1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("contextAnatomy.snapshot")
    }
}
