import Foundation
import MonitorCore
import Synchronization
import Testing
@testable import SessionMonitor

@MainActor
struct SavedFolderAccessTests {
    @Test func newInstallationHasNoFolderToRestore() throws {
        let fixture = try FolderAccessFixture()
        defer { fixture.remove() }
        #expect(try fixture.access.restore() == nil)
    }

    @Test func storeBuildRequiresReselectionOfLegacyPath() throws {
        let fixture = try FolderAccessFixture()
        defer { fixture.remove() }
        fixture.defaults.set(fixture.original.path, forKey: fixture.key)
        #expect(throws: SavedFolderAccessError.permissionRequired(fixture.original.path)) {
            try fixture.access.restore()
        }
        #expect(fixture.probe.state.withLock { $0.creates.isEmpty })
        let legacy = SavedFolderAccess(defaults: fixture.defaults, pathKey: fixture.key,
                                       requiresBookmarks: false, bookmarks: fixture.probe.client)
        #expect(try legacy.restore() == fixture.original)
    }

    @Test func reopeningRestoresTheBookmarkURLAfterAFolderMoves() throws {
        let fixture = try FolderAccessFixture()
        defer { fixture.remove() }
        try fixture.access.save(fixture.original)
        fixture.probe.state.withLock { $0.resolvedURL = fixture.moved }
        let reopened = SavedFolderAccess(defaults: fixture.defaults, pathKey: fixture.key,
                                         requiresBookmarks: true, bookmarks: fixture.probe.client)
        #expect(try reopened.restore() == fixture.moved)
        #expect(fixture.defaults.string(forKey: fixture.key) == fixture.moved.path)
    }

    @Test func plainPathSelectionDoesNotReviveAnOlderStoreGrant() throws {
        let fixture = try FolderAccessFixture()
        defer { fixture.remove() }
        fixture.seed()
        let legacy = SavedFolderAccess(defaults: fixture.defaults, pathKey: fixture.key,
                                       requiresBookmarks: false, bookmarks: fixture.probe.client)
        try legacy.save(fixture.moved)
        #expect(try legacy.restore() == fixture.moved)
        #expect(throws: SavedFolderAccessError.permissionRequired(fixture.moved.path)) {
            try fixture.access.restore()
        }
    }

    @Test(arguments: [true, false])
    func staleBookmarkIsRenewedAndOnlyAcquiredAccessIsReleased(acquired: Bool) throws {
        let fixture = try FolderAccessFixture()
        defer { fixture.remove() }
        fixture.seed()
        fixture.probe.state.withLock {
            $0.stale = true
            $0.acquiresAccess = acquired
        }
        #expect(try fixture.access.restore() == fixture.moved)
        #expect(fixture.defaults.data(forKey: fixture.access.bookmarkKey) == Data("renewed".utf8))
        #expect(fixture.probe.state.withLock { $0.starts } == [fixture.moved])
        #expect(fixture.probe.state.withLock { $0.stops } == (acquired ? [fixture.moved] : []))
    }

    @Test func rejectedBookmarkDoesNotFallBackToPreviouslySavedPath() throws {
        let fixture = try FolderAccessFixture()
        defer { fixture.remove() }
        fixture.seed()
        fixture.probe.state.withLock { $0.rejectResolve = true }
        #expect(throws: SavedFolderAccessError.bookmarkUnavailable(fixture.original.path)) {
            try fixture.access.restore()
        }
        #expect(fixture.defaults.string(forKey: fixture.key) == fixture.original.path)
    }

    @Test func failedRenewalKeepsOriginalBookmarkAndReleasesAccess() throws {
        let fixture = try FolderAccessFixture()
        defer { fixture.remove() }
        fixture.seed()
        fixture.probe.state.withLock {
            $0.stale = true
            $0.rejectCreate = true
        }
        #expect(throws: SavedFolderAccessError.bookmarkUnavailable(fixture.original.path)) {
            try fixture.access.restore()
        }
        #expect(fixture.defaults.data(forKey: fixture.access.bookmarkKey) == Data("original".utf8))
        #expect(fixture.defaults.string(forKey: fixture.key) == fixture.original.path)
        #expect(fixture.probe.state.withLock { $0.stops } == [fixture.moved])
    }

    @Test func failedNewSelectionKeepsPreviousFolderAndBookmark() throws {
        let fixture = try FolderAccessFixture()
        defer { fixture.remove() }
        fixture.seed()
        fixture.probe.state.withLock { $0.rejectCreate = true }
        #expect(throws: SavedFolderAccessError.cannotRemember(fixture.moved.path)) {
            try fixture.access.save(fixture.moved)
        }
        #expect(fixture.defaults.string(forKey: fixture.key) == fixture.original.path)
        #expect(fixture.defaults.data(forKey: fixture.access.bookmarkKey) == Data("original".utf8))
        #expect(fixture.probe.state.withLock { $0.stops } == [fixture.moved])
    }

    @Test func invalidSavedImportGrantKeepsStoredReportAndExplainsUpdate() async throws {
        let fixture = try FolderAccessFixture(key: ImportedDirectorySettings.storageKey)
        defer { fixture.remove() }
        fixture.seed()
        fixture.probe.state.withLock { $0.rejectResolve = true }
        let settings = ImportedDirectorySettings(defaults: fixture.defaults, requiresBookmarks: true,
                                                  bookmarks: fixture.probe.client)
        let report = UsageReport(totals: UsageTotals(requests: 7), sessions: [], diagnostics: [:])
        let runtime = StubExplorerRuntime(report: report)
        let model = SessionExplorerModel(runtimeFactory: { runtime }, importedDirectorySettings: settings)
        await model.loadIfNeeded()
        #expect(model.report == report)
        #expect(model.errorMessage?.contains("Choose the folder again") == true)
        await model.update()
        #expect(await runtime.importedDirectories.isEmpty)
        #expect(model.errorMessage?.contains("could not be restored") == true)
    }

    @Test func successfulImportWithUnsavedGrantRetainsResultsAndWarns() async throws {
        let fixture = try FolderAccessFixture(key: ImportedDirectorySettings.storageKey)
        defer { fixture.remove() }
        fixture.probe.state.withLock { $0.rejectCreate = true }
        let settings = ImportedDirectorySettings(defaults: fixture.defaults, requiresBookmarks: true,
                                                  bookmarks: fixture.probe.client)
        let report = UsageReport(totals: UsageTotals(requests: 9), sessions: [], diagnostics: [:])
        let runtime = StubExplorerRuntime(report: report)
        let model = SessionExplorerModel(runtimeFactory: { runtime }, importedDirectorySettings: settings)
        await model.importDirectory(fixture.original)
        #expect(model.importSummary != nil)
        #expect(model.report == report)
        #expect(model.errorMessage?.contains("Import completed") == true)
        #expect(fixture.defaults.data(forKey: fixture.access.bookmarkKey) == nil)
    }

    @Test func watchResumeReportsLegacyPermissionWithoutStartingAWatch() async throws {
        let fixture = try FolderAccessFixture(key: WatchLaunchSettings.directoryKey)
        defer { fixture.remove() }
        fixture.defaults.set(fixture.original.path, forKey: fixture.key)
        let settings = WatchLaunchSettings(defaults: fixture.defaults, requiresBookmarks: true,
                                            bookmarks: fixture.probe.client)
        let controller = AppWatchController { _ in throw FolderFixtureError.unexpectedWatch }
        await controller.startSaved(settings)
        #expect(!controller.isRunning)
        #expect(controller.errorMessage?.contains("grant access") == true)
        fixture.defaults.set(false, forKey: WatchLaunchSettings.startOnLaunchKey)
        #expect(settings.launchDirectory() == nil)
    }

    @Test func watchDoesNotStartIfSelectedFolderGrantCannotBeSaved() async throws {
        let fixture = try FolderAccessFixture(key: WatchLaunchSettings.directoryKey)
        defer { fixture.remove() }
        fixture.probe.state.withLock { $0.rejectCreate = true }
        let settings = WatchLaunchSettings(defaults: fixture.defaults, requiresBookmarks: true,
                                            bookmarks: fixture.probe.client)
        let controller = AppWatchController { _ in throw FolderFixtureError.unexpectedWatch }
        await controller.startSelected(fixture.original, settings: settings)
        #expect(!controller.isRunning)
        #expect(controller.directory == nil)
        #expect(controller.errorMessage?.contains("could not be saved") == true)
    }
}

private struct FolderAccessFixture {
    let suite = "SavedFolderAccessTests.\(UUID())"
    let defaults: UserDefaults
    let key: String
    let original = URL(fileURLWithPath: "/tmp/selected-sessions", isDirectory: true)
    let moved = URL(fileURLWithPath: "/tmp/moved-sessions", isDirectory: true)
    let probe = FolderBookmarkProbe()

    init(key: String = "folder") throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        self.key = key
    }

    var access: SavedFolderAccess {
        SavedFolderAccess(defaults: defaults, pathKey: key, requiresBookmarks: true, bookmarks: probe.client)
    }

    func seed() {
        defaults.set(original.path, forKey: key)
        defaults.set(Data("original".utf8), forKey: access.bookmarkKey)
    }

    func remove() { defaults.removePersistentDomain(forName: suite) }
}

private enum FolderFixtureError: Error { case rejected, unexpectedWatch }

private final class FolderBookmarkProbe: Sendable {
    struct State {
        var resolvedURL = URL(fileURLWithPath: "/tmp/moved-sessions", isDirectory: true)
        var stale = false
        var acquiresAccess = true
        var rejectCreate = false
        var rejectResolve = false
        var creates: [URL] = []
        var starts: [URL] = []
        var stops: [URL] = []
    }

    let state = Mutex(State())

    var client: FolderBookmarkClient {
        FolderBookmarkClient(create: { [self] url in
            try state.withLock {
                $0.creates.append(url)
                if $0.rejectCreate { throw FolderFixtureError.rejected }
                return Data("renewed".utf8)
            }
        }, resolve: { [self] _ in
            try state.withLock {
                if $0.rejectResolve { throw FolderFixtureError.rejected }
                return ($0.resolvedURL, $0.stale)
            }
        }, startAccess: { [self] url in
            state.withLock { $0.starts.append(url); return $0.acquiresAccess }
        }, stopAccess: { [self] url in
            state.withLock { $0.stops.append(url) }
        })
    }
}
