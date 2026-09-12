import CoreServices
import Foundation
@testable import MonitorRuntime
import Testing

struct FileEventFilterTests {
    @Test(arguments: [
        UInt32(kFSEventStreamEventFlagMustScanSubDirs), UInt32(kFSEventStreamEventFlagUserDropped),
        UInt32(kFSEventStreamEventFlagKernelDropped), UInt32(kFSEventStreamEventFlagEventIdsWrapped),
        UInt32(kFSEventStreamEventFlagRootChanged), UInt32(kFSEventStreamEventFlagMount),
        UInt32(kFSEventStreamEventFlagUnmount)
    ])
    func recoveryBypassesOrdinaryPathFilters(flags: UInt32) throws {
        let filter = FileEventFilter(root: URL(fileURLWithPath: "/logs/root"), excludedPaths: ["/logs/usage.sqlite"])
        let event = try #require(filter.event(path: "/logs/usage.sqlite", flags: flags))
        let reattach = UInt32(kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagUnmount)
        #expect(event.needsReattach == (flags & reattach != 0))
    }

    @Test func ordinaryEventsRespectSubtreeFileTypesAndExactExclusions() {
        let root = "/logs/root"
        let excluded: Set<String> = ["usage.sqlite", "usage.sqlite-wal", "usage.sqlite-shm", "usage.sqlite.import-lock"]
            .reduce(into: []) { $0.insert(root + "/" + $1) }
        let filter = FileEventFilter(root: URL(fileURLWithPath: root), excludedPaths: excluded)
        let file = UInt32(kFSEventStreamEventFlagItemIsFile)
        let directory = UInt32(kFSEventStreamEventFlagItemIsDir)
        for path in [root, root + "/new/sub", root + "/empty"] {
            #expect(filter.event(path: path, flags: directory)?.needsReattach == false)
        }
        for path in [root + "/run.jsonl", root + "/sub/run.jsonl.1", root + "/run.jsonl.012"] {
            #expect(filter.event(path: path, flags: file)?.needsReattach == false)
        }
        for path in excluded.union([
            "/logs/root-other/run.jsonl", "/other/run.jsonl", root + "/run.jsonl.gz",
            root + "/run.jsonl.old", root + "/run.jsonl.-1", root + "/note.txt",
            root + "/.hidden.jsonl", root + "/.cache/run.jsonl"
        ]) {
            #expect(filter.event(path: path, flags: file) == nil)
        }
        for path in excluded { #expect(filter.event(path: path, flags: directory) == nil) }
    }

    @Test func removedRootKeepsItsPhysicalPathIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let physical = FileEventFilter.physicalPath(root)
        let filter = FileEventFilter(root: root, excludedPaths: [])
        try FileManager.default.removeItem(at: root)
        #expect(FileEventFilter.physicalPath(root) == physical)
        #expect(filter.event(path: physical, flags: UInt32(kFSEventStreamEventFlagItemIsDir)) != nil)
    }
}
