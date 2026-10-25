import AppKit
import SwiftUI

struct SharedIndexSettingsSection: View {
    let model: SharedIndexLocationModel

    var body: some View {
        Section {
            if let connection = model.connection {
                LabeledContent("Active index") {
                    Text(connection.databaseURL.path)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                if model.needsRestart {
                    Text("After restart: \(connection.selectedDirectory.path)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack {
                    SharedIndexFolderButton(model: model, title: "Change Folder…")
                    Spacer()
                    Button("Copy CLI Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            SharedIndexSettings.reportCommand(databaseURL: connection.databaseURL), forType: .string
                        )
                    }
                    .accessibilityIdentifier("storage.copyCLICommand")
                }
            } else {
                SharedIndexFolderButton(model: model)
            }
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        } header: {
            Text("Shared Index")
        } footer: {
            Text("The app opens usage.sqlite in place. Folder changes apply after restart; "
                 + "the copied CLI command always uses the active index. Session folders are selected separately.")
        }
        .task { await model.restoreIfNeeded() }
    }
}
