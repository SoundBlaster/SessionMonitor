import MonitorCore
import SwiftUI

/// Findings and alerts for the selected period and account scope, with their evidence.
struct FindingsAlertsPanel: View {
    @Bindable var model: FindingsAlertsModel
    let canOpenSession: (String) -> Bool
    let openSession: (String) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("findings.error")
            }
            switch model.tab {
            case .findings: findingsList
            case .alerts: alertsList
            }
        }
        .padding()
        .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("View", selection: $model.tab) {
                    ForEach(FindingsAlertsModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
            HStack {
                filter
                Spacer()
                Text(model.summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var filter: some View {
        switch model.tab {
        case .findings:
            Picker("Kind", selection: $model.kindFilter) {
                Text("All kinds").tag(String?.none)
                ForEach(model.kinds, id: \.self) { kind in
                    Text(FindingsAlertsPresentation.kindTitle(kind)).tag(String?.some(kind))
                }
            }
            .frame(maxWidth: 280)
        case .alerts:
            Picker("Status", selection: $model.alertStatusFilter) {
                Text("Active and resolved").tag(AlertStatus?.none)
                Text("Active").tag(AlertStatus?.some(.active))
                Text("Resolved").tag(AlertStatus?.some(.resolved))
            }
            .frame(maxWidth: 280)
        }
    }

    private var findingsList: some View {
        List(model.visibleFindings) { finding in
            FindingRow(
                symbol: FindingsAlertsPresentation.symbol(finding.severity),
                title: finding.title,
                subtitle: FindingsAlertsPresentation.kindTitle(FindingsAlertsPresentation.kind(of: finding)),
                detail: finding.explanation,
                footnotes: ["Confidence: \(finding.confidence.rawValue)"]
                    + (FindingsAlertsPresentation.coverageText(finding.coverage).map { [$0] } ?? []),
                nextAction: finding.suggestedNextAction,
                evidence: finding.evidence,
                sessions: finding.affectedSessions,
                canOpenSession: canOpenSession,
                openSession: openSession
            )
        }
        .overlay {
            if model.visibleFindings.isEmpty && !model.isLoading {
                ContentUnavailableView("No session diagnostic findings", systemImage: "checkmark.circle")
            }
        }
        .accessibilityIdentifier("findings.list")
    }

    private var alertsList: some View {
        List(model.visibleAlerts) { record in
            let alert = record.candidate
            FindingRow(
                symbol: FindingsAlertsPresentation.symbol(alert.severity),
                title: alert.title,
                subtitle: "\(record.status.rawValue.capitalized) · \(alert.source.rawValue)/\(alert.kind)",
                detail: alert.message,
                footnotes: alertFootnotes(record),
                nextAction: nil,
                evidence: alert.evidence,
                sessions: alert.sessionIDs,
                canOpenSession: canOpenSession,
                openSession: openSession
            )
        }
        .overlay {
            if model.visibleAlerts.isEmpty && !model.isLoading {
                ContentUnavailableView("No alerts", systemImage: "bell.slash")
            }
        }
        .accessibilityIdentifier("alerts.list")
    }

    private func alertFootnotes(_ record: AlertRecord) -> [String] {
        var notes = [
            "Raised \(record.raisedAt.formatted(date: .abbreviated, time: .shortened))",
            "\(record.occurrences) occurrence\(record.occurrences == 1 ? "" : "s")"
        ]
        if let resolvedAt = record.resolvedAt {
            notes.append("Resolved \(resolvedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if let coverage = FindingsAlertsPresentation.coverageText(record.candidate.coverage) { notes.append(coverage) }
        return notes
    }
}
