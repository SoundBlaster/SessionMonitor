import Foundation

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
