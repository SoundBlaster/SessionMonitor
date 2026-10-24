import MonitorCore
import SwiftUI

/// Source storage is metadata for the whole imported session, separate from period-scoped usage totals.
struct SessionStorageSection: View {
    let storage: SessionStorageSummary?

    var body: some View {
        Section("Session files") {
            if let storage {
                LabeledContent("Source size") { Text(formattedSize(storage)).monospaced() }
                    .accessibilityIdentifier("sessionInspector.sourceStorage.size")
                LabeledContent("Bytes") { Text(byteCount(storage)).monospaced() }
                LabeledContent("Imported files") { Text(storage.fileCount.formatted()).monospaced() }
                if storage.unknownSizeFileCount > 0 {
                    LabeledContent("Unknown size") { Text(storage.unknownSizeFileCount.formatted()).monospaced() }
                }
                if let modified = storage.lastModifiedAt {
                    LabeledContent("Last source change") {
                        Text(modified.formatted(date: .abbreviated, time: .shortened)).monospaced()
                    }
                }
            } else {
                Text("Size unknown. Update or reimport the source folder to measure it.")
                    .foregroundStyle(.secondary)
            }
            Text("Whole imported source logs, measured at import. Copies count separately; hard links count once. "
                 + "Excludes subagents and unimported files. This is file length, not reclaimable disk space; "
                 + "the selected period does not reduce it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedSize(_ storage: SessionStorageSummary) -> String {
        let value = ByteCountFormatter.string(fromByteCount: storage.knownBytes, countStyle: .file)
        return storage.totalBytes == nil ? "≥\(value) · partial" : value
    }

    private func byteCount(_ storage: SessionStorageSummary) -> String {
        let value = storage.knownBytes.formatted()
        return storage.totalBytes == nil ? "≥\(value)" : value
    }
}
