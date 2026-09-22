import Foundation
import MonitorCore
import SwiftUI

struct QuotaPresentationSection: View {
    let report: QuotaPresentationReport?

    var body: some View {
        Section("Quota telemetry") {
            if let report {
                QuotaCoverageSummary(report: report)
                if report.windows.isEmpty {
                    Text(emptyMessage(for: report.coverage.unknownReason))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.windows) { window in
                        QuotaWindowRow(window: window, timeZoneIdentifier: report.query.timeZoneIdentifier)
                    }
                }
            } else {
                Text("Quota telemetry is unavailable for this snapshot.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emptyMessage(for reason: UsageLimitTelemetryUnknownReason?) -> String {
        switch reason {
        case .noSnapshotInPeriod:
            "No quota event was observed in the selected period."
        case .unsupportedSchema:
            "Quota events were observed, but their schema is unsupported."
        case .noWindowData:
            "Quota events were observed, but no supported window data was available."
        case nil:
            "No supported quota window is available."
        }
    }
}

private struct QuotaCoverageSummary: View {
    let report: QuotaPresentationReport

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent("Coverage", value: report.coverage.state.rawValue)
            LabeledContent("Windows", value: report.coverage.supportedWindowObservations.formatted())
            if let latest = report.coverage.latestObservedAt {
                LabeledContent("Latest observation", value: latest.formatted(date: .abbreviated, time: .shortened))
            }
            if let reason = report.coverage.unknownReason {
                LabeledContent("Unknown reason", value: reason.rawValue)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quota telemetry coverage")
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindowPresentation
    let timeZoneIdentifier: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Text(windowTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(usedValue)
                    .font(.headline.monospacedDigit())
            }
            LabeledContent("Remaining", value: remainingValue)
            LabeledContent("Freshness", value: freshnessLabel)
            LabeledContent("Reset", value: resetValue)
            if window.isResetDiscontinuity {
                Label("Reset discontinuity", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            }
            if window.isAmbiguous {
                Label("Conflicting observations at the same timestamp", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var windowTitle: String {
        let identity = window.limitName ?? window.limitID ?? "Unnamed limit"
        return "\(identity) · \(window.windowKind.rawValue)"
    }

    private var usedValue: String {
        window.usedPercent.map { $0.formatted(.number.precision(.fractionLength(1))) + "% used" } ?? "Unknown"
    }

    private var remainingValue: String {
        window.remainingPercent.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "Unknown"
    }

    private var freshnessLabel: String {
        switch window.freshness.state {
        case .current: "Current"
        case .stale: "Stale"
        case .future: "Future timestamp"
        case .unknown: "Unknown"
        }
    }

    private var resetValue: String {
        guard let reset = window.resetsAt else { return "Unknown" }
        var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        format.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return reset.formatted(format)
    }

    private var accessibilityLabel: String {
        "\(windowTitle), \(usedValue), remaining \(remainingValue), "
            + "freshness \(freshnessLabel), reset \(resetValue)"
    }
}
