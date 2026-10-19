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
            VStack(alignment: .leading, spacing: ContextInsightStyle.sectionSpacing) {
                ContextInsightSelection(presentation: presentation, inspection: inspection, timeZone: timeZone)
                Divider()
                Text("Session overview").font(.callout.weight(.semibold))
                ContextInsightZoneSummary(rows: presentation.zones, palette: palette)
                ContextInsightMethodology(basis: presentation.report.anatomy.basis,
                                          limitations: presentation.report.limitations)
            }
            .padding(.top, ContextInsightStyle.sectionSpacing)
        } label: {
            HStack {
                Text("Context insights").font(.callout.weight(.semibold))
                ContextInsightBadge(title: "\(presentation.report.insights.count) signals")
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
        VStack(alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
            HStack {
                Text(index.map { "Request \($0)" } ?? "Request insights")
                    .font(.headline)
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
                    VStack(alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
                        ForEach(ContextAnatomyPresentation.snapshotLines(for: step, in: presentation.report.anatomy,
                                                                        timeZone: timeZone), id: \.self) {
                            Text($0).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, ContextInsightStyle.itemSpacing)
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: ContextInsightStyle.zoneMinimumWidth))],
                  alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
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
        VStack(alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
            Text(ContextInsightStyle.zoneTitle(row.zone)).font(.callout.weight(.semibold))
            Text("\(row.requests) requests").font(.headline).monospacedDigit()
            Text("\(row.phases) phases").font(.caption).foregroundStyle(.secondary)
            Divider()
            ContextInsightMetric(title: "Input tokens", tokens: row.input)
            ContextInsightMetric(title: "Output tokens", tokens: row.output)
        }
        .padding(ContextInsightStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.color(for: row.zone),
                    in: RoundedRectangle(cornerRadius: ContextInsightStyle.cornerRadius))
        .accessibilityElement(children: .combine)
    }
}

private struct ContextInsightMethodology: View {
    let basis: ContextFillBasis
    let limitations: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
            Text(basis == .sessionPeak ? "Zones are relative to session peak, not model capacity."
                 : "Zone totals cover observed requests; input volume is not unique context content.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Coverage and interpretation") {
                VStack(alignment: .leading, spacing: ContextInsightStyle.itemSpacing) {
                    if basis == .sessionPeak {
                        Text("Critical does not mean near capacity. Input volume is not unique context content.")
                    }
                    ForEach(limitations, id: \.self) { Text($0) }
                }
                .padding(.top, ContextInsightStyle.itemSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
