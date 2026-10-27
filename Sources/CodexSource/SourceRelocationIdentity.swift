import Foundation
#if canImport(Darwin)
import Darwin
#endif

extension RolloutDecoder {
    /// Relocation requires an inode lifetime, not just a potentially reused device/inode pair.
    /// Unsupported filesystems/platforms conservatively leave the sources separate.
    public func relocationIdentity(_ url: URL) throws -> String? {
        #if canImport(Darwin)
        let file = try RolloutFile(url: url)
        var attributes = stat()
        guard fstat(file.handle.fileDescriptor, &attributes) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard attributes.st_birthtimespec.tv_sec > 0 else { return nil }
        return file.version.identity
        #else
        return nil
        #endif
    }
}
