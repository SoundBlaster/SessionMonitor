import Foundation

/// Keeps recovery scoped to the failure that produced it, including the exact folder to retry.
enum SessionExplorerFailure {
    case message(String)
    case importerBusy(URL)

    var message: String {
        switch self {
        case let .message(message): message
        case let .importerBusy(directory):
            String(localized: "Could not import \(directory.lastPathComponent). The database is in use.")
        }
    }

    var importRecoveryDirectory: URL? {
        guard case let .importerBusy(directory) = self else { return nil }
        return directory
    }
}
