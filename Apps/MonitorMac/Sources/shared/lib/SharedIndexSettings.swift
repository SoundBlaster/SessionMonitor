import Foundation

struct SharedIndexConnection: Equatable, Sendable {
    let databaseURL: URL
    let selectedDirectory: URL
}

struct SharedIndexSettings {
    static let directoryKey = "storage.sharedIndexDirectory"
    let defaults: UserDefaults
    let bookmarks: FolderBookmarkClient

    init(defaults: UserDefaults = .standard, bookmarks: FolderBookmarkClient = .readWrite) {
        self.defaults = defaults
        self.bookmarks = bookmarks
    }

    func restore() throws -> URL? {
        try SavedFolderAccess(defaults: defaults, pathKey: Self.directoryKey,
                              requiresBookmarks: true, bookmarks: bookmarks).restore()
    }

    /// Prepare before opening SQLite; commit only after the selected index opens successfully.
    func prepare(_ directory: URL) throws -> Data {
        let lease = SecurityScopedResourceLease(directory, bookmarks: bookmarks)
        return try withExtendedLifetime(lease) { try bookmarks.create(directory) }
    }

    func commit(_ directory: URL, bookmark: Data) {
        defaults.set(bookmark, forKey: Self.directoryKey + ".bookmark")
        defaults.set(directory.standardizedFileURL.path, forKey: Self.directoryKey)
    }

    static var suggestedDirectory: URL {
        // Foundation's sandbox home differs from the login user's home.
        let home = NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appending(path: "Library/Application Support/SessionMonitor", directoryHint: .isDirectory)
    }

    static func reportCommand(databaseURL: URL) -> String {
        let quotedPath = "'" + databaseURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "codex-monitor report --database " + quotedPath
    }
}

enum SharedIndexError: LocalizedError {
    case selectionRequired

    var errorDescription: String? {
        "Choose the folder containing usage.sqlite to connect the app and CLI to the same index."
    }
}
