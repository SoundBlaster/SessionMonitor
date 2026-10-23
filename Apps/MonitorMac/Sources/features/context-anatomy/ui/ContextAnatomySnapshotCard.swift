import MonitorCore
import SwiftUI

/// A structured, passive hover preview. The always-mounted snapshot element owns accessibility.
struct ContextAnatomySnapshotCard: View {
    let step: ContextAnatomyStep
    let requestCount: Int
    let timeZone: TimeZone
    let palette: UsageChartPalette
    var insightCount = 0

    var body: some View {
        DesignCard(surface: .floating) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
                ContextSnapshotHeading(step: step, requestCount: requestCount, timeZone: timeZone,
                                       insightCount: insightCount)
                ContextSnapshotContext(step: step, palette: palette)
                Divider()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: DesignTokens.Layout.compactMetricMinimumWidth),
                                            alignment: .leading)],
                          alignment: .leading, spacing: DesignTokens.Spacing.item) {
                    ContextSnapshotMetric(title: "Cached", tokens: step.cachedInputTokens)
                    ContextSnapshotMetric(title: "New", tokens: step.newInputTokens)
                    ContextSnapshotMetric(title: "Output", tokens: step.outputTokens)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ContextSnapshotHeading: View {
    let step: ContextAnatomyStep
    let requestCount: Int
    let timeZone: TimeZone
    let insightCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.inline) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Request \(step.index)").fontWeight(.semibold)
                    Spacer(minLength: DesignTokens.Spacing.item)
                    Text("of \(requestCount)").foregroundStyle(.secondary)
                }
                Text("Request \(step.index) of \(requestCount)").fontWeight(.semibold)
            }
            HStack {
                Text(step.timestamp, format: Date.FormatStyle(date: .omitted, time: .standard, timeZone: timeZone))
                Spacer(minLength: DesignTokens.Spacing.inline)
                if insightCount > 0 {
                    Label {
                        if insightCount == 1 {
                            Text("1 signal")
                        } else {
                            Text("\(insightCount) signals")
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .font(.callout).monospacedDigit()
    }
}

private struct ContextSnapshotContext: View {
    let step: ContextAnatomyStep
    let palette: UsageChartPalette

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.inline) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ContextAnatomyPresentation.compactTokens(step.contextTokens))
                        .font(.title2.weight(.semibold))
                        .accessibilityLabel("Context tokens")
                    Spacer(minLength: DesignTokens.Spacing.item)
                    DesignBadge(title: Text(ContextInsightPresentation.zoneTitle(step.zone)),
                                fill: palette.color(for: step.zone))
                }
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.inline) {
                    Text(ContextAnatomyPresentation.compactTokens(step.contextTokens))
                        .font(.title2.weight(.semibold))
                        .accessibilityLabel("Context tokens")
                    DesignBadge(title: Text(ContextInsightPresentation.zoneTitle(step.zone)),
                                fill: palette.color(for: step.zone))
                }
            }
            if let window = step.contextWindowTokens {
                let share = step.fillFraction.formatted(.percent.precision(.fractionLength(0)))
                let capacity = ContextAnatomyPresentation.compactTokens(window)
                HStack(spacing: DesignTokens.Spacing.inline) {
                    Text("\(share) of \(capacity) window")
                    if step.contextWindowInferred { Text("≈") }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(step.fillFraction, format: .percent.precision(.fractionLength(0))) of session peak")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let delta = step.deltaFromPrevious {
                Text("\(delta, format: .number.sign(strategy: .always())) vs previous request")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("First request").font(.caption).foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}

private struct ContextSnapshotMetric: View {
    let title: LocalizedStringKey
    let tokens: Int64?

    var body: some View {
        DesignMetric(title: Text(title),
                     value: Text(tokens.map(ContextAnatomyPresentation.compactTokens) ?? "Unknown"), emphasis: .compact)
    }
}
