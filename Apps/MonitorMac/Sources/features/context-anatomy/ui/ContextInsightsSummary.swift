import MonitorCore
import SwiftUI

struct ContextInsightsSummary: View {
    let presentation: ContextInsightPresentation
    let inspection: ContextAnatomyInspection
    @State var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Zone totals over the observed requests; input volume is not unique context content.")
                    .foregroundStyle(.secondary)
                if presentation.report.anatomy.basis == .sessionPeak {
                    Text("Zones use the session peak, not model capacity. Critical does not mean near capacity.")
                        .foregroundStyle(.secondary)
                }
                ContextInsightZoneSummary(rows: presentation.zones)
                ContextInsightSelection(presentation: presentation, inspection: inspection)
                ForEach(presentation.report.limitations, id: \.self) { limitation in
                    Text(limitation).foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.top, 6)
        } label: {
            Text("Context insights · \(presentation.report.insights.count) signals")
                .font(.callout.weight(.semibold))
        }
        .accessibilityIdentifier("contextAnatomy.insights")
    }
}

/// Only this leaf observes selection; summary totals and chart marks stay unchanged on hover.
private struct ContextInsightSelection: View {
    let presentation: ContextInsightPresentation
    let inspection: ContextAnatomyInspection

    var body: some View {
        let index = inspection.lastInspectedIndex
        let insights = index.flatMap { presentation.report.insightsByRequest[$0] } ?? []
        VStack(alignment: .leading, spacing: 8) {
            Text(index.map { "Last inspected request \($0) insights" } ?? "Inspect a request to see its evidence")
                .fontWeight(.semibold)
            if index != nil, insights.isEmpty {
                Text("No matching signal for this request; this is not a complete health assessment.")
                    .foregroundStyle(.secondary)
            }
            ForEach(insights) { insight in
                DisclosureGroup {
                    Text(insight.explanation)
                    ForEach(insight.evidence.observed, id: \.detail) { item in Text(item.detail) }
                } label: {
                    Label(insight.title, systemImage: ContextInsightPresentation.symbol(insight.kind))
                }
            }
        }
        .textSelection(.enabled)
        .accessibilityIdentifier("contextAnatomy.insightEvidence")
    }
}

private struct ContextInsightZoneSummary: View {
    let rows: [ContextInsightPresentation.ZoneRow]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Zone / phases")
                    Text("Requests")
                    Text("Input tokens")
                    Text("Output tokens")
                }
                .foregroundStyle(.secondary)
                ForEach(rows) { row in
                    GridRow {
                        Text("\(row.zone.rawValue.capitalized) · \(row.phases)")
                        Text(row.requests, format: .number)
                        Text(tokens(row.input))
                        Text(tokens(row.output))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(row.zone.rawValue.capitalized) · \(row.phases) phases · \(row.requests) requests")
                        Text("Input \(tokens(row.input)) · Output \(tokens(row.output))")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .monospacedDigit()
    }

    private func tokens(_ value: Int64?) -> String {
        value.map(ContextAnatomyPresentation.compactTokens) ?? "Unknown"
    }
}
