import SwiftUI

struct SessionImportChangedSourceBanner: View {
    let directory: URL
    let message: String
    let isBusy: Bool
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
            HStack(alignment: .firstTextBaseline) {
                Label("A session changed during import", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Spacer(minLength: DesignTokens.Spacing.item)
                Button("Dismiss import message", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly).buttonStyle(.plain)
            }
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text("Codex may still be writing an active session. Completed files remain imported; retrying this "
                 + "folder resumes from their checkpoints.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry Import", action: retry)
                .buttonStyle(.bordered)
                .disabled(isBusy)
                .accessibilityIdentifier("sessionExplorer.importChanged.retry")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionExplorer.importChanged")
        .help(directory.lastPathComponent)
    }
}
