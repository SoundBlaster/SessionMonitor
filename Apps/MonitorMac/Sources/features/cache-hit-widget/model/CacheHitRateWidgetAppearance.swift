import SwiftUI

/// Semantic appearance values shared by every in-app presentation of the widget.
/// WidgetKit maps the same roles to its environment in SM-401.
struct CacheHitRateWidgetAppearance {
    struct Palette {
        let accent: Color
        let average: Color
        let notableOutlier: Color
        let strongOutlier: Color
        let improvement: Color
        let degradation: Color

        static let system = Self(
            accent: .blue,
            average: .primary,
            notableOutlier: .secondary,
            strongOutlier: .red,
            improvement: .green,
            degradation: .red
        )
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

    let palette: Palette
    let copy: Copy

    static let `default` = Self(palette: .system, copy: .default)
}

enum CacheHitRateWidgetLayout {
    static let cardPadding: CGFloat = 16
    static let compactCardPadding: CGFloat = 12
    static let cardCornerRadius: CGFloat = 24
    static let chartAspectRatio: CGFloat = 16 / 9
    static let rangeWidth: CGFloat = 14
    static let averageLineWidth: CGFloat = 3
    static let normalOutlierSize: CGFloat = 6
    static let strongOutlierSize: CGFloat = 7
    static let xAxisEdgePadding: CGFloat = 14
    static let xAxisLabelHeight: CGFloat = 14
    static let plotLeadingInset: CGFloat = 32
    static let plotTrailingInset: CGFloat = 8
    static let gridOpacity = 0.20
    static let maximumOutliers = 4
}
