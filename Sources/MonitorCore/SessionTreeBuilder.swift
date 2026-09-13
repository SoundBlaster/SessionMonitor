import Foundation

/// Builds the presentation tree from canonical sessions and already persisted provenance.
///
/// This builder deliberately does not inspect usage records and never combines totals.
public enum SessionTreeBuilder {
    public static func build(
        sessions: [SessionSummary],
        provenance: [String: SessionProvenance]
    ) -> [SessionTreeNode] {
        // Reports should already be unique, but keeping the first occurrence makes the
        // builder total and guarantees the one-node-per-session invariant at this boundary.
        var uniqueSessions: [SessionSummary] = []
        var sessionByID: [String: SessionSummary] = [:]
        for session in sessions where sessionByID[session.id] == nil {
            sessionByID[session.id] = session
            uniqueSessions.append(session)
        }

        let ids = Set(uniqueSessions.map(\.id))
        var parentByID: [String: String] = [:]
        for session in uniqueSessions {
            if let parent = provenance[session.id]?.relationship?.parentSessionID, !parent.isEmpty {
                parentByID[session.id] = parent
            }
        }

        let states = Dictionary(uniqueKeysWithValues: uniqueSessions.map { ($0.id, state(for: $0.id, ids: ids,
                                                                                           parentByID: parentByID,
                                                                                           provenance: provenance)) })
        var childrenByParent: [String: [String]] = [:]
        for session in uniqueSessions {
            guard let parent = parentByID[session.id], ids.contains(parent),
                  states[session.id] == .attached else { continue }
            childrenByParent[parent, default: []].append(session.id)
        }

        func node(_ id: String) -> SessionTreeNode? {
            guard let session = sessionByID[id] else { return nil }
            return SessionTreeNode(session: session, state: states[id] ?? .unknown,
                                   children: (childrenByParent[id] ?? []).compactMap(node))
        }

        return uniqueSessions.compactMap { session in
            guard parentByID[session.id] == nil || states[session.id] != .attached else { return nil }
            return node(session.id)
        }
    }

    private static func state(
        for id: String,
        ids: Set<String>,
        parentByID: [String: String],
        provenance: [String: SessionProvenance]
    ) -> SessionTreeState {
        guard provenance[id] != nil else { return .unknown }
        guard let parent = parentByID[id] else { return .knownRoot }
        guard ids.contains(parent) else { return .orphan }

        var path: [String] = [id]
        var current = parent
        while let next = parentByID[current] {
            if path.contains(current) { return .cycle }
            path.append(current)
            current = next
        }
        if path.contains(current) { return .cycle }

        // root_session_id is corroborating evidence only. It cannot create an edge,
        // but a disagreement with an explicit parent relationship is a conflict.
        if let claimedRoot = provenance[id]?.rootSessionID,
           let parentRoot = rootID(startingAt: parent, parentByID: parentByID),
           claimedRoot != parentRoot {
            return .conflict
        }
        return .attached
    }

    private static func rootID(startingAt id: String, parentByID: [String: String]) -> String? {
        var current = id
        var visited = Set<String>()
        while let parent = parentByID[current] {
            guard visited.insert(current).inserted else { return nil }
            current = parent
        }
        return current
    }
}
