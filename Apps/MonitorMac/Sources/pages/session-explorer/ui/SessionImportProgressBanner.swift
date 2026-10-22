import SwiftUI
import MonitorCore

struct SessionImportProgressBanner: View {
    let progress: ImportProgress
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
            HStack(alignment: .firstTextBaseline) {
                Label("Importing session files", systemImage: "tray.and.arrow.down.fill")
                    .font(.headline)
                Spacer(minLength: DesignTokens.Spacing.item)
                Button("Stop import", systemImage: "stop.fill", action: cancel)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("sessionExplorer.importProgress.cancel")
            }
            if let fileName = progress.currentFileName {
                HStack(alignment: .firstTextBaseline) {
                    Text("Reading \(fileName)")
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: DesignTokens.Spacing.item)
                    if let size = progress.currentFileSize {
                        Text("\(byteCount(progress.currentFileBytesProcessed)) of \(byteCount(size))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ProgressView(value: Double(progress.completedFiles), total: Double(max(progress.totalFiles, 1)))
            Text("\(progress.completedFiles) of \(progress.totalFiles) files completed. "
                 + "Completed files are saved as they finish.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionExplorer.importProgress")
    }

    private func byteCount(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(min(value, UInt64(Int64.max))), countStyle: .file)
    }
}
