import SwiftUI

/// Floating card with the hover snapshot. It only draws the lines `ContextAnatomyPresentation` returns;
/// the chart decides where it sits and how wide it is.
struct ContextAnatomySnapshotCard: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
                Text(line).fontWeight(offset == 0 ? .semibold : .regular)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        // VoiceOver reads the same lines from the chart's always-present `contextAnatomy.snapshot` element.
        .accessibilityHidden(true)
    }
}
