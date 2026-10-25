import AppKit
import SwiftUI

struct SharedIndexFolderButton: View {
    let model: SharedIndexLocationModel
    var title = "Choose Index Folder…"

    var body: some View {
        Button(title, action: chooseFolder)
            .disabled(model.isBusy)
            .accessibilityIdentifier("storage.chooseIndexFolder")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Connect Shared Index"
        panel.message = "Choose the folder containing usage.sqlite. An empty folder creates a new index. "
            + "The CLI can use this same file with --database."
        panel.prompt = "Connect"
        panel.directoryURL = model.connection?.selectedDirectory ?? SharedIndexSettings.suggestedDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let lease = SecurityScopedResourceLease(directory, fromPanel: true)
        Task {
            await model.selectDirectory(directory)
            withExtendedLifetime(lease) {}
        }
    }
}
