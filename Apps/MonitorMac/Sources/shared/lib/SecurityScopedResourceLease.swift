import Foundation

/// Owns one access grant. Panel URLs already have an implicit grant; restored URLs do not.
final class SecurityScopedResourceLease: Sendable {
    private let url: URL
    private let bookmarks: FolderBookmarkClient
    private let shouldStop: Bool

    init(_ url: URL, fromPanel: Bool = false, bookmarks: FolderBookmarkClient = .live) {
        self.url = url
        self.bookmarks = bookmarks
        shouldStop = fromPanel || bookmarks.startAccess(url)
    }

    deinit {
        if shouldStop { bookmarks.stopAccess(url) }
    }
}
