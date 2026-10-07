#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
@testable import MonitorRuntime
import Testing

struct PollingFileEventSourceTests {
    @Test func fingerprintSeesSameSizeReplacementAndMissingRoot() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rollout = root.appending(path: "rollout.jsonl")
        let modified = Date(timeIntervalSince1970: 1_000)
        try Data("first\n".utf8).write(to: rollout)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: rollout.path)
        try Data("ignored".utf8).write(to: root.appending(path: "notes.txt"))

        let before = try #require(PollingFileEventSource.fingerprint(root: root, excludedPaths: []))
        #expect(before.keys.map { URL(fileURLWithPath: $0).lastPathComponent } == ["rollout.jsonl"])

        // Atomic same-size replacement with the old modification time: only identity/ctime differ.
        let replacement = root.appending(path: ".replacement")
        try Data("other\n".utf8).write(to: replacement)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: replacement.path)
        #expect(rename(replacement.path, rollout.path) == 0)
        let after = try #require(PollingFileEventSource.fingerprint(root: root, excludedPaths: []))
        #expect(after != before)

        try FileManager.default.removeItem(at: root)
        #expect(PollingFileEventSource.fingerprint(root: root, excludedPaths: []) == nil)
    }
}
