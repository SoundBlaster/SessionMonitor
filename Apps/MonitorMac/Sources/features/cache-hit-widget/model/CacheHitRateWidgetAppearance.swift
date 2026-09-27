import SwiftUI

/// Semantic appearance values shared by every in-app presentation of the widget.
/// WidgetKit maps the same roles to its environment in SM-401.
struct CacheHitRateWidgetAppearance {
    struct Palette {
        var darkSurface: Color = Color(red: 0.085, green: 0.105, blue: 0.16)
        var lightSurface: Color = Color(red: 0.97, green: 0.98, blue: 1)
        let chart: UsageChartPalette

        var accent: Color { chart.accent }
        var neutral: Color { chart.neutral }
        var average: Color { chart.average }
        var notableOutlier: Color { chart.notable }
        var strongOutlier: Color { chart.warning }
        var improvement: Color { chart.improvement }
        var degradation: Color { chart.degradation }
        var grid: Color { chart.grid }

        static let monochrome = Self(chart: .monochrome)

        static let system = Self(chart: .system)

        init(chart: UsageChartPalette) { self.chart = chart }
    }

    struct Copy: Equatable {
        let title: String
        let rangeLegend: String
        let averageLegend: String
        let outlierLegend: String
        let comparisonLabel: String
        let noDataMessage: String

        static let `default` = Self(
            title: "Cache Hit Rate",
            rangeLegend: "Range (P10 – P90)",
            averageLegend: "Average",
            outlierLegend: "Outlier",
            comparisonLabel: "vs previous period",
            noDataMessage: "No cache data"
        )
    }

    enum Family { case large, medium, small }
    enum ContainerStyle { case card, embedded }

    let palette: Palette
    let copy: Copy

    static let `default` = Self(palette: .system, copy: .default)
}

enum CacheHitRateWidgetLayout {
    static let compactRangeWidth: CGFloat = 8
    static let fullLabelSlotWidth: CGFloat = 32
    static let labelOffset: CGFloat = 12
    static let labelSpace: CGFloat = 24
    static let yAxisLabelGutter: CGFloat = 28
    static let yAxisLabelGap: CGFloat = 4
    static let headerSpacing: CGFloat = 8
    static let textSpacing: CGFloat = 3
    static let borderOpacity = 0.12
    static let cardPadding: CGFloat = 24
    static let compactCardPadding: CGFloat = 12
    static let cardCornerRadius: CGFloat = 28
    static let chartAspectRatio: CGFloat = 16 / 9
    static let rangeWidth: CGFloat = 14
    static let plotVerticalInset: CGFloat = 6
    static let averageSlotHalfWidth = 0.16
    static let minimumRangeArea: CGFloat = 36
    static let outlierArea: CGFloat = 25
}
