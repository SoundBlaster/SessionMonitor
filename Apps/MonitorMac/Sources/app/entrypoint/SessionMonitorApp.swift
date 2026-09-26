import Foundation
import MonitorCore
import MonitorRuntime
import SwiftUI

@main
struct SessionMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    private let runtimeLoader: SessionMonitorRuntimeLoader
    @State private var menuModel: MenuSummaryModel
    @State private var reportScope: ReportScopeModel
    @State private var watchController: AppWatchController
    @State private var cacheHitRateWidgetSettings = CacheHitRateWidgetSettings()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    init() {
        let loader = SessionMonitorRuntimeLoader()
        runtimeLoader = loader
        let watch = AppWatchController(
            didImport: {
                if let runtime = try? await loader.load() { await runtime.publishWidgetSnapshotNow() }
            },
            factory: { directory in try await loader.watch(directory) }
        )
        let scope = ReportScopeModel(profileProvider: {
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
    }

    var body: some Scene {
        WindowGroup("SessionMonitor", id: "session-explorer") {
            SessionMonitorWindow(
                runtimeLoader: runtimeLoader,
                reportScope: reportScope,
                cacheHitRateWidgetSettings: cacheHitRateWidgetSettings
            )
        }
        .defaultSize(width: 1120, height: 760)
        #if DEBUG
        Window("Widget Lab", id: "cache-widget-lab") {
            CacheWidgetLabPage()
        }
        .defaultSize(width: 840, height: 720)
        #endif
        MenuBarExtra("SessionMonitor", systemImage: "chart.bar.xaxis", isInserted: $showMenuBarExtra) {
            AppMenuHost(model: menuModel, watch: watchController, reportScope: reportScope,
                        runtimeLoader: runtimeLoader)
        }
        .menuBarExtraStyle(.window)
        Settings {
            MonitorSettingsPage(
                cacheHitRateWidgetSettings: cacheHitRateWidgetSettings
            )
        }
    }
}

/// Only the database runtime is shared. Every WindowGroup instance owns its page
/// model, navigation and SpecificationKit provider independently.
private struct SessionMonitorWindow: View {
    @State private var model: SessionExplorerModel
    let reportScope: ReportScopeModel
    let cacheHitRateWidgetSettings: CacheHitRateWidgetSettings
    @Environment(\.scenePhase) private var scenePhase

    init(
        runtimeLoader: SessionMonitorRuntimeLoader,
        reportScope: ReportScopeModel,
        cacheHitRateWidgetSettings: CacheHitRateWidgetSettings
    ) {
        self.reportScope = reportScope
        self.cacheHitRateWidgetSettings = cacheHitRateWidgetSettings
        _model = State(initialValue: SessionExplorerModel {
            try await runtimeLoader.load()
        })
    }

    var body: some View {
        SessionExplorerPage(
            model: model,
            reportScope: reportScope,
            cacheHitRateWidgetSettings: cacheHitRateWidgetSettings
        )
            .frame(minWidth: 760, minHeight: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: reportScope.observationID) {
                await reportScope.refreshProfiles()
                let query = reportScope.query
                await model.loadIfNeeded(query: query)
                guard !Task.isCancelled else { return }
                await model.observe(query: query)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reportScope.refreshRelativePeriod() }
            }
    }
}

/// Database setup, like imports and queries, is performed away from MainActor.
actor SessionMonitorRuntimeLoader {
    private var runtime: SharedReportRuntime?
    private var databaseRuntime: MonitorRuntime.SessionMonitor?

    private func database() throws -> MonitorRuntime.SessionMonitor {
        if let databaseRuntime { return databaseRuntime }
        let value = try MonitorRuntime.SessionMonitor(databaseURL: MonitorRuntime.SessionMonitor.defaultDatabaseURL)
        databaseRuntime = value
        return value
    }

    func watch(_ directory: URL) async throws -> SessionWatch {
        try await database().watch(directory)
    }

    func load() async throws -> SharedReportRuntime {
        if let runtime { return runtime }
        let databaseRuntime = try database()
        let runtime = SharedReportRuntime(runtime: databaseRuntime)
        self.runtime = runtime
        Task { await runtime.publishWidgetSnapshotNow() }
        return runtime
    }

    func accountProfiles() async throws -> [AccountProfile] {
        let runtime = try await load()
        return try await runtime.accountProfiles()
    }
}
