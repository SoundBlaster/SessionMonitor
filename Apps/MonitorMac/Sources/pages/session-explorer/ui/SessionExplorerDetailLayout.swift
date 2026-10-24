import SwiftUI

/// Keep notices in the column's safe area, below its toolbar and outside the scrolling report.
struct SessionExplorerDetailLayout<Content: View, Notices: View>: View {
    private let content: Content
    private let notices: Notices

    init(@ViewBuilder content: () -> Content, @ViewBuilder notices: () -> Notices) {
        self.content = content()
        self.notices = notices()
    }

    var body: some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaInset(edge: .top, spacing: 0) {
                notices
            }
            // Native split views query minimum sizes; the viewport must remain compressible.
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}

struct SessionExplorerImportNotices: View {
    let model: SessionExplorerModel
    let reportScope: ReportScopeModel

    var body: some View {
        VStack(spacing: 0) {
            if let directory = model.importRecoveryDirectory {
                SessionImportBusyBanner(directory: directory, isBusy: model.isBusy, retry: {
                    model.startRetryImport { await reportScope.refreshProfiles() }
                }, dismiss: model.dismissError)
            } else if let directory = model.importSourceRecoveryDirectory {
                SessionImportChangedSourceBanner(directory: directory, message: model.errorMessage ?? "",
                                                 isBusy: model.isBusy, retry: {
                    model.startRetryImport { await reportScope.refreshProfiles() }
                }, dismiss: model.dismissError)
            } else if let error = model.errorMessage {
                SessionExplorerErrorBanner(message: error, dismiss: model.dismissError)
            }
            if model.activity == .importing, let progress = model.importProgress {
                SessionImportProgressBanner(progress: progress, cancel: model.cancelImport)
            }
        }
    }
}

private struct SessionExplorerErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message).textSelection(.enabled)
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
        .padding()
        .background(.orange.opacity(0.10))
        .accessibilityElement(children: .combine)
    }
}
