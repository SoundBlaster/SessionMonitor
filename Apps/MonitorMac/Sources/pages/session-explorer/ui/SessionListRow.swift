import MonitorCore
import MonitorPolicies
import SwiftUI

struct SessionListRow: View {
    let node: SessionTreeNode
    let provenance: SessionProvenance?
    /// Only values not already present in the row (for example, the sorted request date).
    var sortDetail: String?
    var cacheThreshold: CacheHitThreshold = .default
    var isSelected = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if node.state == .attached {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                SessionListHeading(title: title, model: modelSubtitle, cacheHit: cacheHit,
                                   isLow: isLowCacheHit, isSelected: isSelected)
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
                        .monospaced()
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
        .accessibilityValue("\(cacheAccessibilityValue) \(tokenCount.formatted()) tokens, "
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

    private var isLowCacheHit: Bool {
        if case .knownBelowThreshold = CacheHitThresholdPolicy(threshold: cacheThreshold)
            .presentation(for: node.session) { return true }
        return false
    }

    private var cacheAccessibilityValue: String {
        guard isLowCacheHit else { return cacheHit.accessibilityValue }
        return "Low cache hit. \(cacheHit.accessibilityValue) "
            + "Below the configured \(cacheThreshold.percent.formatted()) percent threshold."
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
    let isLow: Bool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SessionListIdentity(title: title, model: model)
                .frame(maxWidth: .infinity, alignment: .leading)
            SessionListCacheValue(cacheHit: cacheHit, isLow: isLow, isSelected: isSelected)
                .frame(width: 96, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct SessionListIdentity: View {
    let title: String
    let model: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if let model {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.headline).foregroundStyle(.primary).fixedSize()
                    Text(model).fixedSize()
                }
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct SessionListCounts: View {
    let input: Int64
    let output: Int64
    let requests: Int64

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text("Tokens: \(Text(total.formatted()).font(.caption.monospaced()))").fixedSize()
                Spacer(minLength: 8)
                Text("\(Text(requests.formatted()).font(.caption.monospaced())) requests").fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Tokens: \(Text(total.formatted()).font(.caption.monospaced()))")
                Text("\(Text(requests.formatted()).font(.caption.monospaced())) requests")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var total: Decimal { Decimal(input) + Decimal(output) }
}

private struct SessionListCacheValue: View {
    let cacheHit: SessionCacheHitPresentation
    let isLow: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 3) {
            if isLow {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .accessibilityHidden(true)
            }
            Text("Cache \(Text(cacheHit.value).font(.caption.monospaced()).fontWeight(.semibold))")
        }
        .fixedSize()
        .foregroundStyle(isSelected ? Color.white : (isLow ? .orange : .secondary))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(isLow ? Color.orange.opacity(isSelected ? 0.25 : 0.12) : .clear, in: Capsule())
        .help(cacheHit.explanation)
    }
}
