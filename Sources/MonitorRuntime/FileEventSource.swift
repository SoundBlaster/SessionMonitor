#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

struct FileWatchEvent: Sendable {
    let needsReattach: Bool
}

protocol FileEventSource: Sendable {
    func start(_ receive: @escaping @Sendable (FileWatchEvent) -> Void) throws
    func stop()
}

/// Portable watcher for platforms without FSEvents (Linux). Every `interval` it fingerprints the
/// rollout files under `root` (path, device, inode, size, modification and status-change times, as
/// `RolloutFileVersion` compares them) and reports only when that changes,
/// so an idle folder triggers no imports. Imports stay incremental through checkpoints.
final class PollingFileEventSource: FileEventSource, @unchecked Sendable {
    private let root: URL
    private let excludedPaths: Set<String>
    private let interval: Duration
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    init(root: URL, excludedPaths: Set<String>, interval: Duration = .seconds(2)) {
        self.root = root
        self.excludedPaths = excludedPaths
        self.interval = interval
    }

    func start(_ receive: @escaping @Sendable (FileWatchEvent) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard task == nil else { return }
        let root = root
        let excluded = excludedPaths
        let interval = interval
        var previous = Self.fingerprint(root: root, excludedPaths: excluded)
        task = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                let current = Self.fingerprint(root: root, excludedPaths: excluded)
                if current != previous {
                    previous = current
                    receive(FileWatchEvent(needsReattach: current == nil))
                }
            }
        }
    }

    func stop() {
        lock.lock()
        let running = task
        task = nil
        lock.unlock()
        running?.cancel()
    }

    deinit { stop() }

    /// `nil` when the root itself is unavailable or cannot be enumerated, which asks the watch to reattach.
    static func fingerprint(root: URL, excludedPaths: Set<String>) -> [String: String]? {
        let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard rootValues?.isDirectory == true, rootValues?.isReadable == true else { return nil }
        var failed = false
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles],
            errorHandler: { _, _ in
                failed = true
                return true
            }
        ) else { return nil }
        var result: [String: String] = [:]
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let isRollout = url.pathExtension == "jsonl"
                || (url.deletingPathExtension().pathExtension == "jsonl" && url.pathExtension.allSatisfy(\.isNumber))
            guard isRollout, !excludedPaths.contains(url.path), !name.hasPrefix("."),
                  let version = version(of: url) else { continue }
            result[url.path] = version
        }
        return failed ? nil : result
    }

    /// Same identity and change fields the importer checks, so a same-size atomic replacement is seen.
    private static func version(of url: URL) -> String? {
        var info = stat()
        guard stat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        #if canImport(Darwin)
        let modified = "\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec)"
        let changed = "\(info.st_ctimespec.tv_sec).\(info.st_ctimespec.tv_nsec)"
        #else
        let modified = "\(info.st_mtim.tv_sec).\(info.st_mtim.tv_nsec)"
        let changed = "\(info.st_ctim.tv_sec).\(info.st_ctim.tv_nsec)"
        #endif
        return "\(info.st_dev):\(info.st_ino):\(info.st_size):\(modified):\(changed)"
    }
}
