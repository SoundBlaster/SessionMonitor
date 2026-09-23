import SwiftUI

struct SessionExplorerToolbar: ToolbarContent {
    @Bindable var model: SessionExplorerModel
    @Bindable var reportScope: ReportScopeModel
    let chooseImportDirectory: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.1, *) {
            secondaryActions.visibilityPriority(.low)
        } else {
            secondaryActions
        }
    }

    @ToolbarContentBuilder
    private var secondaryActions: some ToolbarContent {
        ToolbarItemGroup {
            Button("Import Folder…", systemImage: "folder.badge.plus", action: chooseImportDirectory)
                .keyboardShortcut("o")
                .disabled(model.isBusy)
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            .keyboardShortcut("r")
            .disabled(model.isBusy)
            ReportScopeControls(model: reportScope)
        }
    }

}

struct SessionExplorerInspectorToolbar: ToolbarContent {
    @Bindable var model: SessionExplorerModel

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.1, *) {
            inspectorToggle.visibilityPriority(.high)
        } else {
            inspectorToggle
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
        }
    }
}
