import Foundation

/// Bounded, privacy-safe progress for one directory import. The file name is the basename only;
/// source contents and absolute paths are never included.
public struct ImportProgress: Equatable, Sendable {
    public let completedFiles: Int
    public let totalFiles: Int
    public let currentFileName: String?
    public let currentFileBytesProcessed: UInt64
    public let currentFileSize: UInt64?

    public init(completedFiles: Int, totalFiles: Int, currentFileName: String? = nil,
                currentFileBytesProcessed: UInt64 = 0, currentFileSize: UInt64? = nil) {
        self.completedFiles = max(0, completedFiles)
        self.totalFiles = max(0, totalFiles)
        self.currentFileName = currentFileName
        self.currentFileBytesProcessed = currentFileBytesProcessed
        self.currentFileSize = currentFileSize
    }
}

public enum ImportSourceError: Error, Equatable, LocalizedError {
    case changedWhileReading(fileName: String, completedFiles: Int, totalFiles: Int)

    public var errorDescription: String? {
        switch self {
        case let .changedWhileReading(fileName, completedFiles, totalFiles):
            "“\(fileName)” changed while it was being read. Its checkpoint was not advanced. "
                + "\(completedFiles) of \(totalFiles) earlier files are saved; retry when the source stops changing."
        }
    }
}

public enum SourceImportMode: String, Codable, Sendable {
    case unchanged, appended, replaced
}

/// One source transaction. Checkpoint bytes are owned and versioned by the source adapter.
public struct SourceImport: Sendable {
    public let rollout: ParsedRollout
    public let checkpoint: Data
    public let mode: SourceImportMode
    public let bytesRead: UInt64

    public init(rollout: ParsedRollout, checkpoint: Data, mode: SourceImportMode, bytesRead: UInt64) {
        self.rollout = rollout
        self.checkpoint = checkpoint
        self.mode = mode
        self.bytesRead = bytesRead
    }
}

public struct ImportIO: Codable, Equatable, Sendable {
    public var bytesRead: UInt64 = 0
    public var filesSkipped: Int = 0
    public var filesResumed: Int = 0
    public var filesRescanned: Int = 0

    public init() {}
}
