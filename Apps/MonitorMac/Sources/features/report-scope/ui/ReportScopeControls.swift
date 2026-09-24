import NestedA11yIDs
import SwiftUI

struct ReportScopeControls: View {
    @Bindable var model: ReportScopeModel
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            Label(model.compactLabel, systemImage: "calendar.badge.clock")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help("Choose the account, report period and presentation timezone")
        .accessibilityLabel("Account, report period and timezone")
        .accessibilityValue(model.compactLabel)
        .accessibilityIdentifier("sessionExplorer.accountScope")
        .onChange(of: showsPopover) { _, isPresented in
            if isPresented { Task { await model.refreshProfiles() } }
        }
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            scopePopover
        }
    }

    private var scopePopover: some View {
        Form {
            VStack(alignment: .leading, spacing: 6) {
                Text("Account")
                    .font(.headline)
                AccountScopeOptionRow(
                    title: "All accounts",
                    isSelected: model.accountSelection == .allAccounts
                ) { model.selectAccount(.allAccounts) }
                ForEach(model.profiles) { profile in
                    let sourceNote = profile.hasMixedSources
                        ? " · \(profile.assignedSourceCount) assigned, \(profile.mixedSourceCount) mixed"
                        : (profile.sourceCount > 1 ? " · \(profile.sourceCount) sources" : "")
                    AccountScopeOptionRow(
                        title: profile.label + sourceNote,
                        isSelected: model.accountSelection == .profile(profile.id),
                        isEnabled: profile.isSelectable,
                        detail: profile.isSelectable ? nil : "Unavailable"
                    ) { model.selectAccount(.profile(profile.id)) }
                }
                AccountScopeOptionRow(
                    title: "Unknown/Mixed",
                    isSelected: model.accountSelection == .unknownOrMixed
                ) { model.selectAccount(.unknownOrMixed) }
            }
            if model.profiles.isEmpty && model.profileCatalogError == nil {
                Text("No assigned account profiles. Profile mapping is managed by the CLI.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.profileCatalogError {
                Text("Could not load account profiles: \(error)")
                    .font(.caption).foregroundStyle(.orange)
            }
            if model.selectedProfileIsUnavailable {
                VStack(alignment: .leading, spacing: 6) {
                    Label("This profile's sources are now mixed.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Its report excludes mixed data. Switch to Unknown/Mixed to inspect it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Show Unknown/Mixed") { model.selectAccount(.unknownOrMixed) }
                }
            }
            if model.selectedProfileHasMixedSources {
                VStack(alignment: .leading, spacing: 6) {
                    Label("This profile has incomplete source coverage.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("\(model.selectedProfileMixedSourceCount) mixed source roots are excluded from its report.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Show Unknown/Mixed") { model.selectAccount(.unknownOrMixed) }
                }
            }

            Picker("Period", selection: Binding(
                get: { model.preset },
                set: { model.selectPreset($0) }
            )) {
                ForEach(ReportScopeModel.PeriodPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.radioGroup)

            Picker("Timezone", selection: Binding(
                get: { model.timeZoneIdentifier },
                set: { model.selectTimeZone($0) }
            )) {
                ForEach(model.timeZoneIdentifiers, id: \.self) { identifier in
                    Text(timeZoneTitle(identifier)).tag(identifier)
                }
            }
            .pickerStyle(.radioGroup)

            LabeledContent("Resolved start") {
                if let since = model.query.since {
                    Text(since.formatted(resolvedDateFormat))
                        .monospacedDigit()
                } else {
                    Text("Beginning of imported history")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Resolved end") {
                if let until = model.query.until {
                    Text(until.formatted(resolvedDateFormat))
                        .monospacedDigit()
                } else {
                    Text("No upper bound")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Start included · End excluded")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 360)
        .frame(minHeight: 440)
    }

    private var resolvedDateFormat: Date.FormatStyle {
        var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        format.timeZone = TimeZone(identifier: model.timeZoneIdentifier) ?? .gmt
        return format
    }

    private func timeZoneTitle(_ identifier: String) -> String {
        identifier == "UTC" ? "UTC" : "Local — \(identifier)"
    }
}

private struct AccountScopeOptionRow: View {
    let title: String
    let isSelected: Bool
    var isEnabled = true
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : (isEnabled ? "Not selected" : detail ?? "Unavailable"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
