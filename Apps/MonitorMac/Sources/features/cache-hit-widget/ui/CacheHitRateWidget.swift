import MonitorCore
import NestedA11yIDs
import SwiftUI

/// A reusable privacy-safe card. The caller selects a family; no session or model identifier
/// enters this view's public API, rendered labels, or accessibility tree.
struct CacheHitRateWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    let report: CacheHitRateWidgetReport?
    let family: CacheHitRateWidgetAppearance.Family
    let containerStyle: CacheHitRateWidgetAppearance.ContainerStyle
    let appearance: CacheHitRateWidgetAppearance
    let periodTitle: String?
    let onOpenAnalytics: (() -> Void)?
    /// Hovering a bar shows that slot's details in a reserved line below the header.
    let inspectsBuckets: Bool
    /// Clicking an inspected bar narrows the report to that interval. Needs `inspectsBuckets`.
    let onSelectInterval: ((DateInterval) -> Void)?

    @State private var inspectedSlotID: Int?

    init(
        report: CacheHitRateWidgetReport?,
        family: CacheHitRateWidgetAppearance.Family,
        appearance: CacheHitRateWidgetAppearance = .default,
        containerStyle: CacheHitRateWidgetAppearance.ContainerStyle = .card,
        periodTitle: String? = nil,
        onOpenAnalytics: (() -> Void)? = nil,
        inspectsBuckets: Bool = false,
        onSelectInterval: ((DateInterval) -> Void)? = nil
    ) {
        self.report = report
        self.family = family
        self.appearance = appearance
        self.containerStyle = containerStyle
        self.periodTitle = periodTitle
        self.onOpenAnalytics = onOpenAnalytics
        self.inspectsBuckets = inspectsBuckets
        self.onSelectInterval = onSelectInterval
    }

    var body: some View {
        container
        .a11yRoot("cacheHitRate.widget")
        .accessibilityLabel(appearance.copy.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(onOpenAnalytics == nil ? "" : "Open cache analytics.")
    }

    @ViewBuilder
    private var container: some View {
        switch containerStyle {
        case .embedded:
            interactiveContent
        case .card:
            interactiveContent
                .padding(cardPadding)
                .background(
                    colorScheme == .dark ? appearance.palette.darkSurface : appearance.palette.lightSurface,
                    in: RoundedRectangle(cornerRadius: CacheHitRateWidgetLayout.cardCornerRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CacheHitRateWidgetLayout.cardCornerRadius)
                        .stroke(Color.primary.opacity(CacheHitRateWidgetLayout.borderOpacity))
                }
        }
    }

    @ViewBuilder
    private var interactiveContent: some View {
        if let onOpenAnalytics {
            Button(action: onOpenAnalytics) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let report {
                VStack(alignment: .leading, spacing: 10) {
                    CacheHitRateWidgetHeader(report: report, family: family, appearance: appearance,
                                             periodTitle: periodTitle)
                    switch report.availability {
                    case .available:
                        if inspectsBuckets && family != .small { inspectionLine(report) }
                        CacheHitRateWidgetChart(
                            report: report,
                            family: family,
                            appearance: appearance,
                            preservesAspectRatio: containerStyle == .card,
                            inspectedSlotID: inspectsBuckets ? $inspectedSlotID : .constant(nil),
                            onSelectSlot: selectionHandler(for: report)
                        )
                        if family == .large { footer(report) }
                    case .partialCoverage:
                        unavailableState(report, message: "Cache coverage is partial")
                    case .notApplicable:
                        unavailableState(report, message: "Cache is not applicable")
                    case .noData:
                        unavailableState(report, message: appearance.copy.noDataMessage)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(appearance.copy.title).font(.headline)
                    unavailableState(nil, message: appearance.copy.noDataMessage)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectionHandler(for report: CacheHitRateWidgetReport) -> ((Int) -> Void)? {
        guard inspectsBuckets, let onSelectInterval else { return nil }
        let slots = CacheHitRateWidgetChartPresentation.slots(for: report)
        return { id in
            if let interval = CacheHitRateWidgetBucketDetail.interval(ofSlot: id, in: slots, report: report) {
                onSelectInterval(interval)
            }
        }
    }

    /// Always present while inspection is on, so the chart below never moves when the pointer does.
    private func inspectionLine(_ report: CacheHitRateWidgetReport) -> some View {
        let slots = CacheHitRateWidgetChartPresentation.slots(for: report)
        let text = inspectedSlotID.flatMap { id in slots.first { $0.id == id } }
            .map { CacheHitRateWidgetBucketDetail.text(for: $0, report: report) }
        return Text(text ?? (onSelectInterval == nil ? CacheHitRateWidgetBucketDetail.hint
                         : CacheHitRateWidgetBucketDetail.selectableHint))
            .font(.caption2).monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
            .accessibilityHidden(true)
    }

    private func footer(_ report: CacheHitRateWidgetReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(report.sessionCount.formatted()) sessions").font(.subheadline.weight(.semibold))
                    Text("Mixed models").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                legend
            }
        }
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { legendItems }
            VStack(alignment: .leading, spacing: 3) { legendItems }
        }
        .font(.caption2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart legend")
    }

    @ViewBuilder private var legendItems: some View {
        Label { Text(appearance.copy.rangeLegend).foregroundStyle(.secondary) } icon: {
            Image(systemName: "rectangle.portrait.fill").foregroundStyle(appearance.palette.accent)
        }
        Label(appearance.copy.averageLegend, systemImage: "minus")
            .foregroundStyle(appearance.palette.average)
        Label { Text(appearance.copy.outlierLegend).foregroundStyle(.secondary) } icon: {
            Image(systemName: "circle.fill").foregroundStyle(appearance.palette.strongOutlier)
        }
    }

    private func unavailableState(_ report: CacheHitRateWidgetReport?, message: String) -> some View {
        ContentUnavailableView(
            message,
            systemImage: "chart.bar.xaxis",
            description: Text(unavailableDescription(report))
        )
            .frame(maxWidth: .infinity, minHeight: family == .small ? 90 : 120)
    }

    private var accessibilityValue: String {
        guard let report else { return appearance.copy.noDataMessage }
        guard let rate = report.periodCacheHitRate else { return unavailableDescription(report) }
        let delta = report.comparisonDeltaPercentagePoints.map(deltaLabel) ?? "No previous comparison"
        return "Cache hit rate \(percentLabel(rate)) during \(periodTitle ?? periodLabel(report.period)), \(delta)."
    }

    private func unavailableDescription(_ report: CacheHitRateWidgetReport?) -> String {
        guard let report else { return "No cache data is available yet." }
        return switch report.availability {
        case .available: ""
        case let .partialCoverage(unknownObservationCount):
            "\(unknownObservationCount.formatted()) observations have unknown cache usage."
        case .notApplicable: "No cacheable input tokens are available for this period."
        case .noData: "No canonical cache data is available for this period."
        }
    }

    private func periodLabel(_ period: CacheHitRateWidgetPeriod) -> String {
        switch period {
        case .last24Hours: "Last 24 hours"
        case .last7Days: "Last 7 days"
        case .last14Days: "Last 14 days"
        case .last30Days: "Last 30 days"
        }
    }

    private func percentLabel(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "--"
    }

    private func deltaLabel(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(1)))
        return "\(value > 0 ? "+" : "")\(number) pp"
    }

    private var cardPadding: CGFloat {
        family == .large ? CacheHitRateWidgetLayout.cardPadding : CacheHitRateWidgetLayout.compactCardPadding
    }

}
