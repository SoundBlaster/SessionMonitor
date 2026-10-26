import Foundation

struct SandboxWatchFixture: Sendable {
    let root: URL
    let source: URL
    let index: URL
    let suite = "SessionMonitor.UITests.\(UUID())"

    init(parent: URL) throws {
        root = parent.appending(path: "SandboxSmoke-\(UUID())", directoryHint: .isDirectory)
        source = root.appending(path: "rollouts", directoryHint: .isDirectory)
        index = root.appending(path: "index", directoryHint: .isDirectory)
        for directory in [source, index] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let timestamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        let events: [[String: Any]] = [
            ["timestamp": timestamp, "type": "session_meta", "payload": ["id": "smoke", "timestamp": timestamp]],
            ["timestamp": timestamp, "type": "event_msg",
             "payload": ["type": "task_started", "turn_id": "T",
                         "started_at": Int64(Date().timeIntervalSince1970) - 60]],
            ["timestamp": timestamp, "type": "turn_context", "payload": ["turn_id": "T", "model": "smoke-fixture"]]
        ]
        let data = try events.reduce(into: Data()) { result, event in
            result.append(try JSONSerialization.data(withJSONObject: event))
            result.append(0x0A)
        }
        try data.write(to: source.appending(path: "rollout.jsonl"))
        try append(request: 1)
    }

    func append(request: Int, directory: URL? = nil) throws {
        let event: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()), "type": "token_usage_record",
            "payload": ["thread_id": "smoke", "turn_id": "T", "response_id": "R\(request)",
                        "usage": ["input_tokens": request * 100, "cached_input_tokens": request * 80,
                                  "output_tokens": request * 10]]
        ]
        var data = try JSONSerialization.data(withJSONObject: event)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: (directory ?? source).appending(path: "rollout.jsonl"))
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
