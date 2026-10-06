import AppKit
import UserNotifications

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    var shutdown: (() async -> Void)?
    var replyToTermination: (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    private var terminationRequested = false
    /// Retained here: the notification center keeps only a weak delegate reference.
    private let notificationPresenter = ForegroundNotificationPresenter()

    /// Registered before launch completes, as foreground presentation requires.
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationRequested else { return .terminateLater }
        guard let shutdown else { return .terminateNow }
        terminationRequested = true
        Task {
            await shutdown()
            replyToTermination(true)
        }
        return .terminateLater
    }
}
