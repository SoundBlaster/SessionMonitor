import MonitorCore
import NestedA11yIDs
import SwiftUI

struct MonitorSettingsPage: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage(WatchLaunchSettings.startOnLaunchKey) private var watchOnLaunch = true
    @AppStorage(UsageChartPaletteSelection.storageKey)
    private var chartPaletteRawValue = UsageChartPaletteSelection.system.rawValue
    @Bindable var cacheHitRateWidgetSettings: CacheHitRateWidgetSettings
    var sharedIndex: SharedIndexLocationModel?

    var body: some View {
        Form {
            if let sharedIndex { SharedIndexSettingsSection(model: sharedIndex) }
            GeneralSettingsSection(showMenuBarExtra: $showMenuBarExtra, watchOnLaunch: $watchOnLaunch)
            AnalyticsSettingsSection(period: Binding(
                get: { cacheHitRateWidgetSettings.period },
                set: { cacheHitRateWidgetSettings.selectPeriod($0) }
            ), palette: $chartPaletteRawValue)
        }
        .formStyle(.grouped)
        .tint(.blue)
        .frame(width: 580, height: sharedIndex == nil ? 370 : 590)
    }
}

private struct GeneralSettingsSection: View {
    @Binding var showMenuBarExtra: Bool
    @Binding var watchOnLaunch: Bool

    var body: some View {
        Section {
            Toggle("Show in menu bar", isOn: $showMenuBarExtra)
                .accessibilityIdentifier("settings.showMenuBarExtra")
            Toggle(isOn: $watchOnLaunch) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.micro) {
                    Text("Resume watching at launch")
                    Text("Continue watching the last selected folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityLabel("Resume watching at launch")
            .accessibilityHint("Continue watching the last selected folder.")
            .accessibilityIdentifier("settings.watchOnLaunch")
        } header: {
            Text("General")
        } footer: {
            Text("""
                 Watching continues when windows are closed or the menu bar icon is hidden. \
                 To stop, choose Stop Watch or quit SessionMonitor.
                 """)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.switch)
    }
}

private struct AnalyticsSettingsSection: View {
    @Binding var period: CacheHitRateWidgetPeriod
    @Binding var palette: String

    var body: some View {
        Section("Analytics") {
            LabeledContent("Cache hit rate widget period") {
                Picker("Cache hit rate widget period", selection: $period) {
                    Text("Last 24 hours").tag(CacheHitRateWidgetPeriod.last24Hours)
                    Text("Last 7 days").tag(CacheHitRateWidgetPeriod.last7Days)
                    Text("Last 14 days").tag(CacheHitRateWidgetPeriod.last14Days)
                    Text("Last 30 days").tag(CacheHitRateWidgetPeriod.last30Days)
                }
                .labelsHidden()
                .frame(width: 170, alignment: .trailing)
                .accessibilityIdentifier("settings.cacheWidgetPeriod")
            }
            LabeledContent("Chart colors") {
                Picker("Analytics chart colors", selection: $palette) {
                    ForEach(UsageChartPaletteSelection.allCases) { selection in
                        Text(selection.title).tag(selection.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 170, alignment: .trailing)
                .accessibilityIdentifier("settings.analyticsChartPalette")
            }
        }
    }
}
