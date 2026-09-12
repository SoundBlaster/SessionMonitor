import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    var shutdown: (() async -> Void)?
    var replyToTermination: (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
    private var terminationRequested = false

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
