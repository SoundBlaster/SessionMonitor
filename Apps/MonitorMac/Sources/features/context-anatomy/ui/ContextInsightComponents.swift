import MonitorCore
import SwiftUI

struct ContextInsightMetric: View {
    let title: LocalizedStringKey
    let tokens: Int64?

    var body: some View {
        DesignMetric(title: Text(title),
                     value: Text(tokens.map(ContextAnatomyPresentation.compactTokens) ?? "Unknown"))
            .accessibilityValue(tokens.map { $0.formatted() } ?? "Unknown")
    }
}

struct ContextInsightSignalCard: View {
    let presentation: ContextInsightCardPresentation
    @State var isEvidenceExpanded = false

    var body: some View {
        let insight = presentation.insight
        DesignCard {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                DesignCardHeader {
                    Label(presentation.title, systemImage: ContextInsightPresentation.symbol(insight.kind))
                } accessory: {
                    DesignBadge(title: Text(insight.isHypothesis ? "Hypothesis" : "Observed"))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: DesignTokens.Layout.metricMinimumWidth))],
                          alignment: .leading, spacing: DesignTokens.Spacing.item) {
                    ForEach(presentation.metrics) { metric in
                        DesignMetric(title: Text(metric.title), value: Text(metric.value), emphasis: .prominent)
                    }
                }
                if insight.isHypothesis {
                    Text("Possible explanation; cause is not established.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DesignEvidenceDisclosure(title: Text("Source evidence"), isExpanded: $isEvidenceExpanded) {
                    Text(insight.explanation).font(.callout)
                    Divider()
                    ForEach(insight.evidence.observed, id: \.detail) { item in
                        Text(item.detail).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityLabel("Source evidence for \(insight.title)")
            }
            .textSelection(.enabled)
        }
    }
}
