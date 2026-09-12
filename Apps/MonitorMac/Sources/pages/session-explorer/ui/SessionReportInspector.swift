import MonitorPolicies
import SwiftUI

struct SessionReportInspector: View {
    let model: SessionExplorerModel

    var body: some View {
        Form {
            Section("Report coverage") {
                Text("All imported sessions")
                    .font(.headline)
                Text("Canonical records are counted. Legacy token_count entries are not included.")
                    .foregroundStyle(.secondary)
                LabeledContent("Requests", value: model.report.totals.requests.formatted())
                LabeledContent("Unknown cache", value: model.report.totals.unknownCacheRequests.formatted())
                if let finding = CacheCoverageDecision().decide(model.report.totals) {
                    Text(finding).font(.callout).foregroundStyle(.secondary)
                }
            }

            if let session = model.selectedSession {
                Section("Selection") {
                    LabeledContent("Model", value: session.model)
                    Text(session.id)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let directory = model.importedDirectory {
                Section("Last imported folder in this window") {
                    Text(directory.path(percentEncoded: false))
                        .font(.caption)
                        .textSelection(.enabled)
                    Text("Refresh reads the stored report. Import the folder again to ingest new records.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Stored import diagnostics") {
                if model.report.diagnostics.isEmpty {
                    Text("No import diagnostics recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.report.diagnostics.keys.sorted(), id: \.self) { key in
                        LabeledContent {
                            Text((model.report.diagnostics[key] ?? 0).formatted())
                                .monospacedDigit()
                        } label: {
                            Text(key).font(.caption.monospaced())
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
