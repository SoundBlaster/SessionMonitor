import MonitorCore
import SwiftUI
import WidgetKit

struct SessionMonitorWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSharedSnapshot?
}

struct SessionMonitorWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionMonitorWidgetEntry {
        SessionMonitorWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionMonitorWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionMonitorWidgetEntry>) -> Void) {
        completion(Timeline(entries: [makeEntry()], policy: .never))
    }

    private func makeEntry() -> SessionMonitorWidgetEntry {
        SessionMonitorWidgetEntry(date: .now, snapshot: try? WidgetSharedSnapshotStore.appGroup()?.read())
    }
}

struct SessionMonitorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedSnapshot.widgetKind, provider: SessionMonitorWidgetProvider()) { entry in
            SessionMonitorWidgetContent(entry: entry)
        }
        .configurationDisplayName("SessionMonitor Snapshot")
        .description("Confirms the shared usage snapshot is available to widgets.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SessionMonitorWidgetContent: View {
    let entry: SessionMonitorWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SessionMonitor", systemImage: "chart.bar.xaxis")
                .font(.headline)
            if let snapshot = entry.snapshot,
               let week = snapshot.usage.first(where: { $0.period == .last7Days }) {
                Text("Last 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(week.inputTokens.formatted())
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("input tokens · updated \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("No shared snapshot", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }
}

@main
struct SessionMonitorWidgetBundle: WidgetBundle {
    var body: some Widget { SessionMonitorWidget() }
}
