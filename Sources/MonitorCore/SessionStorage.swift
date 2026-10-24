import Foundation

/// Descriptor metadata from a successfully validated source snapshot. Identity stays in the store;
/// it is not a path, content hash, allocated size or estimate of reclaimable disk space.
public struct SourceFileObservation: Sendable {
    public let sessionID: String?
    public let identity: String
    public let byteCount: Int64
    public let modifiedAt: Date

    public init(sessionID: String?, identity: String, byteCount: Int64, modifiedAt: Date) {
        self.sessionID = sessionID
        self.identity = identity
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
    }
}

/// Whole imported source files owned by this session in the selected account scope, independent
/// of the report period. Copies count separately; hard links and resolved symlinks count once.
/// Only known imported sources are covered; discovery of missing/unimported files is not implied.
public struct SessionStorageSummary: Codable, Equatable, Sendable {
    public let knownBytes: Int64
    public let fileCount: Int
    public let unknownSizeFileCount: Int
    public let lastModifiedAt: Date?

    /// Nil means the indexed source set contains sizes that have not been observed yet.
    public var totalBytes: Int64? { unknownSizeFileCount == 0 ? knownBytes : nil }

    public init(knownBytes: Int64, fileCount: Int, unknownSizeFileCount: Int, lastModifiedAt: Date?) {
        self.knownBytes = knownBytes
        self.fileCount = fileCount
        self.unknownSizeFileCount = unknownSizeFileCount
        self.lastModifiedAt = lastModifiedAt
    }
}
