import Foundation

/// The folder the user last chose to watch and whether to resume watching it on launch.
/// The app is not sandboxed, so a plain path is enough; no security-scoped bookmark is needed.
struct WatchLaunchSettings {
    static let directoryKey = "watch.lastDirectory"
    static let startOnLaunchKey = "watch.startOnLaunch"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var directory: URL? {
        defaults.string(forKey: Self.directoryKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// On by default once a folder has been chosen; the Settings toggle can turn it off.
    var startOnLaunch: Bool {
        defaults.object(forKey: Self.startOnLaunchKey) as? Bool ?? true
    }

    func remember(_ directory: URL) {
        defaults.set(directory.standardizedFileURL.path, forKey: Self.directoryKey)
    }

    /// The folder to resume, or why it cannot be resumed. `nil` means there is nothing to do.
    func launchDirectory(fileManager: FileManager = .default) -> Result<URL, WatchLaunchError>? {
        guard startOnLaunch, let directory else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(.missingDirectory(directory.path))
        }
        return .success(directory)
    }
}

enum WatchLaunchError: Error, Equatable, LocalizedError {
    case missingDirectory(String)

    var errorDescription: String? {
        switch self {
        case let .missingDirectory(path):
            "The saved watch folder is unavailable: \(path). Choose a folder to watch again."
        }
    }
}
