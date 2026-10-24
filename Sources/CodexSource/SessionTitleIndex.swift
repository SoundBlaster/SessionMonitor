import Foundation

/// Optional Codex sidecar metadata; never derives names from conversation contents.
public enum SessionTitleIndex {
    public static func indexURL(for source: URL) -> URL? {
        var directory = source.deletingLastPathComponent()
        while directory.path != "/" {
            if directory.lastPathComponent == "sessions" {
                return directory.deletingLastPathComponent().appending(path: "session_index.jsonl")
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    /// Codex appends renames; the last valid record for an ID wins. A partial final line is ignored.
    public static func read(_ url: URL) -> [String: String] {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 16 * 1_024 * 1_024, let data = try? Data(contentsOf: url) else { return [:] }
        var titles: [String: String] = [:]
        for line in data.split(separator: 10) {
            guard let record = try? JSONDecoder().decode(SessionTitleIndexEntry.self, from: Data(line))
            else { continue }
            let title = record.threadName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !record.id.isEmpty, !title.isEmpty else { continue }
            titles[record.id] = title
        }
        return titles
    }

}

private struct SessionTitleIndexEntry: Decodable {
    let id: String
    let threadName: String
    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
    }
}
