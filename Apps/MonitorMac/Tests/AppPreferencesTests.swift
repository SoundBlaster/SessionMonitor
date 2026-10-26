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
