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
    @State private var cacheHitSettings = CacheHitThresholdSettings()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    init() {
        let loader = SessionMonitorRuntimeLoader()
        runtimeLoader = loader
        let watch = AppWatchController { directory in try await loader.watch(directory) }
        let scope = ReportScopeModel()
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
                cacheHitSettings: cacheHitSettings
            )
        }
        .defaultSize(width: 1120, height: 760)
        MenuBarExtra("SessionMonitor", systemImage: "chart.bar.xaxis", isInserted: $showMenuBarExtra) {
            AppMenuHost(model: menuModel, watch: watchController, reportScope: reportScope,
                        runtimeLoader: runtimeLoader)
        }
        .menuBarExtraStyle(.window)
        Settings { MonitorSettingsPage(cacheHitSettings: cacheHitSettings) }
    }
}

/// Only the database runtime is shared. Every WindowGroup instance owns its page
/// model, navigation and SpecificationKit provider independently.
private struct SessionMonitorWindow: View {
    @State private var model: SessionExplorerModel
    let reportScope: ReportScopeModel
    let cacheHitSettings: CacheHitThresholdSettings
    @Environment(\.scenePhase) private var scenePhase

    init(
        runtimeLoader: SessionMonitorRuntimeLoader,
        reportScope: ReportScopeModel,
        cacheHitSettings: CacheHitThresholdSettings
    ) {
        self.reportScope = reportScope
        self.cacheHitSettings = cacheHitSettings
        _model = State(initialValue: SessionExplorerModel {
            try await runtimeLoader.load()
        })
    }

    var body: some View {
        SessionExplorerPage(
            model: model,
            reportScope: reportScope,
            cacheHitSettings: cacheHitSettings
        )
            .frame(minWidth: 760, minHeight: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: reportScope.observationID) {
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

    func load() throws -> SharedReportRuntime {
        if let runtime { return runtime }
        let databaseRuntime = try database()
        let runtime = SharedReportRuntime(runtime: databaseRuntime)
        self.runtime = runtime
        return runtime
    }
}
