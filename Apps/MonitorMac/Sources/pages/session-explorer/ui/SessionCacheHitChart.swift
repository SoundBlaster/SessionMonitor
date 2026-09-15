import Charts
import MonitorCore
import MonitorPolicies
import SwiftUI

struct SessionCacheHitChart: View {
    let sessions: [SessionSummary]
    let provenance: [String: SessionProvenance]
    let query: UsageQuery
    let isSearchActive: Bool
    let policy: CacheHitThresholdPolicy
    let selectedSessionID: String?
    let onSelect: (String?) -> Void

    private var data: [SessionCacheHitChartDatum] {
        SessionCacheHitChartDatum.make(sessions: sessions, provenance: provenance, policy: policy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if data.isEmpty {
                emptyState
            } else {
                thresholdDescription
                legend
                selectedSessionDescription
                chart
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cache hit by session")
        .accessibilityValue(
            data.isEmpty
                ? "No sessions in the selected period."
                : "\(data.count.formatted()) sessions in \(query.timeZoneIdentifier). "
                    + "Minimum threshold \(thresholdLabel)."
        )
        .accessibilityIdentifier("sessionCacheHit.chart")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label("Cache hit by session", systemImage: "chart.bar.xaxis")
                .font(.headline)
            Spacer(minLength: 4)
            Text(data.count, format: .number)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Session count")
        }
    }

    private var thresholdDescription: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Minimum threshold \(thresholdLabel)")
                .font(.caption.weight(.semibold))
            Text("Known values below the line are marked low; unavailable coverage stays neutral.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cache hit threshold")
        .accessibilityValue("\(thresholdLabel). \(thresholdDescriptionText)")
    }

    private var thresholdDescriptionText: String {
        "Known values below the line are marked low; unavailable coverage stays neutral."
    }

    private var thresholdLabel: String {
        policy.threshold.percent.formatted(.number.precision(.fractionLength(0...2))) + "%"
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            legendRow
            legendColumn
        }
        .font(.caption2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart legend")
    }

    private var legendRow: some View {
        HStack(spacing: 8) {
            legendItem(.primary, label: "Known")
            legendItem(.red, label: "Below threshold")
            legendItem(.secondary, label: "Unavailable")
        }
    }

    private var legendColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            legendItem(.primary, label: "Known")
            legendItem(.red, label: "Below threshold")
            legendItem(.secondary, label: "Unavailable")
        }
    }

    private func legendItem(_ color: Color, label: String) -> some View {
        Label(label, systemImage: label == "Unavailable" ? "diamond.fill" : "rectangle.fill")
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var selectedSessionDescription: some View {
        if let selectedSessionID, let selected = data.first(where: { $0.id == selectedSessionID }) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(selected.axisLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(selected.valueLabel)
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text(selected.statusLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.caption2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Selected session \(selected.displayName)")
            .accessibilityValue("\(selected.valueLabel). \(selected.statusLabel).")
            .accessibilityIdentifier("sessionCacheHit.selected")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            isSearchActive ? "No sessions match this search" : "No sessions in this period",
            systemImage: "chart.bar.xaxis",
            description: Text(
                isSearchActive
                    ? "Clear the search to see all sessions in the selected period."
                    : "Import canonical usage or change the selected period."
            )
        )
        .frame(maxWidth: .infinity, minHeight: 108)
        .accessibilityIdentifier("sessionCacheHit.empty")
    }

    private var chart: some View {
        ScrollView(.vertical, showsIndicators: data.count > 8) {
            Chart {
                RuleMark(x: .value("Threshold", policy.threshold.percent))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                ForEach(data) { datum in
                    chartMark(datum)
                }
            }
            .chartXScale(domain: 0...100)
            .chartForegroundStyleScale([
                "Known": Color.primary,
                "Below threshold": Color.red,
                "Unavailable": Color.secondary
            ])
            .chartXAxis {
                AxisMarks(values: [0.0, 25.0, 50.0, 75.0, 100.0]) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text(Self.percentLabel(percent))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: data.map(\.index)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let index = value.as(Int.self), let datum = data.first(where: { $0.index == index }) {
                            Text(datum.axisLabel)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...max(0, data.count - 1))
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 1, coordinateSpace: .local) { location in
                            let plotFrame = geometry[proxy.plotAreaFrame]
                            guard plotFrame.contains(location) else { return }
                            let plotY = location.y - plotFrame.minY
                            guard let index: Int = proxy.value(atY: plotY, as: Int.self),
                                  let datum = data.first(where: { $0.index == index }) else { return }
                            onSelect(datum.id)
                        }
                }
            }
            .frame(height: chartHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Cache hit session chart")
            .accessibilityHint("Select a session bar to open its detail.")
        }
        .frame(maxHeight: 245)
        .accessibilityIdentifier("sessionCacheHit.plot")
    }

    private var chartHeight: CGFloat {
        max(140, CGFloat(data.count) * 26 + 28)
    }

    @ChartContentBuilder
    private func chartMark(_ datum: SessionCacheHitChartDatum) -> some ChartContent {
        if let cacheHitPercent = datum.cacheHitPercent {
            BarMark(
                x: .value("Cache hit", cacheHitPercent),
                y: .value("Session", datum.index)
            )
            .foregroundStyle(by: .value("Status", datum.visualState.legendLabel))
            .cornerRadius(3)
            .accessibilityLabel(datum.accessibilityLabel)
            .accessibilityValue(datum.accessibilityValue)
        } else {
            PointMark(
                x: .value("Cache hit", 0),
                y: .value("Session", datum.index)
            )
            .symbol(.diamond)
            .foregroundStyle(by: .value("Status", datum.visualState.legendLabel))
            .accessibilityLabel(datum.accessibilityLabel)
            .accessibilityValue(datum.accessibilityValue)
        }
    }

    private static func percentLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }
}
