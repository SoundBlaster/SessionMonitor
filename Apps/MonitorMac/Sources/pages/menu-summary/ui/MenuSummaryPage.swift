import MonitorCore
import SwiftUI

struct MenuSummaryPage: View {
    let model: MenuSummaryModel
    var query = menuPageDefaultUsageQuery()
    var scopeLabel = "All Time · UTC"
    var reportScope: ReportScopeModel?
    var watch = MenuWatchPresentation()
    var actions: MenuSummaryActions?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("SessionMonitor", systemImage: "chart.bar.xaxis")
                .font(.headline)
            if let reportScope {
                ReportScopeControls(model: reportScope)
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(watch.title, systemImage: watch.symbol)
                Text(watch.directory ?? "No folder selected.")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
                if let error = watch.error {
                    Text(error).font(.caption).foregroundStyle(.orange).lineLimit(4).help(error)
                }
            }
            Divider()
            if let snapshot = model.snapshot, snapshot.query == query {
                summary(snapshot)
            } else if model.errorMessage == nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Reading imported usage…")
                }
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(4).help(error)
                if model.snapshot?.query == query {
                    Text("Showing the last available report.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let actions { controls(actions) }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: query) { await model.observe(query: query) }
    }

    private func controls(_ actions: MenuSummaryActions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Button("Open Window", action: actions.openWindow)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: actions.refresh)
                    .disabled(model.isRefreshing || watch.isBusy)
            }
            HStack {
                if watch.isRunning {
                    Button(watch.isPaused ? "Resume Watch" : "Pause Watch", action: actions.togglePause)
                    Button("Stop Watch", action: actions.stopWatch)
                } else {
                    Button("Watch Folder…", systemImage: "folder", action: actions.startWatch)
                }
            }
            .disabled(watch.isBusy)
            HStack {
                Button("Settings…", action: actions.openSettings)
                Spacer()
                Button("Quit SessionMonitor", action: actions.quit)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func summary(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scopeLabel)
                .font(.subheadline).foregroundStyle(.secondary)
            if snapshot.report.totals.requests == 0 {
                Text("No canonical usage yet")
                    .font(.headline)
                Text("Choose Watch Folder… or import from the main window.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LabeledContent("Requests", value: snapshot.report.totals.requests.formatted())
                LabeledContent("Input tokens", value: snapshot.report.totals.inputTokens.formatted())
                LabeledContent("Output tokens", value: snapshot.report.totals.outputTokens.formatted())
                LabeledContent("Known cached input", value: snapshot.report.totals.cachedInputTokens.formatted())
            }
            Divider()
            LabeledContent("Cache coverage", value: snapshot.coverage.cache.rawValue.capitalized)
            Text("Known for \(snapshot.coverage.knownCacheRequests.formatted()) of "
                 + "\(snapshot.report.totals.requests.formatted()) requests")
                .font(.caption).foregroundStyle(.secondary)
            if let committedAt = snapshot.watermark.committedAt {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last index update (local time)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(committedAt, format: .dateTime.year().month().day().hour().minute().second())
                        .font(.caption)
                }
            } else {
                Text("No index update recorded")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Canonical usage only. Index time does not prove source freshness.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .monospacedDigit()
    }
}

private func menuPageDefaultUsageQuery() -> UsageQuery {
    do {
        return try UsageQuery()
    } catch {
        preconditionFailure("The built-in UTC query must be valid: \(error)")
    }
}
