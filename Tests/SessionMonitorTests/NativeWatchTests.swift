import Foundation
import MonitorRuntime
import Testing

struct NativeWatchTests {
    @Test(arguments: ["usage.sqlite", "usage.jsonl"])
    func nativeEventsImportAppendPauseResumeAndIgnoreDatabaseWrites(databaseName: String) async throws {
        let fixture = try NativeWatchFixture()
        defer { fixture.remove() }
        try fixture.write("R1")
        let monitor = try SessionMonitor(databaseURL: fixture.root.appending(path: databaseName))
        let watch = try await monitor.watch(fixture.root, options: WatchOptions(debounce: .milliseconds(40)))
        do {
            try await eventually { try await monitor.report().totals.requests == 1 }
            try fixture.append("R2")
            try await eventually { try await monitor.report().totals.requests == 2 }
            await watch.pause()
            try fixture.append("R3")
            try await Task.sleep(for: .milliseconds(350))
            #expect(try await monitor.report().totals.requests == 2)
            await watch.resume()
            try await eventually { try await monitor.report().totals.requests == 3 }
            try await Task.sleep(for: .milliseconds(700)) // Let any coalesced directory notification settle.
            let completed = await watch.status.completedImports
            try await Task.sleep(for: .milliseconds(500))
            #expect(await watch.status.completedImports == completed)
            await watch.stop()
            try fixture.append("R4")
            try await Task.sleep(for: .milliseconds(250))
            #expect(try await monitor.report().totals.requests == 3)
            #expect(await watch.status.phase == .stopped)
        } catch {
            await watch.stop()
            throw error
        }
    }

    @Test func nativeParentWatchRecoversAfterRootRenameAndRecreation() async throws {
        let fixture = try NativeWatchFixture()
        defer { fixture.remove() }
        try fixture.write("R1")
        let monitor = try SessionMonitor(databaseURL: fixture.directory.appending(path: "usage.sqlite"))
        let options = WatchOptions(debounce: .milliseconds(40), retryDelay: .milliseconds(60),
                                   maximumRetryDelay: .milliseconds(150))
        let watch = try await monitor.watch(fixture.root, options: options)
        do {
            try await eventually { try await monitor.report().totals.requests == 1 }
            try FileManager.default.moveItem(at: fixture.root, to: fixture.directory.appending(path: "archived"))
            try await eventually("missing root becomes recovering") { await watch.status.phase == .recovering }
            try Data("not a directory".utf8).write(to: fixture.root)
            try await eventually("file root remains recovering") {
                await watch.status.error == WatchError.directoryRequired.localizedDescription
            }
            #expect(try await monitor.report().totals.requests == 1)
            try FileManager.default.removeItem(at: fixture.root)
            try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
            try fixture.write("R2")
            try await eventually("recreated root is reconciled") {
                let status = await watch.status
                return status.phase == .watching && status.completedImports >= 2
            }
            let report = try await monitor.report()
            #expect(report.totals.requests == 1) // Same source path replaces its last observed generation.
            #expect(await watch.status.error == nil)
            try fixture.append("R3")
            try await eventually { try await monitor.report().totals.requests == 2 }
            await watch.stop()
        } catch {
            await watch.stop()
            throw error
        }
    }
}

private func eventually(_ context: String = "native watch condition",
                        _ predicate: @escaping @Sendable () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline {
        if try await predicate() { return }
        try await Task.sleep(for: .milliseconds(40))
    }
    throw NativeWatchFailure(context: context)
}

private struct NativeWatchFailure: Error { let context: String }

private struct NativeWatchFixture: Sendable {
    let directory: URL
    var root: URL { directory.appending(path: "rollouts") }
    var file: URL { root.appending(path: "session.jsonl") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // Synthetic native ownership evidence and complete JSONL framing.
    // swiftlint:disable line_length
    func write(_ response: String) throws {
        let header = """
        {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta","payload":{"id":"S","timestamp":"1970-01-01T00:01:40Z"}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started","turn_id":"T","started_at":101}}

        """
        try Data((header + record(response)).utf8).write(to: file, options: .atomic)
    }

    func record(_ response: String) -> String {
        "{\"timestamp\":\"1970-01-01T00:01:42Z\",\"type\":\"token_usage_record\",\"payload\":{\"thread_id\":\"S\",\"turn_id\":\"T\",\"response_id\":\"\(response)\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"output_tokens\":10}}}\n"
    }
    // swiftlint:enable line_length

    func append(_ response: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(record(response).utf8))
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
