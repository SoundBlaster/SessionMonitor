import Foundation
import MonitorCore
import WidgetKit

struct SessionMonitorWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSharedSnapshot?

    var isStale: Bool {
        guard let snapshot else { return true }
        return date.timeIntervalSince(snapshot.generatedAt) > WidgetDesignTokens.staleAfter
    }
}

struct SessionMonitorWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionMonitorWidgetEntry {
        SessionMonitorWidgetEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionMonitorWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionMonitorWidgetEntry>) -> Void) {
        let entry = makeEntry()
        let interval = entry.snapshot == nil
            ? WidgetDesignTokens.emptyRefreshInterval
            : WidgetDesignTokens.timelineRefreshInterval
        let refresh = entry.date.addingTimeInterval(interval)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func makeEntry() -> SessionMonitorWidgetEntry {
        SessionMonitorWidgetEntry(date: .now, snapshot: try? WidgetSharedSnapshotStore.appGroup()?.read())
    }
}
