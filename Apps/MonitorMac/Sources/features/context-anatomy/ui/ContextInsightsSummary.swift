import MonitorCore
import SwiftUI

struct ContextInsightsSummary: View {
    let presentation: ContextInsightPresentation
    let inspection: ContextAnatomyInspection
    var palette: UsageChartPalette = .system
    var timeZone: TimeZone = .current
    @State var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                ContextInsightSelection(presentation: presentation, inspection: inspection, timeZone: timeZone)
                Divider()
                Text("Session overview").font(.callout.weight(.semibold))
                ContextInsightZoneSummary(rows: presentation.zones, palette: palette)
                ContextInsightMethodology(basis: presentation.report.anatomy.basis,
                                          limitations: presentation.report.limitations)
            }
            .padding(.top, DesignTokens.Spacing.section)
        } label: {
            HStack {
                Text("Context insights").font(.callout.weight(.semibold))
                DesignBadge(title: Text("\(presentation.report.insights.count) signals"), isNumeric: true)
            }
        }
        .accessibilityIdentifier("contextAnatomy.insights")
    }
}

/// Only this leaf observes selection; summary totals and chart marks stay unchanged on hover.
private struct ContextInsightSelection: View {
    let presentation: ContextInsightPresentation
    let inspection: ContextAnatomyInspection
    let timeZone: TimeZone

    var body: some View {
        let index = inspection.lastInspectedIndex
        let insights = index.flatMap { presentation.cardsByRequest[$0] } ?? []
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
            HStack {
                Text(index.map { "Request \($0)" } ?? "Request insights")
                    .font(index == nil ? .headline : .headline.monospaced())
                if index != nil {
                    Text("Last inspected").font(.caption).foregroundStyle(.secondary)
                }
            }
            if index == nil {
                Text("Inspect a request on the chart to explore its signals.")
                    .font(.callout).foregroundStyle(.secondary)
            } else if insights.isEmpty {
                Text("No matching signals. This is not a complete health assessment.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(insights) { insight in
                ContextInsightSignalCard(presentation: insight)
            }
            if let index, presentation.report.anatomy.steps.indices.contains(index - 1) {
                DisclosureGroup("Full request snapshot") {
                    let step = presentation.report.anatomy.steps[index - 1]
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
                        ForEach(ContextAnatomyPresentation.snapshotLines(for: step, in: presentation.report.anatomy,
                                                                        timeZone: timeZone), id: \.self) {
                            Text($0).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, DesignTokens.Spacing.item)
                    .textSelection(.enabled)
                }
                .font(.caption).foregroundStyle(.secondary)
                .id(index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("contextAnatomy.insightEvidence")
    }
}

private struct ContextInsightZoneSummary: View {
    let rows: [ContextInsightPresentation.ZoneRow]
    let palette: UsageChartPalette

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: DesignTokens.Layout.metricMinimumWidth))],
                  alignment: .leading, spacing: DesignTokens.Spacing.item) {
            ForEach(rows) { row in
                ContextInsightZoneCard(row: row, palette: palette)
            }
        }
    }
}

private struct ContextInsightZoneCard: View {
    let row: ContextInsightPresentation.ZoneRow
    let palette: UsageChartPalette

    var body: some View {
        DesignCard(surface: .tinted(palette.color(for: row.zone))) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
                Text(ContextInsightPresentation.zoneTitle(row.zone)).font(.callout.weight(.semibold))
                Text("\(row.requests) requests").font(.headline).monospaced()
                Text("\(row.phases) phases").font(.caption.monospaced()).foregroundStyle(.secondary)
                Divider()
                ContextInsightMetric(title: "Input tokens", tokens: row.input)
                ContextInsightMetric(title: "Output tokens", tokens: row.output)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ContextInsightMethodology: View {
    let basis: ContextFillBasis
    let limitations: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
            Text(basis == .sessionPeak ? "Zones are relative to session peak, not model capacity."
                 : "Zone totals cover observed requests; input volume is not unique context content.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Coverage and interpretation") {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
                    if basis == .sessionPeak {
                        Text("Critical does not mean near capacity. Input volume is not unique context content.")
                    }
                    ForEach(limitations, id: \.self) { Text($0) }
                }
                .padding(.top, DesignTokens.Spacing.item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
