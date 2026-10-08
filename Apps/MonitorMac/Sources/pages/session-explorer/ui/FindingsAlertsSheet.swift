import MonitorCore
import SwiftUI

/// Presents the findings and alerts panel over the explorer and loads it for the current report query.
struct FindingsAlertsSheet: ViewModifier {
    @Bindable var model: SessionExplorerModel
    @State private var findings = FindingsAlertsModel()

    func body(content: Content) -> some View {
        content.sheet(isPresented: $model.navigation.showsFindings) {
            FindingsAlertsPanel(
                model: findings,
                canOpenSession: { id in model.report.sessions.contains { $0.id == id } },
                openSession: { id in
                    // A search filter must not hide the session that was just chosen.
                    if !model.visibleSessions.contains(where: { $0.id == id }) { model.setFilter("") }
                    model.selectSession(id)
                    model.navigation.showsFindings = false
                },
                refresh: { Task { await reload() } },
                close: { model.navigation.showsFindings = false }
            )
            .task(id: FindingsLoadID(query: model.query, revision: model.snapshot?.watermark.revision)) {
                // Alert transitions do not move the usage watermark, so the open panel also polls.
                while !Task.isCancelled {
                    await reload()
                    try? await Task.sleep(for: .seconds(Self.pollInterval))
                }
            }
        }
    }

    private static let pollInterval = 15.0

    private func reload() async {
        guard let source = try? await model.findingsSource() else { return }
        await findings.load(query: model.query, source: source)
    }
}

private struct FindingsLoadID: Hashable {
    let query: UsageQuery
    let revision: Int64?
}

extension View {
    func findingsAlertsSheet(model: SessionExplorerModel) -> some View {
        modifier(FindingsAlertsSheet(model: model))
    }
}
