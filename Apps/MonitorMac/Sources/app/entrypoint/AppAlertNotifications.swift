import Foundation
import MonitorCore
import MonitorRuntime
import UserNotifications

/// Delivers only interrupting transitions (`notify == true`) as macOS notifications.
/// Silent transitions stay in the persisted alert state and `codex-monitor alerts`.
struct UserNotificationAlertSink: AlertSink {
    func deliver(_ events: [AlertEvent]) async {
        let center = UNUserNotificationCenter.current()
        for event in events where event.notify {
            let alert = event.record.candidate
            let content = UNMutableNotificationContent()
            content.title = event.transition == .resolved ? "Resolved: \(alert.title)" : alert.title
            content.body = alert.message
            content.threadIdentifier = alert.source.rawValue
            content.userInfo = ["alertKey": alert.key, "sessionIDs": alert.sessionIDs]
            if alert.severity == .error { content.sound = .default }
            let identifier = "\(alert.key)|\(event.transition.rawValue)|\(event.record.raisedAt.timeIntervalSince1970)"
            try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

/// Shows alert notifications while SessionMonitor is frontmost; without it they would be silent.
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// Tees the single `SessionWatch.updates` stream: the controller keeps receiving every status while
/// the watchdog evaluates alerts after each committed import.
final class AlertingWatchHandle: AppWatchHandle {
    let updates: AsyncStream<WatchStatus>
    private let watch: SessionWatch
    private let forwarding: Task<Void, Never>

    init(watch: SessionWatch, root: URL, watchdog: AlertWatchdog) {
        let (stream, continuation) = AsyncStream<WatchStatus>.makeStream()
        updates = stream
        self.watch = watch
        forwarding = Task {
            for await status in watch.updates {
                continuation.yield(status)
                // Alert evaluation is best effort; the watch and its UI never depend on it.
                _ = try? await watchdog.handle(status, root: root)
            }
            continuation.finish()
        }
    }

    func pause() async { await watch.pause() }
    func resume() async { await watch.resume() }

    func stop() async {
        await watch.stop()
        await forwarding.value
    }
}
