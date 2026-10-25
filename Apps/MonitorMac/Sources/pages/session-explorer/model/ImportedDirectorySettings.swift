import Foundation

struct ImportedDirectorySettings {
    static let storageKey = "sessionExplorer.lastImportedDirectory"

    private let access: SavedFolderAccess

    init(defaults: UserDefaults = .standard, requiresBookmarks: Bool = AppFileAccess.requiresBookmarks,
         bookmarks: FolderBookmarkClient = .live) {
        access = SavedFolderAccess(defaults: defaults, pathKey: Self.storageKey,
                                   requiresBookmarks: requiresBookmarks, bookmarks: bookmarks)
    }

    var directory: URL? {
        try? restore()
    }

    func restore() throws -> URL? {
        try access.restore()
    }

    func save(_ directory: URL) throws {
        try access.save(directory)
    }
}
