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
    @State private var pageIndex = 0

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
        .onChange(of: pageCount) { _, newPageCount in
            pageIndex = min(pageIndex, max(0, newPageCount - 1))
        }
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
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Button("Previous session group", systemImage: "chevron.up") {
                    pageIndex = max(0, pageIndex - 1)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(pageIndex == 0)

                Text(pageDescription)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)

                Button("Next session group", systemImage: "chevron.down") {
                    pageIndex = min(pageCount - 1, pageIndex + 1)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(pageIndex >= pageCount - 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Session group navigation")

            SessionCacheHitChartPage(
                data: currentPage,
                policy: policy,
                onSelect: onSelect
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Cache hit session chart")
            .accessibilityHint(
                "Select a session bar to open its detail. Use session group controls to view more sessions."
            )
            .accessibilityValue(chartAccessibilityValue)
            .accessibilityIdentifier("sessionCacheHit.plot")
        }
        // Keep the only Charts instance bounded; the session list below remains scrollable.
        .frame(height: SessionCacheHitChartLayout.chartViewportHeight(for: currentPage.count))
        .accessibilityElement(children: .contain)
    }

    private var chartPages: [[SessionCacheHitChartDatum]] {
        stride(from: 0, to: data.count, by: SessionCacheHitChartLayout.pageSize).map { start in
            Array(data[start..<min(start + SessionCacheHitChartLayout.pageSize, data.count)])
        }
    }

    private var pageCount: Int {
        max(1, chartPages.count)
    }

    private var currentPage: [SessionCacheHitChartDatum] {
        chartPages.isEmpty ? [] : chartPages[min(pageIndex, chartPages.count - 1)]
    }

    private var pageDescription: String {
        guard let first = currentPage.first?.index, let last = currentPage.last?.index else {
            return "No sessions"
        }
        return "Sessions \(first + 1)–\(last + 1) of \(data.count)"
    }

    private var chartAccessibilityValue: String {
        let knownCount = data.filter { $0.visualState == .known }.count
        let belowCount = data.filter { $0.visualState == .belowThreshold }.count
        let unavailableCount = data.filter { $0.visualState == .unavailable }.count
        return "\(data.count.formatted()) sessions. \(knownCount.formatted()) known, "
            + "\(belowCount.formatted()) below threshold, \(unavailableCount.formatted()) unavailable. "
            + "\(thresholdLabel) threshold."
    }
}

private struct SessionCacheHitChartPage: View {
    let data: [SessionCacheHitChartDatum]
    let policy: CacheHitThresholdPolicy
    let onSelect: (String?) -> Void

    private var yDomain: ClosedRange<Int> {
        let first = data.first?.index ?? 0
        let last = data.last?.index ?? first
        return first...max(first, last)
    }

    var body: some View {
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
                        Text(SessionCacheHitChartFormat.percentLabel(percent))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(
                position: .leading,
                values: SessionCacheHitChartLayout.axisMarkIndices(
                    startingAt: data.first?.index ?? 0,
                    count: data.count
                )
            ) { value in
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
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        guard let plotAnchor = proxy.plotFrame else { return }
                        let plotFrame = geometry[plotAnchor]
                        guard plotFrame.contains(location) else { return }
                        let plotY = location.y - plotFrame.minY
                        guard let index: Int = proxy.value(atY: plotY, as: Int.self),
                              let datum = data.first(where: { $0.index == index }) else { return }
                        onSelect(datum.id)
                    }
            }
        }
        .frame(height: SessionCacheHitChartLayout.chartHeight(for: data.count))
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
        } else {
            PointMark(
                x: .value("Cache hit", 0),
                y: .value("Session", datum.index)
            )
            .symbol(.diamond)
            .foregroundStyle(by: .value("Status", datum.visualState.legendLabel))
        }
    }
}

private enum SessionCacheHitChartFormat {
    static func percentLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "%"
    }
}

enum SessionCacheHitChartLayout {
    static let maxVisibleAxisMarks = 8
    static let maxVisibleRows = 8
    static let pageSize = maxVisibleRows
    static let minimumChartHeight: CGFloat = 140
    static let maximumChartHeight: CGFloat = 220
    static let pageNavigationHeight: CGFloat = 28
    static let rowHeight: CGFloat = 26
    static let chartInsets: CGFloat = 28

    static func axisMarkCount(for sessionCount: Int) -> Int {
        min(max(sessionCount, 1), maxVisibleAxisMarks)
    }

    static func axisMarkIndices(startingAt startIndex: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        guard count > maxVisibleAxisMarks else {
            return Array(startIndex..<(startIndex + count))
        }

        let maximumSteps = maxVisibleAxisMarks - 1
        let step = max(1, Int(ceil(Double(count - 1) / Double(maximumSteps))))
        var indices = Array(stride(from: startIndex, through: startIndex + count - 1, by: step))
        let lastIndex = startIndex + count - 1
        if indices.last != lastIndex, indices.count < maxVisibleAxisMarks {
            indices.append(lastIndex)
        }
        return indices
    }

    static func visibleYDomainLength(for sessionCount: Int) -> Int {
        min(max(sessionCount, 1), maxVisibleRows)
    }

    static func chartHeight(for sessionCount: Int) -> CGFloat {
        let visibleRows = CGFloat(visibleYDomainLength(for: sessionCount))
        return min(
            maximumChartHeight,
            max(minimumChartHeight, visibleRows * rowHeight + chartInsets)
        )
    }

    static func chartViewportHeight(for sessionCount: Int) -> CGFloat {
        chartHeight(for: sessionCount) + pageNavigationHeight
    }
}
