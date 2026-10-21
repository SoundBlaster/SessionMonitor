import SwiftUI

/// Equal-width metrics on one shared surface. Compact widths fall back to pairs, then a column.
/// Callers supply stable IDs and formatted text, including unavailable values.
struct DesignMetricStrip: View {
    struct Item: Identifiable {
        let id: String
        let title: Text
        let value: Text
    }

    let items: [Item]

    var body: some View {
        if !items.isEmpty {
            DesignCard {
                ViewThatFits(in: .horizontal) {
                    metricGrid(columns: items.count)
                    metricGrid(columns: 2)
                    metricGrid(columns: 1)
                }
            }
        }
    }

    private func metricGrid(columns: Int) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: DesignTokens.Spacing.section) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(Array(items[start..<min(start + columns, items.count)])) { item in
                        DesignMetric(title: item.title, value: item.value, emphasis: .summary)
                            .fixedSize(horizontal: columns > 1, vertical: true)
                            .padding(.horizontal, DesignTokens.Spacing.section)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .trailing) {
                                if item.id != items[min(start + columns, items.count) - 1].id {
                                    Rectangle().fill(.quaternary)
                                        .frame(width: DesignTokens.Card.separatorWidth)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.title)
                            .accessibilityValue(item.value)
                            .accessibilityIdentifier(item.id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
