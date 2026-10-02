import MonitorCore
import SwiftUI

struct CacheAnalyticsControls: View {
    @Binding var viewport: CacheAnalyticsViewport
    @Binding var selection: Double?
    let slots: [CacheHitRateWidgetSlot]
    let report: CacheHitRateWidgetReport

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { zoom; position; reset }
            VStack(alignment: .leading) { zoom; position; reset }
        }
        Picker("Selected bucket", selection: $selection) {
            Text("None").tag(nil as Double?)
            ForEach(slots) { slot in
                Text(CacheAnalyticsBucketDetail.dateLabel(slot.start, report: report))
                    .tag(Optional(Double(slot.id)))
            }
        }
        .accessibilityIdentifier("cacheHitRate.analytics.bucket")
    }

    private var zoom: some View {
        VStack(alignment: .leading) {
            Text("Zoom: \(viewport.zoom.formatted(.number.precision(.fractionLength(1))))×").font(.caption)
            Slider(value: $viewport.zoom, in: 1...Double(max(slots.count, 2)))
                .accessibilityLabel("Chart zoom")
                .accessibilityIdentifier("cacheHitRate.analytics.zoom")
        }
        .frame(minWidth: CacheAnalyticsLayout.controlWidth)
    }

    private var position: some View {
        VStack(alignment: .leading) {
            Text("Position").font(.caption)
            Slider(value: $viewport.position, in: 0...1)
                .disabled(viewport.zoom <= 1 || slots.count <= 1)
                .accessibilityLabel("Position in selected period")
                .accessibilityIdentifier("cacheHitRate.analytics.position")
        }
        .frame(minWidth: CacheAnalyticsLayout.controlWidth)
    }

    private var reset: some View {
        Button("Show full period") {
            viewport = CacheAnalyticsViewport()
            selection = nil
        }
        .accessibilityIdentifier("cacheHitRate.analytics.reset")
    }
}
