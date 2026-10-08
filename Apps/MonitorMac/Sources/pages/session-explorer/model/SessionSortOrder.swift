import Foundation
import MonitorCore

/// How the Sidebar orders sessions. Presentation only: it never changes which sessions are listed or their totals.
enum SessionSortKey: String, CaseIterable, Sendable {
    case firstRequest
    case lastRequest
    case cacheHit
    case requests
    case tokens

    var title: String {
        switch self {
        case .firstRequest: "First request"
        case .lastRequest: "Last request"
        case .cacheHit: "Cache hit rate"
        case .requests: "Requests"
        case .tokens: "Tokens"
        }
    }
}

struct SessionSortOrder: Hashable, Identifiable, Sendable {
    enum Direction: String, Sendable {
        case ascending
        case descending
    }

    let key: SessionSortKey
    let direction: Direction

    static let `default` = SessionSortOrder(key: .tokens, direction: .descending)

    /// Every key in both directions, grouped by key, the first-listed direction being the usual one.
    static let all: [SessionSortOrder] = SessionSortKey.allCases.flatMap { key in
        [Direction.descending, .ascending].map { SessionSortOrder(key: key, direction: $0) }
    }

    var id: String { "\(key.rawValue).\(direction.rawValue)" }
    var rawValue: String { id }

    init(key: SessionSortKey, direction: Direction) {
        self.key = key
        self.direction = direction
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ".").map(String.init)
        guard parts.count == 2, let key = SessionSortKey(rawValue: parts[0]),
              let direction = Direction(rawValue: parts[1]) else { return nil }
        self.init(key: key, direction: direction)
    }

    /// "Last request · newest first"
    var title: String { "\(key.title) · \(directionTitle)" }

    var directionTitle: String {
        switch (key, direction) {
        case (.firstRequest, .ascending), (.lastRequest, .ascending): "oldest first"
        case (.firstRequest, .descending), (.lastRequest, .descending): "newest first"
        case (.cacheHit, .ascending): "lowest first"
        case (.cacheHit, .descending): "highest first"
        case (.requests, .ascending), (.tokens, .ascending): "fewest first"
        case (.requests, .descending), (.tokens, .descending): "most first"
        }
    }

    /// Roots and, inside each parent, children. Equal or unknown values keep a stable order by id.
    func sorted(_ nodes: [SessionTreeNode]) -> [SessionTreeNode] {
        nodes.map { SessionTreeNode(session: $0.session, state: $0.state, children: sorted($0.children)) }
            .sorted { precedes($0.session, $1.session) }
    }

    /// An unknown value (no complete cache coverage, no date) is listed last in either direction and is never
    /// treated as zero.
    func precedes(_ lhs: SessionSummary, _ rhs: SessionSummary) -> Bool {
        switch (value(of: lhs), value(of: rhs)) {
        case let (left?, right?):
            if left != right { return direction == .ascending ? left < right : left > right }
        case (nil, _?): return false
        case (_?, nil): return true
        case (nil, nil): break
        }
        return lhs.id < rhs.id
    }

    func value(of session: SessionSummary) -> Double? {
        switch key {
        case .firstRequest: session.firstRequestAt?.timeIntervalSince1970
        case .lastRequest: session.lastRequestAt?.timeIntervalSince1970
        case .cacheHit: session.totals.cacheHitRatio
        case .requests: Double(session.totals.requests)
        case .tokens: Double(session.totals.inputTokens) + Double(session.totals.outputTokens)
        }
    }

    /// The sorted-by value, for keys the row does not already show.
    func detail(
        for session: SessionSummary, timeZone: TimeZone = .current, locale: Locale = .autoupdatingCurrent
    ) -> String? {
        switch key {
        case .firstRequest, .lastRequest:
            guard let date = key == .firstRequest ? session.firstRequestAt : session.lastRequestAt else {
                return "\(key.title): unknown"
            }
            let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone)
            return "\(key.title): \(date.formatted(style))"
        case .tokens:
            let total = session.totals.inputTokens + session.totals.outputTokens
            return "Tokens: \(total.formatted(.number.locale(locale)))"
        case .cacheHit, .requests:
            return nil
        }
    }
}
