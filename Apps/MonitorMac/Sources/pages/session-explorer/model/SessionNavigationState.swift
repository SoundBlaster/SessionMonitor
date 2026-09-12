import MonitorCore
import SwiftUI

/// Window-owned selection and presentation state. Native NavigationSplitView behavior
/// was informed by the NavigationSplitView reference described in dogfooding-plan.md;
/// this implementation uses SessionMonitor's own domain models.
struct SessionNavigationState {
    private(set) var selectedSessionID: String?
    var columnVisibility: NavigationSplitViewVisibility = .all
    var showsInspector = false

    mutating func select(_ id: String?, among sessions: [SessionSummary]) {
        selectedSessionID = id.flatMap { candidate in
            sessions.contains { $0.id == candidate } ? candidate : nil
        }
    }

    /// Preserve a visible selection; otherwise select the first visible session.
    /// An empty result clears selection so stale details cannot remain on screen.
    mutating func reconcile(with sessions: [SessionSummary]) {
        if let selectedSessionID, sessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }
        selectedSessionID = sessions.first?.id
    }
}
