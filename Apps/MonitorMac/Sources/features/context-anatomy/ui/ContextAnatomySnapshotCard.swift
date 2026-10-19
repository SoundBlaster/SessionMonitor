import MonitorCore
import SwiftUI

/// A structured, passive hover preview. The always-mounted snapshot element owns accessibility.
struct ContextAnatomySnapshotCard: View {
    let step: ContextAnatomyStep
    let requestCount: Int
    let timeZone: TimeZone
    let palette: UsageChartPalette
    var insights: [ContextInsight] = []

    var body: some View {
        VStack(alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
            ContextSnapshotHeading(step: step, requestCount: requestCount, timeZone: timeZone)
            ContextSnapshotContext(step: step, palette: palette)
            Divider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: ContextInsightStyle.snapshotMetricMinimumWidth),
                                        alignment: .leading)],
                      alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
                ContextSnapshotMetric(title: "Cached", tokens: step.cachedInputTokens)
                ContextSnapshotMetric(title: "New", tokens: step.newInputTokens)
                ContextSnapshotMetric(title: "Output", tokens: step.outputTokens)
            }
            if !insights.isEmpty {
                Text("\(insights.count) signals · details in Context insights")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(ContextInsightStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ContextInsightStyle.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: ContextInsightStyle.cornerRadius).stroke(.quaternary))
        .shadow(color: .black.opacity(0.15), radius: ContextInsightStyle.shadowRadius, y: 2)
        .accessibilityHidden(true)
    }
}

private struct ContextSnapshotHeading: View {
    let step: ContextAnatomyStep
    let requestCount: Int
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: ContextInsightStyle.tightSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Request \(step.index)").fontWeight(.semibold)
                    Spacer(minLength: ContextInsightStyle.itemSpacing)
                    Text("of \(requestCount)").foregroundStyle(.secondary)
                }
                Text("Request \(step.index) of \(requestCount)").fontWeight(.semibold)
            }
            Text(step.timestamp, format: Date.FormatStyle(date: .omitted, time: .standard, timeZone: timeZone))
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout).monospacedDigit()
    }
}

private struct ContextSnapshotContext: View {
    let step: ContextAnatomyStep
    let palette: UsageChartPalette

    var body: some View {
        VStack(alignment: .leading, spacing: ContextInsightStyle.tightSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ContextAnatomyPresentation.compactTokens(step.contextTokens))
                        .font(.title2.weight(.semibold))
                        .accessibilityLabel("Context tokens")
                    Spacer(minLength: ContextInsightStyle.itemSpacing)
                    ContextInsightBadge(title: ContextInsightStyle.zoneTitle(step.zone),
                                        fill: palette.color(for: step.zone))
                }
                VStack(alignment: .leading, spacing: ContextInsightStyle.tightSpacing) {
                    Text(ContextAnatomyPresentation.compactTokens(step.contextTokens))
                        .font(.title2.weight(.semibold))
                        .accessibilityLabel("Context tokens")
                    ContextInsightBadge(title: ContextInsightStyle.zoneTitle(step.zone),
                                        fill: palette.color(for: step.zone))
                }
            }
            if let window = step.contextWindowTokens {
                let share = step.fillFraction.formatted(.percent.precision(.fractionLength(0)))
                let capacity = ContextAnatomyPresentation.compactTokens(window)
                Text("\(share) of \(capacity) window")
                    .font(.caption).foregroundStyle(.secondary)
                if step.contextWindowInferred {
                    Text("Window inferred from nearby request").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("\(step.fillFraction, format: .percent.precision(.fractionLength(0))) of session peak")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let delta = step.deltaFromPrevious {
                Text("\(delta, format: .number.sign(strategy: .always())) vs previous request")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
    }
}

private struct ContextSnapshotMetric: View {
    let title: LocalizedStringKey
    let tokens: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            Text(tokens.map(ContextAnatomyPresentation.compactTokens) ?? "Unknown").fontWeight(.semibold)
        }
        .font(.caption).monospacedDigit()
    }
}
