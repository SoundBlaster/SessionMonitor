import SwiftUI

/// A passive status label. The caller provides its meaning and semantic tint.
struct DesignBadge: View {
    let title: Text
    var fill: Color = .secondary.opacity(DesignTokens.Badge.backgroundOpacity)

    var isNumeric = false

    var body: some View {
        title
            .font(isNumeric ? .caption.weight(.medium).monospaced() : .caption.weight(.medium))
            .padding(.horizontal, DesignTokens.Spacing.item)
            .padding(.vertical, DesignTokens.Spacing.inline)
            .background(fill, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}
