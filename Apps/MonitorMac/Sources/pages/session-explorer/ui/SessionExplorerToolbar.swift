import NestedA11yIDs
import SwiftUI

struct SessionExplorerToolbar: ToolbarContent {
    @Bindable var model: SessionExplorerModel
    @Bindable var reportScope: ReportScopeModel
    let chooseImportDirectory: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
#if compiler(>=6.2.1)
        if #available(macOS 26.1, *) {
            secondaryActions.visibilityPriority(.low)
            accountScope.visibilityPriority(.high)
        } else {
            secondaryActions
            accountScope
        }
#else
        secondaryActions
        accountScope
#endif
    }

    @ToolbarContentBuilder
    private var secondaryActions: some ToolbarContent {
        ToolbarItemGroup {
            Button("Import Folder…", systemImage: "folder.badge.plus", action: chooseImportDirectory)
                .keyboardShortcut("o")
                .accessibilityIdentifier("sessionExplorer.importFolder")
                .disabled(model.isBusy)
            Button("Update", systemImage: "arrow.clockwise") {
                if model.importedDirectory == nil {
                    chooseImportDirectory()
                } else {
                    Task {
                        await model.update()
                        await reportScope.refreshProfiles()
                    }
                }
            }
            .keyboardShortcut("r")
            .help(model.importedDirectory == nil
                ? "Choose a rollout folder to use as the update source"
                : "Import new and changed JSONL files from the last folder")
            .disabled(model.isBusy)
            .accessibilityIdentifier("sessionExplorer.update")
            Button("Findings", systemImage: "exclamationmark.bubble") {
                model.navigation.showsFindings = true
            }
            .help("Show diagnostic findings and alerts for this report")
            .accessibilityIdentifier("sessionExplorer.findings")
        }
    }

    @ToolbarContentBuilder
    private var accountScope: some ToolbarContent {
        ToolbarItem {
            ReportScopeControls(model: reportScope)
        }
    }

}

struct SessionExplorerDetailToolbar: ToolbarContent {
    @Bindable var model: SessionExplorerModel
    let exportSession: (String) -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
#if compiler(>=6.2.1)
        if #available(macOS 26.1, *) {
            sessionExport.visibilityPriority(.low)
            inspectorToggle.visibilityPriority(.high)
        } else {
            sessionExport
            inspectorToggle
        }
#else
        sessionExport
        inspectorToggle
#endif
    }

    private var sessionExport: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Export anonymized JSON…", systemImage: "square.and.arrow.up") {
                if let sessionID = model.selectedSession?.id {
                    exportSession(sessionID)
                }
            }
            .labelStyle(.iconOnly)
            .disabled(model.selectedSession == nil)
            .help("Save an identity-free session fixture for diagnostics")
            .accessibilityIdentifier("sessionExplorer.exportSession")
        }
    }

    private var inspectorToggle: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.navigation.showsInspector.toggle()
            } label: {
                Label(
                    model.navigation.showsInspector ? "Hide Inspector" : "Show Inspector",
                    systemImage: "sidebar.right"
                )
            }
            .labelStyle(.iconOnly)
            .help(model.navigation.showsInspector ? "Hide Inspector" : "Show Inspector")
            .accessibilityLabel(model.navigation.showsInspector ? "Hide Inspector" : "Show Inspector")
            .accessibilityIdentifier("sessionExplorer.inspectorToggle")
        }
    }
}
