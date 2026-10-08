import Foundation
import MonitorCore
import Observation

/// Where the panel reads findings and alerts: the same runtime calls the CLI makes (`doctor`, `alerts`).
protocol FindingsAlertsSource: Sendable {
    func diagnosticReport(query: UsageQuery) async throws -> DiagnosticReport
    func alertRecords(status: AlertStatus?) async throws -> [AlertRecord]
}

@MainActor
@Observable
final class FindingsAlertsModel {
    enum Tab: String, CaseIterable, Identifiable {
        case findings = "Findings"
        case alerts = "Alerts"
        var id: String { rawValue }
    }

    var tab: Tab = .findings
    /// `nil` shows every kind, like `doctor --json`.
    var kindFilter: String?
    /// `nil` shows active and resolved alerts, like `alerts --status all --json`.
    var alertStatusFilter: AlertStatus?
    private(set) var report: DiagnosticReport?
    private(set) var alertRecords: [AlertRecord] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false

    var kinds: [String] { FindingsAlertsPresentation.kinds(in: report?.findings ?? []) }

    var visibleFindings: [DiagnosticFinding] {
        FindingsAlertsPresentation.findings(report?.findings ?? [], kind: kindFilter)
    }

    var visibleAlerts: [AlertRecord] {
        FindingsAlertsPresentation.alerts(alertRecords, status: alertStatusFilter)
    }

    var summary: String {
        FindingsAlertsPresentation.summary(findings: report?.findings.count ?? 0, alerts: alertRecords.count)
    }

    /// Reads both lists for `query`. A failed read keeps the previous lists and names the problem.
    func load(query: UsageQuery, source: any FindingsAlertsSource) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let diagnostics = source.diagnosticReport(query: query)
            async let alerts = source.alertRecords(status: nil)
            let (newReport, newAlerts) = try await (diagnostics, alerts)
            guard !Task.isCancelled else { return }
            report = newReport
            alertRecords = newAlerts
            errorMessage = nil
            if let kindFilter, !kinds.contains(kindFilter) { self.kindFilter = nil }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Could not load findings. \(error.localizedDescription)"
        }
    }
}
