import CodexSource
import Foundation
import MonitorCore

extension SessionMonitor {
    func readSource(
        _ path: URL, source: String, checkpoint: Data?, rescan: Bool,
        progress: SourceReadProgressContext
    ) throws -> SourceReadResult {
        let decoder = RolloutDecoder()
        var metadataBytesRead: UInt64 = 0
        if !rescan, let checkpoint, try store.needsProvenanceBackfill(source: source) {
            do {
                if let metadata = try decoder.parseMetadata(
                    path, matching: checkpoint, onProgress: progress.report
                ) {
                    metadataBytesRead = metadata.bytesRead
                    _ = try store.backfillProvenance(source: source, update: metadata,
                                                     expectedCheckpoint: checkpoint)
                }
            } catch RolloutReadError.sourceChanged {
                throw ImportSourceError.changedWhileReading(fileName: path.lastPathComponent,
                                                            completedFiles: progress.completedFiles,
                                                            totalFiles: progress.totalFiles)
            }
        }
        let currentCheckpoint = try store.checkpoint(source: source)
        do {
            let update = try decoder.parseIncrementally(
                path, checkpoint: rescan ? nil : currentCheckpoint, onProgress: progress.report
            )
            return SourceReadResult(update: update, checkpoint: currentCheckpoint,
                                    metadataBytesRead: metadataBytesRead)
        } catch RolloutReadError.sourceChanged {
            throw ImportSourceError.changedWhileReading(fileName: path.lastPathComponent,
                                                        completedFiles: progress.completedFiles,
                                                        totalFiles: progress.totalFiles)
        }
    }
}

struct SourceReadProgressContext {
    let completedFiles: Int
    let totalFiles: Int
    let report: @Sendable (UInt64, UInt64) -> Void
}

struct SourceReadResult {
    let update: SourceImport
    let checkpoint: Data?
    let metadataBytesRead: UInt64
}
