import Foundation

struct FileWatchEvent: Sendable {
    let needsReattach: Bool
}

protocol FileEventSource: Sendable {
    func start(_ receive: @escaping @Sendable (FileWatchEvent) -> Void) throws
    func stop()
}

/// Portable watcher for platforms without FSEvents (Linux). Every `interval` it fingerprints the
/// rollout files under `root` (path, size, modification time) and reports only when that changes,
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

    /// `nil` when the root itself is unavailable, which asks the watch to reattach.
    static func fingerprint(root: URL, excludedPaths: Set<String>) -> [String: String]? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return nil }
        var result: [String: String] = [:]
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let isRollout = url.pathExtension == "jsonl"
                || (url.deletingPathExtension().pathExtension == "jsonl" && url.pathExtension.allSatisfy(\.isNumber))
            guard isRollout, !excludedPaths.contains(url.path), !name.hasPrefix("."),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            result[url.path] = "\(values.fileSize ?? 0):\(modified)"
        }
        return result
    }
}
