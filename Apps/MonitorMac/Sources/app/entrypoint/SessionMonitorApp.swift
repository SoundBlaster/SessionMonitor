import Foundation
import MonitorRuntime
import SwiftUI

@main
struct SessionMonitorApp: App {
    private let runtimeLoader = SessionMonitorRuntimeLoader()

    var body: some Scene {
        WindowGroup("SessionMonitor") {
            SessionMonitorWindow(runtimeLoader: runtimeLoader)
        }
        .defaultSize(width: 1120, height: 760)
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
            .task { await model.loadIfNeeded() }
    }
}

/// Database setup, like imports and queries, is performed away from MainActor.
private actor SessionMonitorRuntimeLoader {
    private var runtime: MonitorRuntime.SessionMonitor?

    func load() throws -> MonitorRuntime.SessionMonitor {
        if let runtime { return runtime }
        let runtime = try MonitorRuntime.SessionMonitor(
            databaseURL: MonitorRuntime.SessionMonitor.defaultDatabaseURL
        )
        self.runtime = runtime
        return runtime
    }
}
