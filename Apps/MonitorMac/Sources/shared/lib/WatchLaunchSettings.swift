import Foundation

/// The folder the user last chose to watch and whether to resume watching it on launch.
struct WatchLaunchSettings {
    static let directoryKey = "watch.lastDirectory"
    static let startOnLaunchKey = "watch.startOnLaunch"

    private let defaults: UserDefaults
    private let access: SavedFolderAccess

    init(defaults: UserDefaults = .standard, requiresBookmarks: Bool = AppFileAccess.requiresBookmarks,
         bookmarks: FolderBookmarkClient = .live) {
        self.defaults = defaults
        access = SavedFolderAccess(defaults: defaults, pathKey: Self.directoryKey,
                                   requiresBookmarks: requiresBookmarks, bookmarks: bookmarks)
    }

    var directory: URL? {
        try? access.restore()
    }

    /// On by default once a folder has been chosen; the Settings toggle can turn it off.
    var startOnLaunch: Bool {
        defaults.object(forKey: Self.startOnLaunchKey) as? Bool ?? true
    }

    func remember(_ directory: URL) throws {
        try access.save(directory)
    }

    /// The folder to resume, or why it cannot be resumed. `nil` means there is nothing to do.
    func launchDirectory(fileManager: FileManager = .default) -> Result<URL, WatchLaunchError>? {
        guard startOnLaunch else { return nil }
        let directory: URL
        do {
            guard let restored = try access.restore() else { return nil }
            directory = restored
        } catch let error as SavedFolderAccessError {
            return .failure(.access(error))
        } catch {
            return .failure(.access(.bookmarkUnavailable("the saved watch folder")))
        }
        let acquired = directory.startAccessingSecurityScopedResource()
        defer { if acquired { directory.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.missingDirectory(directory.path))
        }
        return .success(directory)
    }
}

enum WatchLaunchError: Error, Equatable, LocalizedError {
    case missingDirectory(String)
    case access(SavedFolderAccessError)

    var errorDescription: String? {
        switch self {
        case let .missingDirectory(path):
            "The saved watch folder is unavailable: \(path). Choose a folder to watch again."
        case let .access(error):
            error.localizedDescription
        }
    }
}
