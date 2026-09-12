import SwiftUI

struct ReportScopeControls: View {
    @Bindable var model: ReportScopeModel
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            Label(model.compactLabel, systemImage: "calendar.badge.clock")
        }
        .help("Choose the report period and presentation timezone")
        .accessibilityLabel("Report period and timezone")
        .accessibilityValue(model.compactLabel)
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            scopePopover
        }
    }

    private var scopePopover: some View {
        Form {
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
        .frame(minHeight: 360)
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
