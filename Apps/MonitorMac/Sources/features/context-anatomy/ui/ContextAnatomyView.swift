import MonitorCore
import MonitorPolicies
import NestedA11yIDs
import SwiftUI

/// Context size per request, with a hover snapshot and an events/tokens lane strip.
/// Pure rules live in `ContextAnatomyPresentation`; this view only lays them out.
struct ContextAnatomyView: View {
    let timeline: RequestTimeline
    @State private var presentation: ContextInsightPresentation?
    @State private var inspection = ContextAnatomyInspection()
    let timeZone: TimeZone
    var palette: UsageChartPalette = .system

    var body: some View {
        let current = presentation.flatMap {
            $0.report.query == timeline.query && $0.report.anatomy.sessionID == timeline.sessionID ? $0 : nil
        }
        VStack(alignment: .leading, spacing: 14) {
            Label("Context anatomy", systemImage: "square.stack.3d.up")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text(ContextAnatomyPresentation.caption(for: current?.report.anatomy.basis ?? .sessionPeak))
                Text(ContextAnatomyPresentation.hint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let presentation = current, !presentation.report.anatomy.isEmpty {
                ContextAnatomyChart(anatomy: presentation.report.anatomy, timeZone: timeZone,
                                   palette: palette, inspection: inspection, insights: presentation)
                ContextAnatomyLegend(basis: presentation.report.anatomy.basis, palette: palette)
                ContextInsightsSummary(presentation: presentation, inspection: inspection,
                                       palette: palette, timeZone: timeZone)
            } else if current == nil {
                ProgressView("Preparing context insights…")
            } else {
                Text("No requests with known input in this range.").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .task(id: timeline) {
            // One projection per source snapshot. Never rerun policies from pointer/viewport updates.
            let snapshot = timeline
            if presentation?.report.query != snapshot.query {
                inspection.reconcile(stepCount: 0)
            }
            let task = Task.detached(priority: .userInitiated) {
                ContextInsightPresentation(report: ContextInsightPolicy.evaluate(snapshot))
            }
            let value = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            guard !Task.isCancelled else { return }
            presentation = value
            inspection.reconcile(stepCount: value.report.anatomy.steps.count)
        }
        .a11yRoot("contextAnatomy")
        .accessibilityIdentifier("contextAnatomy")
    }

}

private struct ContextAnatomyLegend: View {
    let basis: ContextFillBasis
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
            Item(title: "Tools, waits, other", color: palette.color(for: ContextLaneSegments.Kind.otherActivity.flow)),
            Item(title: "Compaction", color: palette.color(for: .compaction)),
            Item(title: "Human turn", color: palette.color(for: .humanTurn))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text("Context size:")
                ForEach(ContextAnatomyPresentation.zoneLegend(for: basis), id: \.zone) { item in
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
