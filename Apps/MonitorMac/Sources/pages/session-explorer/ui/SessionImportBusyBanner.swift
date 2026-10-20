import SwiftUI

/// Recovery guidance does not claim to know which process currently owns the database lease.
struct SessionImportBusyBanner: View {
    let directory: URL
    let isBusy: Bool
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
            HStack(alignment: .firstTextBaseline) {
                Label("Database in use", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Spacer(minLength: DesignTokens.Spacing.item)
                Button("Dismiss import help", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly).buttonStyle(.plain)
            }
            Text("Could not import “\(directory.lastPathComponent)”.")
                .font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Watch in this app can hold the database, even while paused. "
                 + "Another SessionMonitor instance, CLI Watch, or import can also hold it.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.inline) {
                Text("1. Open the SessionMonitor menu bar menu and choose Stop Watch.")
                Text("2. Wait for Watch to stop, then retry this folder.")
            }
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Retry Import", action: retry)
                    .buttonStyle(.bordered).disabled(isBusy)
                    .accessibilityIdentifier("sessionExplorer.importBusy.retry")
                Text("Pause Watch keeps the database reserved.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("If the database is still busy") {
                Text("Stop Watch in any other SessionMonitor instance or stop codex-monitor watch with Control-C. "
                     + "If another import is running, let it finish. Retry uses this same folder; "
                     + "your existing report is kept when an import cannot start.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.top, DesignTokens.Spacing.item)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionExplorer.importBusy")
    }
}
