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

    private let store: UsageStore
    private let databaseURL: URL

    public init(databaseURL: URL = SessionMonitor.defaultDatabaseURL) throws {
        self.databaseURL = databaseURL
        store = try UsageStore(url: databaseURL)
    }

    /// Each changed source commits its records and checkpoint together; unchanged bodies are not read.
    public func importDirectory(_ directory: URL) throws -> ImportSummary {
        try importDirectory(directory, rescan: false)
    }

    public func importDirectory(_ directory: URL, rescan: Bool) throws -> ImportSummary {
        let lock = try ImportLock(url: databaseURL.appendingPathExtension("import-lock"))
        defer { lock.release() }
        let paths = try sourceFiles(directory)
        var records = 0
        var diagnostics: [String: Int64] = [:]
        var ioMetrics = ImportIO()
        for path in paths {
            try Task.checkCancellation()
            let source = path.resolvingSymlinksInPath().path
            let previous = try store.checkpoint(source: source)
            let update = try RolloutDecoder().parseIncrementally(path, checkpoint: rescan ? nil : previous)
            try Task.checkCancellation()
            if update.mode != .unchanged {
                try store.apply(source: source, update: update, expectedCheckpoint: previous)
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

    private func sourceFiles(_ root: URL) throws -> [URL] {
        let values = try root.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        if values.isRegularFile == true { return [root] }
        guard values.isDirectory == true else { throw MonitorError.notDirectory }
        var scanError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles],
            errorHandler: { _, error in scanError = error; return false }
        ) else { throw MonitorError.notDirectory }
        var paths: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { paths.append(url) }
        }
        if let scanError { throw scanError }
        return paths.sorted { $0.path < $1.path }
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

private final class ImportLock {
    private let descriptor: Int32

    init(url: URL) throws {
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw MonitorError.importerBusy
        }
    }

    func release() {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
