import MonitorCore
import Testing

struct SessionTreeTests {
    @Test func explicitParentCreatesChildWithoutChangingTotals() {
        let parent = session("parent", requests: 2)
        let child = session("child", requests: 3)
        let tree = SessionTreeBuilder.build(sessions: [parent, child], provenance: [
            "parent": provenance("parent"),
            "child": provenance("child", parent: "parent", root: "parent")
        ])

        #expect(tree.map(\.id) == ["parent"])
        #expect(tree[0].children.map(\.id) == ["child"])
        #expect(tree[0].children[0].state == .attached)
        #expect(tree[0].session.totals.requests == 2)
        #expect(tree[0].children[0].session.totals.requests == 3)
    }

    @Test func missingParentIsRootOrphan() {
        let tree = SessionTreeBuilder.build(sessions: [session("child")], provenance: [
            "child": provenance("child", parent: "missing")
        ])
        #expect(tree.map(\.id) == ["child"])
        #expect(tree[0].state == .orphan)
    }

    @Test func conflictingRootEvidenceIsRootConflict() {
        let tree = SessionTreeBuilder.build(sessions: [session("parent"), session("child")], provenance: [
            "parent": provenance("parent", root: "parent"),
            "child": provenance("child", parent: "parent", root: "other")
        ])
        #expect(tree.map(\.id) == ["parent", "child"])
        #expect(tree[1].state == .conflict)
    }

    @Test func cycleMembersAreRoots() {
        let tree = SessionTreeBuilder.build(sessions: [session("a"), session("b")], provenance: [
            "a": provenance("a", parent: "b"),
            "b": provenance("b", parent: "a")
        ])
        #expect(tree.map(\.id) == ["a", "b"])
        #expect(tree.allSatisfy { $0.state == .cycle })
    }

    @Test func sessionsWithoutProvenanceAreUnknownFlatRoots() {
        let tree = SessionTreeBuilder.build(sessions: [session("one"), session("two")], provenance: [:])
        #expect(tree.map(\.id) == ["one", "two"])
        #expect(tree.allSatisfy { $0.state == .unknown && $0.children.isEmpty })
    }

    @Test func inputOrderAndUniquenessArePreserved() {
        let sessions = [session("b"), session("a"), session("b"), session("c")]
        let tree = SessionTreeBuilder.build(sessions: sessions, provenance: [:])
        #expect(tree.map(\.id) == ["b", "a", "c"])
        #expect(Set(tree.map(\.id)).count == 3)
    }

    private func session(_ id: String, requests: Int64 = 1) -> SessionSummary {
        SessionSummary(id: id, model: "model", totals: UsageTotals(requests: requests))
    }

    private func provenance(_ id: String, parent: String? = nil, root: String? = nil) -> SessionProvenance {
        SessionProvenance(sessionID: id, rootSessionID: root,
                          relationship: parent.map { SessionRelationship(kind: .subagent, parentSessionID: $0) })
    }
}
