import Foundation
import MonitorCore
import MonitorRuntime
import SwiftUI

@main
struct SessionMonitorApp: App {
    private let runtimeLoader: SessionMonitorRuntimeLoader
    @State private var menuModel: MenuSummaryModel
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    init() {
        let loader = SessionMonitorRuntimeLoader()
        runtimeLoader = loader
        _menuModel = State(initialValue: MenuSummaryModel {
            let runtime = try await loader.load()
            return await runtime.snapshots(query: try UsageQuery())
        })
    }

    var body: some Scene {
        WindowGroup("SessionMonitor") {
            SessionMonitorWindow(runtimeLoader: runtimeLoader)
        }
        .defaultSize(width: 1120, height: 760)
        MenuBarExtra("SessionMonitor", systemImage: "chart.bar.xaxis", isInserted: $showMenuBarExtra) {
            MenuSummaryPage(model: menuModel)
        }
        .menuBarExtraStyle(.window)
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
private actor SessionMonitorRuntimeLoader {
    private var runtime: SharedReportRuntime?

    func load() throws -> SharedReportRuntime {
        if let runtime { return runtime }
        let databaseRuntime = try MonitorRuntime.SessionMonitor(
            databaseURL: MonitorRuntime.SessionMonitor.defaultDatabaseURL
        )
        let runtime = SharedReportRuntime(runtime: databaseRuntime)
        self.runtime = runtime
        return runtime
    }
}
