import MonitorCore
import NestedA11yIDs
import SwiftUI

/// Context size per request, with a hover snapshot and an events/tokens lane strip.
/// Pure rules live in `ContextAnatomyPresentation`; this view only lays them out.
struct ContextAnatomyView: View {
    let anatomy: ContextAnatomy
    let timeZone: TimeZone
    var palette: UsageChartPalette = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Context anatomy", systemImage: "square.stack.3d.up")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text(ContextAnatomyPresentation.caption)
                Text(ContextAnatomyPresentation.hint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ContextAnatomyChart(anatomy: anatomy, timeZone: timeZone, palette: palette)
            ContextAnatomyLegend(palette: palette)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .a11yRoot("contextAnatomy")
        .accessibilityIdentifier("contextAnatomy")
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
            Item(title: "New input", color: palette.color(for: ContextLaneSegments.Kind.newInput.flow)),
            Item(title: "Output (reasoning darker)", color: palette.color(for: ContextLaneSegments.Kind.output.flow)),
            Item(title: "Reasoning unknown", color: palette.neutral),
            Item(title: "Tools/waits", color: palette.color(for: ContextLaneSegments.Kind.toolsOrWaits.flow)),
            Item(title: "Compaction", color: palette.color(for: .compaction)),
            Item(title: "Human turn", color: palette.color(for: .humanTurn))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("Context size:")
                ForEach(ContextAnatomyPresentation.zoneLegend, id: \.zone) { item in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(palette.color(for: item.zone))
                            .frame(width: 10, height: 10)
                        Text(item.title)
                    }
                }
            }
            HStack(spacing: 12) {
                ForEach(items) { item in
                    HStack(spacing: 4) {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.title)
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
