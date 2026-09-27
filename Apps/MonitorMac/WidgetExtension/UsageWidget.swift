import MonitorCore
import SwiftUI
import WidgetKit

struct SessionMonitorUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetSharedSnapshot.usageWidgetKind,
            provider: SessionMonitorWidgetProvider()
        ) { entry in
            SessionMonitorUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Usage Summary")
        .description("Input and output token totals for today and the last seven days.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct SessionMonitorUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SessionMonitorWidgetEntry

    private var today: WidgetUsagePeriodSnapshot? {
        entry.snapshot?.usage.first { $0.period == .today }
    }

    private var week: WidgetUsagePeriodSnapshot? {
        entry.snapshot?.usage.first { $0.period == .last7Days }
    }

    var body: some View {
        Group {
            if let today, let week {
                content(today: today, week: week)
            } else {
                WidgetUnavailableState(
                    title: "Usage unavailable",
                    detail: "Open SessionMonitor to refresh the shared snapshot."
                )
            }
        }
        .padding(family == .systemSmall ? WidgetDesignTokens.compactInset : WidgetDesignTokens.contentInset)
        .containerBackground(.background, for: .widget)
        .widgetURL(WidgetDeepLinkRoute.usage(family == .systemSmall ? .today : .last7Days).url)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func content(today: WidgetUsagePeriodSnapshot, week: WidgetUsagePeriodSnapshot) -> some View {
        switch family {
        case .systemSmall:
            UsageCompactView(period: today, entry: entry)
        case .systemLarge:
            UsageLargeView(today: today, week: week, entry: entry)
        default:
            UsageMediumView(today: today, week: week, entry: entry)
        }
    }
}

private struct UsageCompactView: View {
    let period: WidgetUsagePeriodSnapshot
    let entry: SessionMonitorWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignTokens.sectionSpacing) {
            WidgetTitle(title: "SessionMonitor", subtitle: "Today")
            Spacer(minLength: 0)
            if period.requests == 0 {
                Text("No usage yet").font(.title3.weight(.medium))
                Text("Usage appears after a request is recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(period.inputTokens.formatted())
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .accessibilityLabel("\(period.inputTokens) input tokens today")
                Label("\(period.requests.formatted()) requests", systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            WidgetUpdatedLabel(entry: entry)
        }
    }
}

private struct UsageMediumView: View {
    let today: WidgetUsagePeriodSnapshot
    let week: WidgetUsagePeriodSnapshot
    let entry: SessionMonitorWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignTokens.sectionSpacing) {
            WidgetTitle(title: "Usage Summary", subtitle: "Input tokens")
            HStack(alignment: .top, spacing: WidgetDesignTokens.sectionSpacing) {
                UsagePeriodMetric(period: today)
                Divider()
                UsagePeriodMetric(period: week)
            }
            Spacer(minLength: 0)
            WidgetUpdatedLabel(entry: entry)
        }
    }
}

private struct UsagePeriodMetric: View {
    let period: WidgetUsagePeriodSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WidgetFormatting.periodTitle(period.period))
                .font(.caption)
                .foregroundStyle(.secondary)
            if period.requests == 0 {
                Text("No activity").font(.title3.weight(.medium))
            } else {
                Text(period.inputTokens.formatted())
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("\(period.requests.formatted()) requests")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if period.cacheCoverage == .partial {
                    Text("\(period.unknownCacheRequests.formatted()) cache values unknown")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct UsageLargeView: View {
    let today: WidgetUsagePeriodSnapshot
    let week: WidgetUsagePeriodSnapshot
    let entry: SessionMonitorWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignTokens.sectionSpacing) {
            WidgetTitle(title: "Usage Summary", subtitle: "Aggregate token activity")
            UsageComparisonRow(title: "Today", value: today)
            UsageComparisonRow(title: "Last 7 days", value: week)
            Divider()
            if week.cacheCoverage == .partial {
                Text("\(week.unknownCacheRequests.formatted()) requests have unknown cache coverage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: WidgetDesignTokens.sectionSpacing) {
                UsageSecondaryMetric(title: "Cached input", value: week.cachedInputTokens)
                UsageSecondaryMetric(title: "Output", value: week.outputTokens)
            }
            Spacer(minLength: 0)
            WidgetUpdatedLabel(entry: entry)
        }
    }
}

private struct UsageComparisonRow: View {
    let title: String
    let value: WidgetUsagePeriodSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value.inputTokens.formatted())
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("\(value.requests.formatted()) requests")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UsageSecondaryMetric: View {
    let title: String
    let value: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value.formatted()).font(.subheadline.weight(.medium).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
