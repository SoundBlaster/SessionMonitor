import Foundation
import MonitorCore
import MonitorRuntime
import SwiftUI

@main
struct SessionMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    private let runtimeLoader: SessionMonitorRuntimeLoader
    private let preferences: AppPreferences
    @State private var menuModel: MenuSummaryModel
    @State private var reportScope: ReportScopeModel
    @State private var watchController: AppWatchController
    @State private var sharedIndex: SharedIndexLocationModel?
    @State private var cacheHitRateWidgetSettings = CacheHitRateWidgetSettings()
    @State private var cacheAnalytics = CacheAnalyticsPresentation()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    init() {
        let preferences = AppPreferences()
        self.preferences = preferences
        let isHostedTest = !preferences.isUITest && (NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
        _showMenuBarExtra = AppStorage(wrappedValue: true, "showMenuBarExtra", store: preferences.defaults)
        _cacheHitRateWidgetSettings = State(initialValue: CacheHitRateWidgetSettings(defaults: preferences.defaults))
        let testDatabase = URL.temporaryDirectory
            .appending(path: "SessionMonitor-hosted-tests-\(ProcessInfo.processInfo.processIdentifier)/usage.sqlite")
        let loader = SessionMonitorRuntimeLoader(
            databaseURL: isHostedTest ? testDatabase : MonitorRuntime.SessionMonitor.defaultDatabaseURL,
            publishesWidgets: !isHostedTest && !preferences.isUITest,
            requiresSharedIndex: !isHostedTest && AppFileAccess.requiresBookmarks,
            preferencesSuite: preferences.suiteName,
            deliversNotifications: !isHostedTest && !preferences.isUITest
        )
        runtimeLoader = loader
        let index = !isHostedTest && AppFileAccess.requiresBookmarks ? SharedIndexLocationModel(
            restore: { try await loader.restoreIndex() }, select: { try await loader.selectIndex($0) }
        ) : nil
        _sharedIndex = State(initialValue: index)
        let watch = AppWatchController(
            didImport: {
                if let runtime = try? await loader.load() { await runtime.publishWidgetSnapshotNow() }
            },
            factory: { directory in try await loader.watch(directory) }
        )
        let scope = ReportScopeModel(defaults: preferences.defaults, profileProvider: {
            let runtime = try await loader.load()
            return try await runtime.accountProfiles()
        })
        _reportScope = State(initialValue: scope)
        _watchController = State(initialValue: watch)
        _menuModel = State(initialValue: MenuSummaryModel(queryStreamFactory: { query in
            let runtime = try await loader.load()
            return await runtime.snapshots(query: query)
        }))
        appDelegate.shutdown = { await watch.shutdown() }
        // SM-205: resume watching the last chosen folder without user action.
        if !isHostedTest, index == nil {
            Task { await watch.startSaved(WatchLaunchSettings(defaults: preferences.defaults)) }
        }
    }

    var body: some Scene {
        WindowGroup("SessionMonitor", id: "session-explorer") {
            SharedIndexGate(model: sharedIndex) {
                SessionMonitorWindow(
                    runtimeLoader: runtimeLoader,
                    watch: watchController,
                    reportScope: reportScope,
                    cacheHitRateWidgetSettings: cacheHitRateWidgetSettings,
                    cacheAnalytics: cacheAnalytics,
                    defaults: preferences.defaults
                )
            }
            .task(id: sharedIndex?.isReady) {
                if sharedIndex?.isReady == true {
                    await watchController.startSaved(WatchLaunchSettings(defaults: preferences.defaults))
                }
            }
            .defaultAppStorage(preferences.defaults)
        }
        .defaultSize(width: 1120, height: 760)
        .commands { CacheAnalyticsCommands() }
        Window("Cache Hit Rate", id: CacheAnalyticsPresentation.windowID) {
            CacheAnalyticsPage(presentation: cacheAnalytics)
        }
        .defaultSize(width: 960, height: 640)
        #if DEBUG
        Window("Widget Lab", id: "cache-widget-lab") {
            CacheWidgetLabPage()
        }
        .defaultSize(width: 840, height: 720)
        #endif
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            SharedIndexGate(model: sharedIndex) {
                AppMenuHost(model: menuModel, watch: watchController, reportScope: reportScope,
                            runtimeLoader: runtimeLoader, defaults: preferences.defaults)
            }
            .defaultAppStorage(preferences.defaults)
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .accessibilityLabel("SessionMonitor")
                .accessibilityIdentifier("sessionMonitor.statusItem")
        }
        .menuBarExtraStyle(.window)
        Settings {
            MonitorSettingsPage(
                cacheHitRateWidgetSettings: cacheHitRateWidgetSettings, sharedIndex: sharedIndex
            )
            .defaultAppStorage(preferences.defaults)
        }
    }
}

/// Only the database runtime is shared. Every WindowGroup instance owns its page
/// model, navigation and SpecificationKit provider independently.
private struct SessionMonitorWindow: View {
    @State private var model: SessionExplorerModel
    let reportScope: ReportScopeModel
    let cacheHitRateWidgetSettings: CacheHitRateWidgetSettings
    let cacheAnalytics: CacheAnalyticsPresentation
    @Environment(\.scenePhase) private var scenePhase

    init(
        runtimeLoader: SessionMonitorRuntimeLoader,
        watch: AppWatchController,
        reportScope: ReportScopeModel,
        cacheHitRateWidgetSettings: CacheHitRateWidgetSettings,
        cacheAnalytics: CacheAnalyticsPresentation,
        defaults: UserDefaults
    ) {
        self.reportScope = reportScope
        self.cacheHitRateWidgetSettings = cacheHitRateWidgetSettings
        self.cacheAnalytics = cacheAnalytics
        _model = State(initialValue: SessionExplorerModel(
            importOperation: { directory, runtime, progress in
                try await watch.importManually { try await runtime.importDirectory(directory, progress: progress) }
            },
            runtimeFactory: { try await runtimeLoader.load() },
            importedDirectorySettings: ImportedDirectorySettings(defaults: defaults)
        ))
    }

    var body: some View {
        SessionExplorerPage(
            model: model,
            reportScope: reportScope,
            cacheHitRateWidgetSettings: cacheHitRateWidgetSettings,
            cacheAnalytics: cacheAnalytics
        )
            .frame(minWidth: 760, minHeight: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: reportScope.observationID) {
                await reportScope.refreshProfiles()
                let query = reportScope.focusedQuery
                await model.loadIfNeeded(query: query, chartScope: reportScope.query)
                guard !Task.isCancelled else { return }
                await model.observe(query: query, chartScope: reportScope.query)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reportScope.refreshRelativePeriod() }
            }
            .onOpenURL { url in
                guard let route = WidgetDeepLinkRoute(url: url) else { return }
                model.selectSession(nil)
                switch route {
                case let .usage(period):
                    reportScope.selectPreset(period == .today ? .today : .lastSevenDays)
                case .cacheHitRate:
                    reportScope.selectPreset(.lastSevenDays)
                    cacheHitRateWidgetSettings.selectPeriod(.last7Days)
                }
            }
    }
}
