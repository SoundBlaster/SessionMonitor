import MonitorCore
import SwiftUI

struct SessionListRow: View {
    let node: SessionTreeNode
    let provenance: SessionProvenance?
    /// The value the list is sorted by, when the row does not show it already.
    var sortDetail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(provenance?.displayName ?? (node.session.model.isEmpty ? "Unknown model" : node.session.model))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Text(node.session.id)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(node.session.id)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Cache hit")
                    .foregroundStyle(.secondary)
                Text(cacheHit.value)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(cacheHit.explanation)
                    .accessibilityValue(cacheHit.accessibilityValue)
                Spacer(minLength: 0)
                Text("\(node.session.totals.requests.formatted()) requests")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let sortDetail {
                Text(sortDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            HStack {
                Label(
                    stateLabel,
                    systemImage: node.state == .attached ? "arrow.turn.down.right" : "questionmark.circle"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var cacheHit: SessionCacheHitPresentation {
        SessionCacheHitPresentation(totals: node.session.totals)
    }

    private var stateLabel: String {
        switch node.state {
        case .knownRoot: "Root"
        case .attached: provenance?.relationship?.kind == .subagent ? "Subagent" : "Child"
        case .unknown: "Unknown"
        case .orphan: "Orphan"
        case .conflict: "Conflict"
        case .cycle: "Cycle"
        }
    }
}
