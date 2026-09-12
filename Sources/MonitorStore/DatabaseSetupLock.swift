import Darwin
import Foundation

/// Serializes WAL setup and migrations without reserving long-lived importer ownership.
final class DatabaseSetupLock {
    private let descriptor: Int32

    /// O_CREAT follows dangling file symlinks without truncating an existing database.
    /// Once the file exists, realpath gives every first-open client the same sidecar namespace.
    static func prepareDatabaseURL(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard let resolved = realpath(url.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    init(url: URL) throws {
        descriptor = open(url.resolvingSymlinksInPath().path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            let code = errno
            close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    func release() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
