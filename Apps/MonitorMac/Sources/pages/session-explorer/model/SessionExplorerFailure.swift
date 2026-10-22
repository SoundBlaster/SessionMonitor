import Foundation

/// Keeps recovery scoped to the failure that produced it, including the exact folder to retry.
enum SessionExplorerFailure {
    case message(String)
    case importerBusy(URL)
    case sourceChanged(URL, fileName: String, completedFiles: Int, totalFiles: Int)

    var message: String {
        switch self {
        case let .message(message): message
        case let .importerBusy(directory):
            String(localized: "Could not import \(directory.lastPathComponent). The database is in use.")
        case let .sourceChanged(directory, fileName, completedFiles, totalFiles):
            String(localized: """
                Could not finish importing \(directory.lastPathComponent). “\(fileName)” changed while it was read. \\
                Its checkpoint was not advanced; \(completedFiles) of \(totalFiles) earlier files were saved. \\
                Retry when the source stops changing.
                """)
        }
    }

    var importRecoveryDirectory: URL? {
        guard case let .importerBusy(directory) = self else { return nil }
        return directory
    }

    var importSourceRecoveryDirectory: URL? {
        guard case let .sourceChanged(directory, _, _, _) = self else { return nil }
        return directory
    }
}
