import SwiftUI

/// One grid keeps both rows aligned, including empty reports and differently sized totals.
struct SessionSidebarTotals: View {
    let sessions: Int64
    let requests: Int64
    let inputTokens: Int64
    let outputTokens: Int64

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            GridRow {
                SessionSidebarTotal(title: "Sessions", value: sessions)
                SessionSidebarTotal(title: "Requests", value: requests, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            GridRow {
                SessionSidebarTotal(title: "Input tokens", value: inputTokens)
                SessionSidebarTotal(title: "Output tokens", value: outputTokens, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SessionSidebarTotal: View {
    let title: LocalizedStringKey
    let value: Int64
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(value, format: .number)
                .font(.headline.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .combine)
    }
}
