import Darwin
import Foundation

struct RolloutFileVersion: Codable, Equatable {
    let identity: String
    let size: UInt64
    let modification: String

    init(handle: FileHandle) throws {
        var attributes = stat()
        guard fstat(handle.fileDescriptor, &attributes) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_size >= 0 else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        identity = "\(attributes.st_dev):\(attributes.st_ino):"
            + "\(attributes.st_birthtimespec.tv_sec):\(attributes.st_birthtimespec.tv_nsec)"
        size = UInt64(attributes.st_size)
        modification = "\(attributes.st_mtimespec.tv_sec):\(attributes.st_mtimespec.tv_nsec):"
            + "\(attributes.st_ctimespec.tv_sec):\(attributes.st_ctimespec.tv_nsec)"
    }
}

/// Reads one bounded descriptor snapshot; a changing source is retried by the next import.
final class RolloutFile {
    let handle: FileHandle
    let version: RolloutFileVersion
    private(set) var bytesRead: UInt64 = 0

    init(url: URL) throws {
        let opened = try FileHandle(forReadingFrom: url)
        do {
            version = try RolloutFileVersion(handle: opened)
            handle = opened
        } catch {
            try? opened.close()
            throw error
        }
    }

    deinit { try? handle.close() }

    func read(upToCount count: Int) throws -> Data {
        try Task.checkCancellation()
        guard let data = try handle.read(upToCount: count), !data.isEmpty else {
            throw RolloutReadError.sourceChanged
        }
        bytesRead += UInt64(data.count)
        return data
    }

    func validateSnapshot() throws {
        try Task.checkCancellation()
        guard try RolloutFileVersion(handle: handle) == version else { throw RolloutReadError.sourceChanged }
    }
}

public enum RolloutReadError: Error, LocalizedError {
    case sourceChanged

    public var errorDescription: String? {
        "The JSONL file changed while it was being read. Its checkpoint was not advanced; retry the import."
    }
}
