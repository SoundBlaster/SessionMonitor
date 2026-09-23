import Foundation

struct ImportedDirectorySettings {
    static let storageKey = "sessionExplorer.lastImportedDirectory"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var directory: URL? {
        guard let path = defaults.string(forKey: Self.storageKey) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func save(_ directory: URL) {
        defaults.set(directory.standardizedFileURL.path, forKey: Self.storageKey)
    }
}
