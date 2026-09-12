import Foundation

struct MenuWatchPresentation {
    var title = "Watch: not managed by this app"
    var symbol = "questionmark.circle"
    var directory: String?
    var error: String?
    var isRunning = false
    var isPaused = false
    var isBusy = false
}

/// App composition supplies commands; the summary model remains a read-only consumer.
struct MenuSummaryActions {
    var openWindow: () -> Void
    var refresh: () -> Void
    var startWatch: () -> Void
    var togglePause: () -> Void
    var stopWatch: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void
}
