import Foundation
import MonitorCore
import SwiftUI

struct QuotaPresentationSection: View {
    let report: QuotaPresentationReport?

    var body: some View {
        Section("Quota telemetry") {
            if let report {
                let unknownScopeLabels = unknownScopeLabels(for: report)
                if report.accountCoverages.isEmpty && report.windows.isEmpty {
                    QuotaCoverageSummary(coverage: report.coverage,
                                         timeZoneIdentifier: report.query.timeZoneIdentifier)
                    Text(emptyMessage(for: report.coverage.unknownReason))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accountGroups(report)) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.coverages) { scopedCoverage in
                                QuotaCoverageSummary(
                                    coverage: scopedCoverage.coverage,
                                    timeZoneIdentifier: report.query.timeZoneIdentifier,
                                    detail: group.isUnknown
                                        ? unknownScopeDetail(
                                            scopedCoverage.accountScopeID,
                                            state: scopedCoverage.accountScopeState.rawValue,
                                            labels: unknownScopeLabels
                                        )
                                        : nil
                                )
                            }
                            if group.windows.isEmpty {
                                Text(emptyMessage(for: group.coverages.first?.coverage.unknownReason))
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(group.windows) { window in
                                    QuotaWindowRow(window: window,
                                                   timeZoneIdentifier: report.query.timeZoneIdentifier,
                                                   accountScopeLabel: group.isUnknown
                                                    ? unknownScopeLabels[scopeKey(window.accountScopeID)]
                                                    : nil)
                                }
                            }
                        }
                        .padding(.vertical, 6)
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

    private func accountGroups(_ report: QuotaPresentationReport) -> [QuotaAccountGroup] {
        let profileIDs = Set(report.accountCoverages.compactMap(\.accountProfileID)
            + report.windows.compactMap(\.accountProfileID))
        let profiles = profileIDs.map { id in
            QuotaAccountGroup(
                id: "profile:\(id)",
                title: report.accountCoverages.first(where: { $0.accountProfileID == id })?.accountProfileLabel
                    ?? report.windows.first(where: { $0.accountProfileID == id })?.accountProfileLabel ?? id,
                isUnknown: false,
                coverages: report.accountCoverages.filter { $0.accountProfileID == id },
                windows: report.windows.filter { $0.accountProfileID == id }
            )
        }
        let unknownCoverages = report.accountCoverages.filter { $0.accountProfileID == nil }
        let unknownWindows = report.windows.filter { $0.accountProfileID == nil }
        let unknown = unknownCoverages.isEmpty && unknownWindows.isEmpty ? [] : [QuotaAccountGroup(
            id: "unknown-mixed", title: "Unknown/Mixed", isUnknown: true,
            coverages: unknownCoverages,
            windows: unknownWindows.sorted {
                if $0.accountScopeID != $1.accountScopeID {
                    return ($0.accountScopeID ?? "") < ($1.accountScopeID ?? "")
                }
                return $0.id < $1.id
            }
        )]
        return (profiles + unknown).sorted {
            let comparison = $0.title.localizedCaseInsensitiveCompare($1.title)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    private func unknownScopeLabels(for report: QuotaPresentationReport) -> [String: String] {
        let scopeKeys = Set(
            report.accountCoverages.filter { $0.accountProfileID == nil }.map { scopeKey($0.accountScopeID) }
                + report.windows.filter { $0.accountProfileID == nil }.map { scopeKey($0.accountScopeID) }
        ).sorted()
        return Dictionary(uniqueKeysWithValues: scopeKeys.enumerated().map { index, key in
            (key, "Unknown scope \(index + 1)")
        })
    }

    private func scopeKey(_ scopeID: String?) -> String { scopeID ?? "no-scope" }

    private func unknownScopeDetail(
        _ scopeID: String?,
        state: String,
        labels: [String: String]
    ) -> String {
        let label = labels[scopeKey(scopeID)] ?? "Unknown scope"
        return "\(label) · \(state.capitalized)"
    }
}

private struct QuotaCoverageSummary: View {
    let coverage: UsageLimitTelemetryCoverage
    let timeZoneIdentifier: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent("Coverage", value: coverage.state.rawValue.capitalized)
            LabeledContent("Windows", value: coverage.supportedWindowObservations.formatted())
            if let detail { LabeledContent("Scope", value: detail) }
            if let latest = coverage.latestObservedAt {
                LabeledContent("Latest observation", value: latest.formatted(dateFormat))
            }
            if let reason = coverage.unknownReason {
                LabeledContent("Unknown reason", value: reason.rawValue)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(detail.map { "Quota telemetry coverage, \($0)" } ?? "Quota telemetry coverage")
    }

    private var dateFormat: Date.FormatStyle {
        var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        format.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return format
    }
}

private struct QuotaAccountGroup: Identifiable {
    let id: String
    let title: String
    let isUnknown: Bool
    let coverages: [QuotaAccountCoverage]
    let windows: [QuotaWindowPresentation]
}

private struct QuotaWindowRow: View {
    let window: QuotaWindowPresentation
    let timeZoneIdentifier: String
    var accountScopeLabel: String?
    @State private var isShowingResetDetails = false

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
            if window.accountProfileID == nil {
                LabeledContent(
                    "Account scope",
                    value: "\(accountScopeLabel ?? "Unknown/Mixed") · "
                        + window.accountScopeState.rawValue.capitalized
                )
            }
            LabeledContent("Freshness", value: freshnessLabel)
            LabeledContent("Reset", value: resetValue)
            if window.isResetDiscontinuity {
                Button("Reset discontinuity") {
                    isShowingResetDetails.toggle()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.15), in: Capsule())
                .buttonStyle(.plain)
                .accessibilityHint("Shows why the reset boundary changed and compares usage before and after it.")
                .popover(isPresented: $isShowingResetDetails, arrowEdge: .leading) {
                    ResetDiscontinuityPopover(
                        transition: window.resetDiscontinuity,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                }
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

private struct ResetDiscontinuityPopover: View {
    let transition: QuotaResetDiscontinuity?
    let timeZoneIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quota reset changed")
                .font(.headline)
            Text("The source reported a new reset boundary for this quota window. "
                + "Values before and after the boundary are separate quota cycles.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let transition {
                LabeledContent("Usage", value: percentageChange(
                    from: transition.previousUsedPercent, current: transition.currentUsedPercent
                ))
                LabeledContent("Remaining", value: percentageChange(
                    from: transition.previousRemainingPercent, current: transition.currentRemainingPercent
                ))
                LabeledContent("Reset", value: dateChange(
                    from: transition.previousResetsAt, current: transition.currentResetsAt
                ))
                LabeledContent("Observed", value: dateChange(
                    from: transition.previousObservedAt, current: transition.currentObservedAt
                ))
            } else {
                Text("The source marked a reset discontinuity, but did not provide enough "
                    + "paired observations to show the transition.")
                    .foregroundStyle(.secondary)
            }

            Text("Do not interpret the change as usage during one continuous window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 320, alignment: .leading)
    }

    private func percentageChange(from: Double?, current: Double?) -> String {
        "\(formatPercent(from)) → \(formatPercent(current))"
    }

    private func formatPercent(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "Unknown"
    }

    private func dateChange(from: Date, current: Date) -> String {
        "\(formatDate(from)) → \(formatDate(current))"
    }

    private func formatDate(_ date: Date) -> String {
        var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        format.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return date.formatted(format)
    }
}
