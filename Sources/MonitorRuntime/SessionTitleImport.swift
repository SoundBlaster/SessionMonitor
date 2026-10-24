import CodexSource
import Foundation
import MonitorCore
import MonitorStore

struct SessionTitleImport {
    let store: UsageStore
    private var indexes: [URL: [String: String]] = [:]

    init(store: UsageStore) { self.store = store }

    mutating func update(path: URL, source: String) throws {
        guard let url = SessionTitleIndex.indexURL(for: path) else { return }
        let titles: [String: String]
        if let cached = indexes[url] {
            titles = cached
        } else {
            titles = SessionTitleIndex.read(url)
            indexes[url] = titles
        }
        try store.updateSessionTitles(source: source, titles: titles)
    }
}

extension SessionMonitor {
    public func accountProfiles() throws -> [AccountProfile] {
        try store.accountProfiles()
    }
}
