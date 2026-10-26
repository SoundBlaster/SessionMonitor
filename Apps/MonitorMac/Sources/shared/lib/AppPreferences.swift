import Foundation

/// UI tests isolate product settings, but still use real system folder grants.
struct AppPreferences {
    enum UITestFolder: String { case index, rollouts }
    static let uiTestSuitePrefix = "SessionMonitor.UITests."
    let suiteName: String?
    let defaults: UserDefaults

    var isUITest: Bool { suiteName != nil }

    /// Sets only the picker's initial folder. The native selection still creates the real grant.
    static func uiTestDirectory(_ folder: UITestFolder,
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        #if DEBUG
        guard let suite = environment["SESSIONMONITOR_UI_TEST_SUITE"], isUITestSuite(suite),
              let path = environment["SESSIONMONITOR_UI_TEST_FIXTURE"], path.hasPrefix("/") else { return nil }
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let prefix = "SandboxSmoke-"
        guard root.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil else { return nil }
        return root.appending(path: folder.rawValue, directoryHint: .isDirectory)
        #else
        return nil
        #endif
    }

    private static func isUITestSuite(_ name: String) -> Bool {
        name.hasPrefix(uiTestSuitePrefix)
            && UUID(uuidString: String(name.dropFirst(uiTestSuitePrefix.count))) != nil
    }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG
        suiteName = environment["SESSIONMONITOR_UI_TEST_SUITE"]
        if let suiteName {
            precondition(Self.isUITestSuite(suiteName),
                         "UI tests require a unique SessionMonitor.UITests.<UUID> preference suite")
        }
        #else
        suiteName = nil
        #endif
        if let suiteName, let isolated = UserDefaults(suiteName: suiteName) {
            defaults = isolated
            if environment["SESSIONMONITOR_UI_TEST_RESET"] == "1" {
                isolated.removePersistentDomain(forName: suiteName)
            }
        } else {
            precondition(suiteName == nil, "Could not open the isolated UI test preference suite")
            defaults = .standard
        }
    }
}
