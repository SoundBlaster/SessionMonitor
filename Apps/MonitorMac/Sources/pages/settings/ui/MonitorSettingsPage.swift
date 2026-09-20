import MonitorCore
import SwiftUI

struct MonitorSettingsPage: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage(UsageChartPaletteSelection.storageKey)
    private var chartPaletteRawValue = UsageChartPaletteSelection.system.rawValue
    @Bindable var cacheHitRateWidgetSettings: CacheHitRateWidgetSettings

    var body: some View {
        Form {
            Toggle("Show SessionMonitor in the menu bar", isOn: $showMenuBarExtra)
            Picker("Cache Hit Rate widget period", selection: Binding(
                get: { cacheHitRateWidgetSettings.period },
                set: { cacheHitRateWidgetSettings.selectPeriod($0) }
            )) {
                Text("Last 24 hours").tag(CacheHitRateWidgetPeriod.last24Hours)
                Text("Last 7 days").tag(CacheHitRateWidgetPeriod.last7Days)
                Text("Last 14 days").tag(CacheHitRateWidgetPeriod.last14Days)
                Text("Last 30 days").tag(CacheHitRateWidgetPeriod.last30Days)
            }
            Picker("Analytics chart colors", selection: $chartPaletteRawValue) {
                ForEach(UsageChartPaletteSelection.allCases) { selection in
                    Text(selection.title).tag(selection.rawValue)
                }
            }
            .accessibilityIdentifier("settings.analyticsChartPalette")
            Text("Hiding the icon or closing a window does not stop an active watch. "
                 + "Use Stop Watch or Quit SessionMonitor to stop it.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 440, height: 260)
    }
}
