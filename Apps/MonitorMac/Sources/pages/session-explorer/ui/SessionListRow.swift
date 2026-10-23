import MonitorCore
import SwiftUI

struct SessionListRow: View {
    let node: SessionTreeNode
    let provenance: SessionProvenance?
    /// Only values not already present in the row (for example, the sorted request date).
    var sortDetail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if node.state == .attached {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                    SessionListHeading(title: title, model: modelSubtitle, cacheHit: cacheHit, state: stateLabel)
                    SessionListHeading(title: title, model: nil, cacheHit: cacheHit, state: stateLabel)
                    SessionListNarrowHeading(title: title, cacheHit: cacheHit, state: stateLabel)
                }
                Text(node.session.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(node.session.id)
                SessionListCounts(input: node.session.totals.inputTokens,
                                  output: node.session.totals.outputTokens,
                                  requests: node.session.totals.requests)
                if let sortDetail {
                    Text(sortDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(sortDetail)
                }
            }
        }
        .padding(.vertical, 5)
        .help(modelSubtitle.map { "\(title) · \($0)" } ?? title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue("\(cacheHit.accessibilityValue) \(tokenCount.formatted()) tokens, "
                            + "\(node.session.totals.requests.formatted()) requests. \(sortDetail ?? "")")
    }

    private var title: String {
        provenance?.sessionTitle ?? provenance?.displayName
            ?? (node.session.model.isEmpty ? "Unknown model" : node.session.model)
    }

    private var accessibilityTitle: String {
        let model = node.session.model
        let name = model.isEmpty || model == title ? title : "\(title), \(model)"
        return "\(name), \(stateLabel), \(node.session.id)"
    }

    private var modelSubtitle: String? {
        guard provenance?.sessionTitle != nil, !node.session.model.isEmpty,
              node.session.model != title else { return nil }
        return node.session.model
    }

    private var tokenCount: Decimal {
        Decimal(node.session.totals.inputTokens) + Decimal(node.session.totals.outputTokens)
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

private struct SessionListHeading: View {
    let title: String
    let model: String?
    let cacheHit: SessionCacheHitPresentation
    let state: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 54, alignment: .leading)
                .layoutPriority(1)
            if let model {
                Text(model).fixedSize()
                Text("|").accessibilityHidden(true)
            }
            SessionListCacheValue(cacheHit: cacheHit)
            Spacer(minLength: 4)
            Text(state).fixedSize()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

private struct SessionListCounts: View {
    let input: Int64
    let output: Int64
    let requests: Int64

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tokens: \(total.formatted())").fixedSize()
                Spacer(minLength: 8)
                Text("\(requests.formatted()) requests").fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Tokens: \(total.formatted())")
                Text("\(requests.formatted()) requests")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    private var total: Decimal { Decimal(input) + Decimal(output) }
}

private struct SessionListNarrowHeading: View {
    let title: String
    let cacheHit: SessionCacheHitPresentation
    let state: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(state).fixedSize()
            }
            SessionListCacheValue(cacheHit: cacheHit)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

private struct SessionListCacheValue: View {
    let cacheHit: SessionCacheHitPresentation

    var body: some View {
        Text("Cache \(Text(cacheHit.value).fontWeight(.semibold))")
            .fixedSize()
            .help(cacheHit.explanation)
    }
}
