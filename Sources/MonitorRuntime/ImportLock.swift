import Darwin
import Foundation

/// Cooperative database ownership. Never unlink the file: all clients must lock the same inode.
final class ImportLock: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32

    init(url: URL) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(descriptor)
            descriptor = -1
            if code == EWOULDBLOCK { throw MonitorError.importerBusy }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    func release() {
        lock.withLock {
            guard descriptor >= 0 else { return }
            flock(descriptor, LOCK_UN)
            close(descriptor)
            descriptor = -1
        }
    }

    deinit { release() }
}
