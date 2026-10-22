import SwiftUI

/// A labeled value; formatting and unknown semantics belong to the caller.
struct DesignMetric: View {
    enum Emphasis {
        case compact
        case standard
        case prominent
        case summary

        fileprivate var valueFont: Font {
            switch self {
            case .compact: .caption.weight(.semibold)
            case .standard: .callout.weight(.semibold)
            case .prominent: .title3.weight(.semibold)
            case .summary: .title2.bold()
            }
        }
    }

    let title: Text
    let value: Text
    var emphasis: Emphasis = .standard

    var body: some View {
        VStack(alignment: .leading,
               spacing: emphasis == .compact ? DesignTokens.Spacing.micro : DesignTokens.Spacing.inline) {
            title.font(emphasis == .summary ? .callout : .caption).foregroundStyle(.secondary)
            value.font(emphasis.valueFont).monospacedDigit()
        }
        .frame(maxWidth: emphasis == .compact ? nil : .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
