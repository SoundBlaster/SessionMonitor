import MonitorCore
import SwiftUI

struct CacheAnalyticsControls: View {
    @Binding var viewport: CacheAnalyticsViewport
    @Binding var selection: Double?
    let slots: [CacheHitRateWidgetSlot]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                guidance
                Spacer()
                navigation
            }
            VStack(alignment: .leading) {
                navigation
                guidance
            }
        }
        .controlSize(.small)
    }

    private var guidance: some View {
        Text("Click to select · Drag or scroll to pan · Pinch to zoom")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var navigation: some View {
        HStack(spacing: CacheHitRateWidgetLayout.headerSpacing) {
            HStack(spacing: 0) {
                Button { moveSelection(by: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous interval (Option–Left Arrow)")
                    .accessibilityLabel("Select previous interval")
                    .keyboardShortcut(.leftArrow, modifiers: .option)
                    .disabled(slots.isEmpty || selection == 0)
                Button { moveSelection(by: 1) } label: { Image(systemName: "chevron.right") }
                    .help("Next interval (Option–Right Arrow)")
                    .accessibilityLabel("Select next interval")
                    .keyboardShortcut(.rightArrow, modifiers: .option)
                    .disabled(slots.isEmpty || selection == Double(slots.count - 1))
            }
            Divider().frame(height: 16)
            HStack(spacing: 0) {
                Button { zoom(by: 0.5) } label: { Image(systemName: "minus.magnifyingglass") }
                    .accessibilityLabel("Zoom out")
                    .accessibilityIdentifier("cacheHitRate.analytics.zoomOut")
                    .help("Zoom out")
                    .disabled(viewport.zoom <= 1)
                Button { zoom(by: 2) } label: { Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel("Zoom in")
                    .accessibilityIdentifier("cacheHitRate.analytics.zoom")
                    .help("Zoom in")
                    .disabled(viewport.zoom >= Double(slots.count))
            }
            Text("\(viewport.zoom.formatted(.number.precision(.fractionLength(1))))×")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .accessibilityLabel("Chart zoom")
            Button("Reset") { viewport = CacheAnalyticsViewport() }
                .help("Show full period; keep selected interval")
                .accessibilityLabel("Show full period")
                .accessibilityIdentifier("cacheHitRate.analytics.reset")
                .disabled(viewport.zoom <= 1)
        }
        .fixedSize()
    }

    private func moveSelection(by offset: Int) {
        guard !slots.isEmpty else { return }
        let index = selection.map { Int($0.rounded()) + offset } ?? (offset > 0 ? 0 : slots.count - 1)
        selection = Double(min(max(index, 0), slots.count - 1))
        if let selection { viewport.reveal(slot: selection, slotCount: slots.count) }
    }

    private func zoom(by factor: Double) {
        let domain = viewport.domain(slotCount: slots.count)
        let anchor = selection.map { ($0 - domain.lowerBound) / (domain.upperBound - domain.lowerBound) } ?? 0.5
        viewport.magnify(by: factor, anchor: anchor, slotCount: slots.count)
    }
}
