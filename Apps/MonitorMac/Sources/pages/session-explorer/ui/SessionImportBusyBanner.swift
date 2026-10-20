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
            Text("Manual import stops Watch in this app first. "
                 + "Another SessionMonitor instance, CLI Watch, or import can still hold the database.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.inline) {
                Text("1. Let another import finish, or choose Stop Watch in the other SessionMonitor instance.")
                Text("2. Retry this folder after the other importer has stopped.")
            }
            .font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Retry Import", action: retry)
                    .buttonStyle(.bordered).disabled(isBusy)
                    .accessibilityIdentifier("sessionExplorer.importBusy.retry")
                Text("Pausing another Watch keeps the database reserved.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("If the database is still busy") {
                Text("Stop codex-monitor watch with Control-C. Watch in this app stays stopped after manual import. "
                     + "Retry uses this same folder; "
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
