import CodexSource
import Darwin
import Foundation
import MonitorCore
import MonitorStore

public actor SessionMonitor {
    public static var defaultDatabaseURL: URL {
        if let path = ProcessInfo.processInfo.environment["SESSIONMONITOR_DATABASE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return URL.applicationSupportDirectory.appending(path: "SessionMonitor/usage.sqlite")
    }

    let store: UsageStore
    private let databaseURL: URL

    public init(databaseURL: URL = SessionMonitor.defaultDatabaseURL) throws {
        store = try UsageStore(url: databaseURL)
        self.databaseURL = store.databaseURL
    }

    /// Each changed source commits its records and checkpoint together; unchanged bodies are not read.
    public func importDirectory(_ directory: URL) throws -> ImportSummary {
        try importDirectory(directory, rescan: false)
    }

    public func importDirectory(_ directory: URL, rescan: Bool) throws -> ImportSummary {
        try importSources(directory, rescan: rescan, directoryOnly: false)
    }

    private func importSources(
        _ directory: URL, rescan: Bool, directoryOnly: Bool, ownsLease: Bool = false
    ) throws -> ImportSummary {
        try Task.checkCancellation()
        let lock = try ownsLease ? nil : ImportLock(url: databaseURL.appendingPathExtension("import-lock"))
        defer { lock?.release() }
        let paths = try sourceFiles(directory, directoryOnly: directoryOnly)
        var records = 0
        var diagnostics: [String: Int64] = [:]
        var ioMetrics = ImportIO()
        for path in paths {
            try Task.checkCancellation()
            let source = path.resolvingSymlinksInPath().path
            let previous = try store.checkpoint(source: source)
            let decoder = RolloutDecoder()
            if !rescan, let previous, try store.needsProvenanceBackfill(source: source) {
                let metadata = try decoder.parseMetadata(path)
                ioMetrics.bytesRead += metadata.bytesRead
                _ = try store.backfillProvenance(source: source, update: metadata,
                                                 expectedCheckpoint: previous)
            }
            let currentCheckpoint = try store.checkpoint(source: source)
            let update = try decoder.parseIncrementally(path, checkpoint: rescan ? nil : currentCheckpoint)
            try Task.checkCancellation()
            if update.mode != .unchanged {
                try store.apply(source: source, update: update, expectedCheckpoint: currentCheckpoint)
            }
            records += update.rollout.records.count
            for (key, count) in update.rollout.diagnostics { diagnostics[key, default: 0] += count }
            ioMetrics.bytesRead += update.bytesRead
            switch update.mode {
            case .unchanged: ioMetrics.filesSkipped += 1
            case .appended: ioMetrics.filesResumed += 1
            case .replaced: ioMetrics.filesRescanned += 1
            }
        }
        return ImportSummary(files: paths.count, records: records, diagnostics: diagnostics, ioMetrics: ioMetrics)
    }

    public func report(since: Date? = nil, until: Date? = nil) throws -> UsageReport {
        if let since, let until, since >= until { throw MonitorError.invalidDateRange }
        return try store.report(since: since, until: until)
    }

    public func watch(_ directory: URL, options: WatchOptions = WatchOptions()) async throws -> SessionWatch {
        try Task.checkCancellation()
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw WatchError.directoryRequired
        }
        let lease = try ImportLock(url: databaseURL.appendingPathExtension("import-lock"))
        let source = FSEventsSource(root: root, excludedPaths: databaseSourcePaths)
        let watch = try SessionWatch(source: source, options: options, lease: lease) {
            try await self.importSources(root, rescan: false, directoryOnly: true, ownsLease: true)
        }
        do { try await watch.start() } catch {
            await watch.stop()
            throw error
        }
        if Task.isCancelled {
            await watch.stop()
            throw CancellationError()
        }
        return watch
    }

    private func sourceFiles(_ root: URL, directoryOnly: Bool) throws -> [URL] {
        var root = root
        root.removeAllCachedResourceValues()
        let excluded = databaseSourcePaths
        let values = try root.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        if values.isRegularFile == true {
            guard !directoryOnly else { throw WatchError.directoryRequired }
            return excluded.contains(root.resolvingSymlinksInPath().path) ? [] : [root]
        }
        guard values.isDirectory == true else { throw MonitorError.notDirectory }
        var scanError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles],
            errorHandler: { _, error in scanError = error; return false }
        ) else { throw MonitorError.notDirectory }
        var paths: [URL] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard isRolloutFilename(url) else { continue }
            guard !excluded.contains(url.resolvingSymlinksInPath().path) else { continue }
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { paths.append(url) }
        }
        if let scanError { throw scanError }
        return paths.sorted { $0.path < $1.path }
    }

    private func isRolloutFilename(_ url: URL) -> Bool {
        url.pathExtension == "jsonl"
            || (url.deletingPathExtension().pathExtension == "jsonl"
                && url.pathExtension.wholeMatch(of: /[0-9]+/) != nil)
    }

    private var databaseSourcePaths: Set<String> {
        let path = databaseURL.resolvingSymlinksInPath().standardizedFileURL.path
        return [path, path + "-wal", path + "-shm", path + ".import-lock", path + ".setup-lock"]
    }
}

public enum MonitorError: Error, LocalizedError {
    case importerBusy
    case notDirectory
    case invalidDateRange

    public var errorDescription: String? {
        switch self {
        case .importerBusy: "Another importer is using this database."
        case .notDirectory: "Choose an accessible JSONL file or directory."
        case .invalidDateRange: "The start date must precede the end date."
        }
    }
}
