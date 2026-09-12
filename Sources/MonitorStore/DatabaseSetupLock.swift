import Darwin
import Foundation

/// Serializes WAL setup and migrations without reserving long-lived importer ownership.
final class DatabaseSetupLock {
    private let descriptor: Int32

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
