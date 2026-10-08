import MonitorCore
import SwiftUI

/// One finding or alert: what was found, how sure we are, the evidence split into observed, inferred and
/// unknown, and a way to the affected sessions' timelines.
struct FindingRow: View {
    let symbol: String
    let title: String
    let subtitle: String
    let detail: String
    let footnotes: [String]
    let nextAction: String?
    let evidence: DiagnosticEvidence
    let sessions: [String]
    let canOpenSession: (String) -> Bool
    let openSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: symbol)
            }
            Text(detail)
            if !footnotes.isEmpty {
                Text(footnotes.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            if let nextAction, !nextAction.isEmpty {
                Text("Next: \(nextAction)").font(.callout)
            }
            if hasEvidence {
                DisclosureGroup("Evidence") { evidenceBody }
            }
            if !sessions.isEmpty { sessionLinks }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var hasEvidence: Bool {
        !(evidence.observed.isEmpty && evidence.inference.isEmpty && evidence.unknown.isEmpty
            && evidence.limitations.isEmpty)
    }

    private var evidenceBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            evidenceSection("Observed", evidence.observed.map(\.detail))
            evidenceSection("Inference", evidence.inference.map(\.detail))
            evidenceSection("Unknown", evidence.unknown.map(\.detail))
            evidenceSection("Limitations", evidence.limitations)
        }
        .font(.caption)
    }

    @ViewBuilder
    private func evidenceSection(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                ForEach(lines, id: \.self) { Text($0).foregroundStyle(.secondary) }
            }
        }
    }

    private var sessionLinks: some View {
        HStack {
            ForEach(sessions.prefix(3), id: \.self) { id in
                Button("Open \(id.prefix(8))…", systemImage: "timeline.selection") { openSession(id) }
                    .controlSize(.small)
                    .disabled(!canOpenSession(id))
                    .help(canOpenSession(id) ? "Show this session and its timeline"
                          : "This session is not in the current report")
            }
            if sessions.count > 3 {
                Text("+\(sessions.count - 3) more").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
