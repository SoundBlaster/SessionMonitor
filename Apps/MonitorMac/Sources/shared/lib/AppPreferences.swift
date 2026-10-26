import Foundation

/// UI tests isolate product settings, but still use real system folder grants.
struct AppPreferences {
    static let uiTestSuitePrefix = "SessionMonitor.UITests."
    let suiteName: String?
    let defaults: UserDefaults

    var isUITest: Bool { suiteName != nil }

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if DEBUG
        suiteName = environment["SESSIONMONITOR_UI_TEST_SUITE"]
        if let suiteName {
            precondition(suiteName.hasPrefix(Self.uiTestSuitePrefix)
                         && UUID(uuidString: String(suiteName.dropFirst(Self.uiTestSuitePrefix.count))) != nil,
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
