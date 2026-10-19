import MonitorCore
import SwiftUI

/// Shared visual vocabulary for the passive preview and the persistent evidence panel.
enum ContextInsightStyle {
    static let tightSpacing: CGFloat = 4
    static let itemSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let cornerRadius: CGFloat = 12
    static let shadowRadius: CGFloat = 8
    static let zoneMinimumWidth: CGFloat = 150
    static let snapshotMetricMinimumWidth: CGFloat = 70

    static func zoneTitle(_ zone: ContextFillZone) -> LocalizedStringKey {
        switch zone {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        case .critical: "Critical"
        }
    }
}

struct ContextInsightBadge: View {
    let title: LocalizedStringKey
    var fill: Color = .secondary.opacity(0.10)

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .padding(.horizontal, ContextInsightStyle.itemSpacing)
            .padding(.vertical, ContextInsightStyle.tightSpacing)
            .background(fill, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ContextInsightMetric: View {
    let title: LocalizedStringKey
    let tokens: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: ContextInsightStyle.tightSpacing) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(tokens.map(ContextAnatomyPresentation.compactTokens) ?? "Unknown")
                .font(.callout.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(tokens.map { $0.formatted() } ?? "Unknown")
    }
}

struct ContextInsightSignalCard: View {
    let presentation: ContextInsightCardPresentation
    @State var isEvidenceExpanded = false

    var body: some View {
        let insight = presentation.insight
        VStack(alignment: .leading, spacing: ContextInsightStyle.sectionSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Label(presentation.title, systemImage: ContextInsightPresentation.symbol(insight.kind))
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: ContextInsightStyle.itemSpacing)
                    ContextInsightBadge(title: insight.isHypothesis ? "Hypothesis" : "Observed")
                }
                VStack(alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
                    Label(presentation.title, systemImage: ContextInsightPresentation.symbol(insight.kind))
                        .font(.callout.weight(.semibold))
                    ContextInsightBadge(title: insight.isHypothesis ? "Hypothesis" : "Observed")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: ContextInsightStyle.zoneMinimumWidth))],
                      alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
                ForEach(presentation.metrics) { metric in
                    VStack(alignment: .leading, spacing: ContextInsightStyle.tightSpacing) {
                        Text(metric.title).font(.caption).foregroundStyle(.secondary)
                        Text(metric.value).font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            if insight.isHypothesis {
                Text("Possible explanation; cause is not established.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Source evidence", isExpanded: $isEvidenceExpanded) {
                VStack(alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
                    Text(insight.explanation).font(.callout)
                    Divider()
                    ForEach(insight.evidence.observed, id: \.detail) { item in
                        Text(item.detail).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, ContextInsightStyle.itemSpacing)
            }
            .font(.caption)
            .accessibilityLabel("Source evidence for \(insight.title)")
        }
        .textSelection(.enabled)
        .padding(ContextInsightStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: ContextInsightStyle.cornerRadius))
    }
}
