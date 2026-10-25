import Foundation
import MonitorCore
import MonitorRuntime

/// Database setup, like imports and queries, is performed away from MainActor.
actor SessionMonitorRuntimeLoader {
    private let databaseURL: URL
    private let publishesWidgets: Bool
    private let requiresSharedIndex: Bool
    private let preferencesSuite: String?
    private let indexBookmarks: FolderBookmarkClient
    private var indexLease: SecurityScopedResourceLease?
    private var activeDatabaseURL: URL?
    private var runtime: SharedReportRuntime?
    private var databaseRuntime: MonitorRuntime.SessionMonitor?
    private var watchdog: AlertWatchdog?

    init(databaseURL: URL = MonitorRuntime.SessionMonitor.defaultDatabaseURL, publishesWidgets: Bool = true,
         requiresSharedIndex: Bool = AppFileAccess.requiresBookmarks, preferencesSuite: String? = nil,
         indexBookmarks: FolderBookmarkClient = .readWrite) {
        self.databaseURL = databaseURL
        self.publishesWidgets = publishesWidgets
        self.requiresSharedIndex = requiresSharedIndex
        self.preferencesSuite = preferencesSuite
        self.indexBookmarks = indexBookmarks
    }

    private func database() throws -> MonitorRuntime.SessionMonitor {
        if let databaseRuntime { return databaseRuntime }
        if requiresSharedIndex {
            guard let directory = try indexSettings.restore() else { throw SharedIndexError.selectionRequired }
            return try openIndex(directory)
        }
        let value = try MonitorRuntime.SessionMonitor(databaseURL: databaseURL)
        databaseRuntime = value
        activeDatabaseURL = databaseURL
        return value
    }

    private var indexSettings: SharedIndexSettings {
        let defaults = preferencesSuite.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        return SharedIndexSettings(defaults: defaults, bookmarks: indexBookmarks)
    }

    func restoreIndex() throws -> SharedIndexConnection {
        _ = try database()
        let active = activeDatabaseURL ?? databaseURL
        return SharedIndexConnection(databaseURL: active, selectedDirectory: active.deletingLastPathComponent())
    }

    func selectIndex(_ directory: URL) throws -> SharedIndexConnection {
        let bookmark = try indexSettings.prepare(directory)
        // An open runtime and its streams keep the current index until the next launch.
        if databaseRuntime == nil { _ = try openIndex(directory) }
        indexSettings.commit(directory, bookmark: bookmark)
        return SharedIndexConnection(databaseURL: activeDatabaseURL ?? databaseURL, selectedDirectory: directory)
    }

    private func openIndex(_ directory: URL) throws -> MonitorRuntime.SessionMonitor {
        let lease = SecurityScopedResourceLease(directory, bookmarks: indexBookmarks)
        return try withExtendedLifetime(lease) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: directory.path])
            }
            let url = directory.appending(path: "usage.sqlite")
            let value = try MonitorRuntime.SessionMonitor(databaseURL: url)
            indexLease = lease
            activeDatabaseURL = url
            databaseRuntime = value
            return value
        }
    }

    func watch(_ directory: URL) async throws -> any AppWatchHandle {
        let watch = try await database().watch(directory)
        return AlertingWatchHandle(watch: watch, root: directory, watchdog: try await alertWatchdog())
    }

    /// One watchdog per app process; its center drains the shared alert outbox into macOS notifications.
    private func alertWatchdog() async throws -> AlertWatchdog {
        if let watchdog { return watchdog }
        let monitor = try database()
        let center = AlertCenter(monitor: monitor, sinks: [UserNotificationAlertSink()])
        let value = AlertWatchdog(monitor: monitor, center: center)
        watchdog = value
        await UserNotificationAlertSink.requestAuthorization()
        return value
    }

    func load() async throws -> SharedReportRuntime {
        if let runtime { return runtime }
        let databaseRuntime = try database()
        let runtime = SharedReportRuntime(runtime: databaseRuntime,
                                          widgetSnapshotStore: publishesWidgets ? .appGroup() : nil)
        self.runtime = runtime
        Task { await runtime.publishWidgetSnapshotNow() }
        return runtime
    }

    func accountProfiles() async throws -> [AccountProfile] {
        let runtime = try await load()
        return try await runtime.accountProfiles()
    }
}
