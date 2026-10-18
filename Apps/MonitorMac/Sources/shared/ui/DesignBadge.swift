import SwiftUI

/// A passive status label. The caller provides its meaning and semantic tint.
struct DesignBadge: View {
    let title: Text
    var fill: Color = .secondary.opacity(DesignTokens.Badge.backgroundOpacity)

    var body: some View {
        title
            .font(.caption.weight(.medium))
            .padding(.horizontal, DesignTokens.Spacing.item)
            .padding(.vertical, DesignTokens.Spacing.inline)
            .background(fill, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}
