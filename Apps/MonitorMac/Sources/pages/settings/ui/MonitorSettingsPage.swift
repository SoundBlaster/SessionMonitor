import SwiftUI

struct MonitorSettingsPage: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @Bindable var cacheHitSettings: CacheHitThresholdSettings

    var body: some View {
        Form {
            Toggle("Show SessionMonitor in the menu bar", isOn: $showMenuBarExtra)
            HStack {
                Text("Minimum cache hit")
                Spacer()
                TextField("Percent", text: $cacheHitSettings.input)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onSubmit { _ = cacheHitSettings.commitInput() }
                Text("%")
            }
            if let validationMessage = cacheHitSettings.validationMessage {
                Text(validationMessage).font(.caption).foregroundStyle(.red)
            }
            Text("Known cache hit below this threshold is marked low. Unknown, partial, and zero-input "
                 + "data stay neutral.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Hiding the icon or closing a window does not stop an active watch. "
                 + "Use Stop Watch or Quit SessionMonitor to stop it.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 440, height: 220)
    }
}
