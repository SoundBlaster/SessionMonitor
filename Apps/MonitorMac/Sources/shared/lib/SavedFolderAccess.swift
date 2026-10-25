import Foundation

/// Store builds require a grant from the system folder picker, including after relaunch.
enum AppFileAccess {
    static var requiresBookmarks: Bool {
        #if APP_STORE
        true
        #else
        false
        #endif
    }
}

struct FolderBookmarkClient: Sendable {
    var create: @Sendable (URL) throws -> Data
    var resolve: @Sendable (Data) throws -> (url: URL, stale: Bool)
    var startAccess: @Sendable (URL) -> Bool
    var stopAccess: @Sendable (URL) -> Void

    static var live: Self {
        Self(create: { url in
            try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                 includingResourceValuesForKeys: nil, relativeTo: nil)
        }, resolve: { data in
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url, stale)
        }, startAccess: { $0.startAccessingSecurityScopedResource() },
             stopAccess: { $0.stopAccessingSecurityScopedResource() })
    }
}

/// Keeps the resolved URL (and its security scope); a path is only a legacy preference/display value.
struct SavedFolderAccess {
    let defaults: UserDefaults
    let pathKey: String
    let requiresBookmarks: Bool
    let bookmarks: FolderBookmarkClient

    var bookmarkKey: String { pathKey + ".bookmark" }

    func restore() throws -> URL? {
        let path = defaults.string(forKey: pathKey)
        guard requiresBookmarks else {
            return path.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }
        guard let data = defaults.data(forKey: bookmarkKey) else {
            guard let path else { return nil }
            throw SavedFolderAccessError.permissionRequired(path)
        }
        do {
            let resolved = try bookmarks.resolve(data)
            if resolved.stale {
                // Refresh while the resolved grant is active, then release only our own access.
                let acquired = bookmarks.startAccess(resolved.url)
                defer { if acquired { bookmarks.stopAccess(resolved.url) } }
                let refreshed = try bookmarks.create(resolved.url)
                defaults.set(refreshed, forKey: bookmarkKey)
            }
            defaults.set(resolved.url.path, forKey: pathKey)
            return resolved.url
        } catch {
            // Never fall back to an old path in the sandbox after a failed bookmark resolution.
            throw SavedFolderAccessError.bookmarkUnavailable(path ?? "the saved folder")
        }
    }

    func save(_ directory: URL) throws {
        if requiresBookmarks {
            let acquired = bookmarks.startAccess(directory)
            defer { if acquired { bookmarks.stopAccess(directory) } }
            do {
                let data = try bookmarks.create(directory)
                defaults.set(data, forKey: bookmarkKey)
            } catch {
                // Retain the previous folder and grant when saving a new selection fails.
                throw SavedFolderAccessError.cannotRemember(directory.path)
            }
        } else {
            // A newer plain-path selection must not revive an older grant if the Store build is reopened.
            defaults.removeObject(forKey: bookmarkKey)
        }
        defaults.set(directory.standardizedFileURL.path, forKey: pathKey)
    }
}

enum SavedFolderAccessError: Error, Equatable, LocalizedError {
    case permissionRequired(String)
    case bookmarkUnavailable(String)
    case cannotRemember(String)

    var errorDescription: String? {
        switch self {
        case let .permissionRequired(path):
            "Choose the saved folder again to grant access: \(path). A saved path alone does not grant permission."
        case let .bookmarkUnavailable(path):
            "Access to the saved folder could not be restored: \(path). Choose the folder again."
        case let .cannotRemember(path):
            "Access to the folder could not be saved: \(path). Choose the folder again before restarting the app."
        }
    }
}
