import MonitorPolicies
import SwiftUI

struct SessionReportInspector: View {
    let model: SessionExplorerModel

    var body: some View {
        Form {
            Section("Report scope") {
                LabeledContent("Timezone", value: model.query.timeZoneIdentifier)
                LabeledContent("From") {
                    queryBoundary(model.query.since, fallback: "Beginning of imported history")
                }
                LabeledContent("Until") {
                    queryBoundary(model.query.until, fallback: "No upper bound")
                }
                Text("The period is absolute and half-open: the start is included and the end is excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Report coverage") {
                Text("Selected period")
                    .font(.headline)
                Text("Canonical records are counted. Legacy token_count entries are not included.")
                    .foregroundStyle(.secondary)
                LabeledContent("Requests", value: model.report.totals.requests.formatted())
                LabeledContent("Unknown cache", value: model.report.totals.unknownCacheRequests.formatted())
                if let finding = CacheCoverageDecision().decide(model.report.totals) {
                    Text(finding).font(.callout).foregroundStyle(.secondary)
                }
            }

            QuotaPresentationSection(report: model.quotaPresentationReport)

            if let session = model.selectedSession {
                Section("Selection") {
                    if let provenance = model.provenance[session.id] {
                        LabeledContent("Display name", value: provenance.displayName ?? "Unknown")
                        LabeledContent("Origin", value: provenance.originator ?? "Unknown")
                        LabeledContent("Client", value: provenance.clientVersion ?? "Unknown")
                        LabeledContent("Relationship",
                                       value: provenance.relationship.map { $0.kind.rawValue } ?? "Unknown")
                    }
                    LabeledContent("Model", value: session.model)
                    Text(session.id)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let directory = model.importedDirectory {
                Section("Import source") {
                    Text(directory.path(percentEncoded: false))
                        .font(.caption)
                        .textSelection(.enabled)
                    Text("Update imports new and changed JSONL files from this folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Service diagnostics") {
                Text("Import diagnostics are database-wide counters for the selected store. "
                    + "They are not attributed to the selected session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func queryBoundary(_ date: Date?, fallback: String) -> some View {
        if let date {
            Text(date.formatted(queryDateFormat)).monospacedDigit()
        } else {
            Text(fallback).foregroundStyle(.secondary)
        }
    }

    private var queryDateFormat: Date.FormatStyle {
        var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        format.timeZone = TimeZone(identifier: model.query.timeZoneIdentifier) ?? .gmt
        return format
    }
}
