import MonitorCore
import NestedA11yIDs
import SwiftUI

/// Context size per request, with a hover snapshot and an events/tokens lane strip.
/// Pure rules live in `ContextAnatomyPresentation`; this view only lays them out.
struct ContextAnatomyView: View {
    let anatomy: ContextAnatomy
    let timeZone: TimeZone
    var palette: UsageChartPalette = .system

    @State private var selectedX: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Context anatomy", systemImage: "square.stack.3d.up")
                .font(.title2.bold())
            Text(ContextAnatomyPresentation.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            snapshot
            ContextAnatomyChart(anatomy: anatomy, selectedX: $selectedX, palette: palette)
            ContextAnatomyLegend(palette: palette)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .a11yRoot("contextAnatomy")
        .accessibilityIdentifier("contextAnatomy")
    }

    private var selectedStep: ContextAnatomyStep? {
        selectedX
            .flatMap { ContextAnatomyPresentation.stepIndex(forX: $0, stepCount: anatomy.steps.count) }
            .map { anatomy.steps[$0 - 1] }
    }

    /// Reserves room for the longest snapshot so hovering never moves the chart.
    private var snapshot: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let step = selectedStep {
                let lines = ContextAnatomyPresentation.snapshotLines(for: step, in: anatomy, timeZone: timeZone)
                ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
                    Text(line).fontWeight(offset == 0 ? .semibold : .regular)
                }
            } else {
                Text(ContextAnatomyPresentation.hint).foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit())
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("contextAnatomy.snapshot")
    }
}

private struct ContextAnatomyLegend: View {
    let palette: UsageChartPalette

    private struct Item: Identifiable {
        let title: String
        let color: Color
        var id: String { title }
    }

    private var items: [Item] {
        [
            Item(title: "New input", color: palette.warning.opacity(0.75)),
            Item(title: "Output (reasoning darker)", color: palette.improvement),
            Item(title: "Reasoning unknown", color: palette.neutral),
            Item(title: "Tools/waits", color: palette.accent),
            Item(title: "Compaction", color: palette.color(for: .compaction)),
            Item(title: "Human turn", color: palette.color(for: .humanTurn))
        ]
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items) { item in
                HStack(spacing: 4) {
                    Circle().fill(item.color).frame(width: 8, height: 8)
                    Text(item.title)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
