import MonitorCore
import SwiftUI

struct MenuSummaryPage: View {
    let model: MenuSummaryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("SessionMonitor", systemImage: "chart.bar.xaxis")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Label("Watch: not managed by this app", systemImage: "questionmark.circle")
                Text("External watch status is unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            if let snapshot = model.snapshot {
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
                if model.snapshot != nil {
                    Text("Showing the last available report.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .task { await model.observe() }
    }

    private func summary(_ snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All imported time · \(snapshot.query.timeZoneIdentifier)")
                .font(.subheadline).foregroundStyle(.secondary)
            if snapshot.report.totals.requests == 0 {
                Text("No canonical usage yet")
                    .font(.headline)
                Text("Import a rollout folder from the main window.")
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
