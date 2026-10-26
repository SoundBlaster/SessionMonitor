import Foundation
import Testing
@testable import SessionMonitor

@MainActor
struct AppPreferencesTests {
    @Test func ordinaryLaunchUsesStandardPreferences() {
        let preferences = AppPreferences(environment: [:])
        #expect(!preferences.isUITest)
        #expect(preferences.defaults === UserDefaults.standard)
    }

    @Test func uiTestFolderSuggestionsRequireIsolatedSuiteAndSyntheticRoot() {
        let root = "/tmp/SandboxSmoke-\(UUID())"
        var environment = ["SESSIONMONITOR_UI_TEST_FIXTURE": root]
        #expect(AppPreferences.uiTestDirectory(.index, environment: environment) == nil)
        environment["SESSIONMONITOR_UI_TEST_SUITE"] = "ordinary"
        #expect(AppPreferences.uiTestDirectory(.index, environment: environment) == nil)
        environment["SESSIONMONITOR_UI_TEST_SUITE"] = AppPreferences.uiTestSuitePrefix + UUID().uuidString
        #expect(AppPreferences.uiTestDirectory(.index, environment: environment)?.path == root + "/index")
        #expect(AppPreferences.uiTestDirectory(.rollouts, environment: environment)?.path == root + "/rollouts")
        environment["SESSIONMONITOR_UI_TEST_FIXTURE"] = "/tmp/personal-folder"
        #expect(AppPreferences.uiTestDirectory(.index, environment: environment) == nil)
    }

    @Test func uiTestPreferencesSurviveRelaunchAndResetOnlyTheirSuite() {
        let suite = AppPreferences.uiTestSuitePrefix + UUID().uuidString
        let environment = ["SESSIONMONITOR_UI_TEST_SUITE": suite]
        let first = AppPreferences(environment: environment)
        defer { first.defaults.removePersistentDomain(forName: suite) }
        #expect(first.isUITest)
        let key = "fixture.\(UUID())"
        first.defaults.set("saved", forKey: key)
        let relaunched = AppPreferences(environment: environment)
        #expect(relaunched.defaults.string(forKey: key) == "saved")
        #expect(UserDefaults.standard.object(forKey: key) == nil)
        var reset = environment
        reset["SESSIONMONITOR_UI_TEST_RESET"] = "1"
        #expect(AppPreferences(environment: reset).defaults.object(forKey: key) == nil)
    }
}
