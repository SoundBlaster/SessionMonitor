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
                canOpenSession: { id in model.visibleSessions.contains { $0.id == id } },
                openSession: { id in
                    model.selectSession(id)
                    model.navigation.showsFindings = false
                },
                close: { model.navigation.showsFindings = false }
            )
            .task(id: FindingsLoadID(query: model.query, revision: model.snapshot?.watermark.revision)) {
                guard let source = try? await model.findingsSource() else { return }
                await findings.load(query: model.query, source: source)
            }
        }
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
