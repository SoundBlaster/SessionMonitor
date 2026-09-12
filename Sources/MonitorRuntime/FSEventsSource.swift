import CoreServices
import Darwin
import Foundation

struct FileWatchEvent: Sendable {
    let needsReattach: Bool
}

protocol FileEventSource: Sendable {
    func start(_ receive: @escaping @Sendable (FileWatchEvent) -> Void) throws
    func stop()
}

/// The lock owns all native stream state. Callbacks use a separate immutable context
/// and never take this lock, so stopping a stream cannot deadlock its callback.
final class FSEventsSource: FileEventSource, @unchecked Sendable {
    private let root: URL
    private let excludedPaths: Set<String>
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "SessionMonitor.FSEvents")
    private var stream: FSEventStreamRef?

    init(root: URL, excludedPaths: Set<String>) {
        self.root = root
        self.excludedPaths = excludedPaths
    }

    func start(_ receive: @escaping @Sendable (FileWatchEvent) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else { return }
        let callback = CallbackContext(root: root.path, excludedPaths: excludedPaths, receive: receive)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<CallbackContext>.fromOpaque(pointer).retain()
                return pointer
            },
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<CallbackContext>.fromOpaque(pointer).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
        )
        let paths = [FileEventFilter.physicalPath(root.deletingLastPathComponent())] as CFArray
        let created = withExtendedLifetime(callback) {
            FSEventStreamCreate(kCFAllocatorDefault, { _, info, count, paths, flags, _ in
                guard let info else { return }
                let callback = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue()
                let eventPaths = unsafeBitCast(paths, to: NSArray.self)
                var pending: FileWatchEvent?
                for index in 0..<count {
                    guard let path = eventPaths[index] as? String else { continue }
                    guard let event = callback.filter.event(path: path, flags: flags[index]) else { continue }
                    pending = FileWatchEvent(needsReattach: event.needsReattach || pending?.needsReattach == true)
                }
                if let pending { callback.receive(pending) }
            }, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, flags)
        }
        guard let created else { throw FileEventsError.creationFailed }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            throw FileEventsError.startFailed
        }
        stream = created
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}

private final class CallbackContext: Sendable {
    let filter: FileEventFilter
    let receive: @Sendable (FileWatchEvent) -> Void

    init(root: String, excludedPaths: Set<String>, receive: @escaping @Sendable (FileWatchEvent) -> Void) {
        filter = FileEventFilter(root: URL(fileURLWithPath: root), excludedPaths: excludedPaths)
        self.receive = receive
    }
}

struct FileEventFilter: Sendable {
    private let root: String
    private let excludedPaths: Set<String>

    init(root: URL, excludedPaths: Set<String>) {
        self.root = Self.physicalPath(root)
        self.excludedPaths = Set(excludedPaths.map { Self.physicalPath(URL(fileURLWithPath: $0)) })
    }

    func event(path: String, flags: FSEventStreamEventFlags) -> FileWatchEvent? {
        let recovery = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped
            | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount | kFSEventStreamEventFlagUnmount)
        if flags & recovery != 0 {
            let reattach = UInt32(kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagUnmount)
            return FileWatchEvent(needsReattach: flags & reattach != 0)
        }
        // FSEvents supplies physical paths, even for removed entries. Foundation's
        // standardizedFileURL can remove /private only while the entry exists.
        let url = URL(fileURLWithPath: path)
        guard !excludedPaths.contains(path), path == root || path.hasPrefix(root == "/" ? "/" : root + "/") else {
            return nil
        }
        let relative = path.dropFirst(root.count)
        guard !relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { return nil }
        let isArchive = url.deletingPathExtension().pathExtension == "jsonl"
            && url.pathExtension.wholeMatch(of: /[0-9]+/) != nil
        guard path == root || flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
            || url.pathExtension == "jsonl" || isArchive else { return nil }
        return FileWatchEvent(needsReattach: false)
    }

    static func physicalPath(_ url: URL) -> String {
        var ancestor = url
        var missing: [String] = []
        while true {
            if let resolved = realpath(ancestor.path, nil) {
                defer { free(resolved) }
                let base = String(cString: resolved)
                return missing.reversed().reduce(base) { $0 == "/" ? $0 + $1 : $0 + "/" + $1 }
            }
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestor.path else { return url.path }
            missing.append(ancestor.lastPathComponent)
            ancestor = parent
        }
    }
}

private enum FileEventsError: Error, LocalizedError {
    case creationFailed, startFailed

    var errorDescription: String? {
        switch self {
        case .creationFailed: "Could not create the file event stream."
        case .startFailed: "Could not start watching the source directory."
        }
    }
}
