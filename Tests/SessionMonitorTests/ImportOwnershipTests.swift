import Foundation
import MonitorRuntime
import Testing

struct ImportOwnershipTests {
    @Test func pausedWatchOwnsImporterAndStopReleasesIt() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        let owner = try SessionMonitor(databaseURL: fixture.database)
        let reader = try SessionMonitor(databaseURL: fixture.database)
        let watch = try await owner.watch(fixture.root)
        await watch.pause()
        do {
            #expect(try await reader.report().totals.requests == 0)
            await expectImporterBusy { _ = try await reader.importDirectory(fixture.root) }
            await expectImporterBusy { _ = try await reader.watch(fixture.root) }
            await expectImporterBusy { _ = try await owner.importDirectory(fixture.root) }
            await watch.stop()
            await watch.stop() // Cleanup must be idempotent and never release another owner's lease.
            _ = try await reader.importDirectory(fixture.root)
            let successor = try await reader.watch(fixture.root)
            await successor.stop()
        } catch {
            await watch.stop()
            throw error
        }
    }

    @Test func danglingDatabaseSymlinkUsesTargetOwnershipOnFirstOpen() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        let alias = fixture.directory.appending(path: "alias.sqlite")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.database)
        #expect(!FileManager.default.fileExists(atPath: fixture.database.path))
        let owner = try SessionMonitor(databaseURL: alias)
        let other = try SessionMonitor(databaseURL: fixture.database)
        let watch = try await owner.watch(fixture.root)
        await watch.pause()
        await expectImporterBusy { _ = try await other.watch(fixture.root) }
        await expectImporterBusy { _ = try await other.importDirectory(fixture.root) }
        await watch.stop()
        _ = try await other.importDirectory(fixture.root)
        #expect(!FileManager.default.fileExists(atPath: alias.path + ".import-lock"))
        #expect(!FileManager.default.fileExists(atPath: alias.path + ".setup-lock"))
    }

    @Test func databaseSymlinkCannotBypassWatchOwnership() async throws {
        let fixture = try OwnershipFixture()
        defer { fixture.remove() }
        let owner = try SessionMonitor(databaseURL: fixture.database)
        let alias = fixture.directory.appending(path: "alias.sqlite")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.database)
        let other = try SessionMonitor(databaseURL: alias)
        let watch = try await owner.watch(fixture.root)
        await watch.pause()
        do {
            await expectImporterBusy { _ = try await other.importDirectory(fixture.root) }
            await expectImporterBusy { _ = try await other.watch(fixture.root) }
            await watch.stop()
            _ = try await other.importDirectory(fixture.root)
        } catch {
            await watch.stop()
            throw error
        }
    }
}

private struct OwnershipFixture {
    let directory: URL
    var root: URL { directory.appending(path: "rollouts") }
    var database: URL { directory.appending(path: "usage.sqlite") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func expectImporterBusy(_ operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected importerBusy while another watch owns the database")
    } catch MonitorError.importerBusy {
        // This is the public contention result, not an unrelated I/O or SQLite failure.
    } catch {
        Issue.record("Unexpected ownership error: \(error)")
    }
}
