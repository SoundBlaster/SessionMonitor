import Foundation
import MonitorCore
import MonitorRuntime
import SwiftUI

@main
struct SessionMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    private let runtimeLoader: SessionMonitorRuntimeLoader
    @State private var menuModel: MenuSummaryModel
    @State private var watchController: AppWatchController
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    init() {
        let loader = SessionMonitorRuntimeLoader()
        runtimeLoader = loader
        let watch = AppWatchController { directory in try await loader.watch(directory) }
        _watchController = State(initialValue: watch)
        _menuModel = State(initialValue: MenuSummaryModel {
            let runtime = try await loader.load()
            return await runtime.snapshots(query: try UsageQuery())
        })
        appDelegate.shutdown = { await watch.shutdown() }
    }

    var body: some Scene {
        WindowGroup("SessionMonitor", id: "session-explorer") {
            SessionMonitorWindow(runtimeLoader: runtimeLoader)
        }
        .defaultSize(width: 1120, height: 760)
        MenuBarExtra("SessionMonitor", systemImage: "chart.bar.xaxis", isInserted: $showMenuBarExtra) {
            AppMenuHost(model: menuModel, watch: watchController, runtimeLoader: runtimeLoader)
        }
        .menuBarExtraStyle(.window)
        Settings { MonitorSettingsPage() }
    }
}

/// Only the database runtime is shared. Every WindowGroup instance owns its page
/// model, navigation and SpecificationKit provider independently.
private struct SessionMonitorWindow: View {
    @State private var model: SessionExplorerModel

    init(runtimeLoader: SessionMonitorRuntimeLoader) {
        _model = State(initialValue: SessionExplorerModel {
            try await runtimeLoader.load()
        })
    }

    var body: some View {
        SessionExplorerPage(model: model)
            .frame(minWidth: 760, minHeight: 520)
            .task {
                await model.loadIfNeeded()
                await model.observe()
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
