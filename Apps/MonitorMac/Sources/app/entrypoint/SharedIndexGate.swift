import SwiftUI

/// The app and menu share one connection. Neither can open a private fallback index.
struct SharedIndexGate<Content: View>: View {
    let model: SharedIndexLocationModel?
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if let model, !model.isReady {
                VStack(spacing: 16) {
                    Image(systemName: "externaldrive").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Connect Your Session Index").font(.headline)
                    Text("Choose your existing SessionMonitor index folder to keep your history "
                         + "and let the app and CLI use the same data.")
                        .foregroundStyle(.secondary)
                    if model.isBusy {
                        ProgressView("Opening index…")
                    } else if let error = model.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                    }
                    SharedIndexFolderButton(model: model)
                        .buttonStyle(.borderedProminent)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(24)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("storage.indexConnection")
            } else {
                content()
            }
        }
        .task { await model?.restoreIfNeeded() }
    }
}
