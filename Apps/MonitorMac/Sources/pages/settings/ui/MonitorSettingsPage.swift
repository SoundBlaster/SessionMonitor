import SwiftUI

struct MonitorSettingsPage: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some View {
        Form {
            Toggle("Show SessionMonitor in the menu bar", isOn: $showMenuBarExtra)
            Text("Hiding the icon or closing a window does not stop an active watch. "
                 + "Use Stop Watch or Quit SessionMonitor to stop it.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
    }
}
