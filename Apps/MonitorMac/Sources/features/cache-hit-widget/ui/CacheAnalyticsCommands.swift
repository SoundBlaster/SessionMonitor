import SwiftUI

extension FocusedValues {
    /// Opens the cache analytics window for the focused Session Explorer, with that explorer's report and scope.
    @Entry var openCacheAnalytics: (() -> Void)?
}

/// View ▸ Show Cache Analytics: the menu path to the window next to the widget's expand button.
struct CacheAnalyticsCommands: Commands {
    @FocusedValue(\.openCacheAnalytics) private var openCacheAnalytics

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Show Cache Analytics") { openCacheAnalytics?() }
                .disabled(openCacheAnalytics == nil)
        }
    }
}
