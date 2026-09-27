import AppKit
import MonitorCore
import SwiftUI

struct AppMenuHost: View {
    let model: MenuSummaryModel
    let watch: AppWatchController
    let reportScope: ReportScopeModel
    let runtimeLoader: SessionMonitorRuntimeLoader
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuSummaryPage(model: model, query: reportScope.query, scopeLabel: reportScope.compactLabel,
                        reportScope: reportScope, watch: presentation, actions: MenuSummaryActions(
            openWindow: {
                NSApp.activate()
                openWindow(id: "session-explorer")
            },
            refresh: {
                Task {
                    let query = reportScope.query
                    await model.refresh(query: query) {
                        let runtime = try await runtimeLoader.load()
                        return try await runtime.snapshot(query: query)
                    }
                    if let runtime = try? await runtimeLoader.load() {
                        await runtime.publishWidgetSnapshotNow()
                    }
                }
            },
            startWatch: chooseWatchFolder,
            togglePause: {
                Task {
                    if watch.status?.phase == .paused {
                        await watch.resume()
                    } else {
                        await watch.pause()
                    }
                }
            },
            stopWatch: { Task { await watch.stop() } },
            openSettings: {
                NSApp.activate()
                openSettings()
            },
            quit: { NSApp.terminate(nil) }
        ))
    }

    private var presentation: MenuWatchPresentation {
        let title: String
        let symbol: String
        switch watch.status?.phase {
        case .watching: (title, symbol) = ("Watching", "wave.3.right")
        case .importing: (title, symbol) = ("Importing", "arrow.triangle.2.circlepath")
        case .paused: (title, symbol) = ("Watch paused", "pause.circle")
        case .recovering: (title, symbol) = ("Watch recovering", "exclamationmark.triangle")
        case .stopped: (title, symbol) = ("Watch stopped", "stop.circle")
        case nil: (title, symbol) = (watch.isRunning ? "Starting watch…" : "Watch not started", "folder")
        }
        return MenuWatchPresentation(
            title: watch.isShuttingDown ? "Stopping before quit…" : title, symbol: symbol,
            directory: watch.directory?.path,
            error: watch.errorMessage ?? watch.status?.error,
            isRunning: watch.isRunning, isPaused: watch.status?.phase == .paused,
            isBusy: watch.isBusy || watch.isShuttingDown
        )
    }

    private func chooseWatchFolder() {
        guard !watch.isBusy, !watch.isRunning, !watch.isShuttingDown else { return }
        let panel = NSOpenPanel()
        panel.title = "Watch JSONL Rollouts"
        panel.message = "The selected folder is imported, then monitored for changes until you stop watch or quit."
        panel.prompt = "Start Watch"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { await watch.start(directory) }
    }
}
