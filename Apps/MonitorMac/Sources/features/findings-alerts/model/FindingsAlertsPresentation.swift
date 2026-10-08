import Foundation
import MonitorCore

/// Pure display rules for findings and alerts. Nothing here drops or rewrites a finding: with no filter the
/// GUI shows exactly the set `doctor --json` and `alerts --status all --json` print.
enum FindingsAlertsPresentation {
    /// Findings from the anomaly policies carry `kind|sessions|responses|lines` as their id; store-level
    /// findings (such as `missing_provenance`) use the bare id.
    static func kind(of finding: DiagnosticFinding) -> String {
        String(finding.id.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    static func kinds(in findings: [DiagnosticFinding]) -> [String] {
        Array(Set(findings.map(kind(of:)))).sorted()
    }

    static func findings(_ findings: [DiagnosticFinding], kind: String?) -> [DiagnosticFinding] {
        guard let kind else { return findings }
        return findings.filter { self.kind(of: $0) == kind }
    }

    static func alerts(_ records: [AlertRecord], status: AlertStatus?) -> [AlertRecord] {
        guard let status else { return records }
        return records.filter { $0.status == status }
    }

    /// `repetitive_polling` reads as "Repetitive polling".
    static func kindTitle(_ kind: String) -> String {
        let words = kind.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func coverageText(_ coverage: AnomalyCoverage?) -> String? {
        switch coverage {
        case nil, .observed?: nil
        case let .partial(reason)?: "Partial coverage: \(reason)"
        case let .unknown(reason)?: "Unknown coverage: \(reason)"
        }
    }

    static func symbol(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    static func summary(findings: Int, alerts: Int) -> String {
        "\(findings) finding\(findings == 1 ? "" : "s") · \(alerts) alert\(alerts == 1 ? "" : "s")"
    }
}
