import SwiftUI

enum WidgetDesignTokens {
    static let contentInset: CGFloat = 16
    static let compactInset: CGFloat = 12
    static let sectionSpacing: CGFloat = 10
    static let chartSpacing: CGFloat = 6
    static let compactChartHeight: CGFloat = 62
    static let mediumChartHeight: CGFloat = 92
    static let largeChartHeight: CGFloat = 126
    static let axisLabelWidth: CGFloat = 24
    static let barWidth: CGFloat = 14
    static let compactBarWidth: CGFloat = 10
    static let averageMarkerWidth: CGFloat = 20
    static let largeAverageMarkerWidth: CGFloat = 24
    static let averageMarkerHeight: CGFloat = 2
    static let minimumRangeHeight: CGFloat = 6
    static let outlierDiameter: CGFloat = 6
    static let warningOutlierDiameter: CGFloat = 7
    static let axisFontSize: CGFloat = 9
    static let largeAxisFontSize: CGFloat = 10
    static let bucketLabelHeight: CGFloat = 16
    static let compactBucketLabelHeight: CGFloat = 12
    static let chartAxisInset: CGFloat = 5
    static let axisGutterSpacing: CGFloat = 4
    static let chartGridLineWidth: CGFloat = 0.6
    static let chartBaselineLineWidth: CGFloat = 1
    static let chartGridDashLength: CGFloat = 2
    static let chartGridDashGap: CGFloat = 3
    static let smallOutlierLimit = 2
    static let mediumOutlierLimit = 3
    static let largeOutlierLimit = 4
    static let staleAfter: TimeInterval = 24 * 60 * 60
    static let timelineRefreshInterval: TimeInterval = 12 * 60 * 60
    static let emptyRefreshInterval: TimeInterval = 30 * 60
    static let chartMinimum: Double = 75
    static let chartMaximum: Double = 100
    static let chartAxisTicks: [Double] = [100, 90, 80, 75]

    static let accent = Color.accentColor
    static let warning = Color.red
    static let improvement = Color.green
    static let grid = Color.primary.opacity(0.14)
    static let notableOutlier = Color.secondary.opacity(0.72)
    static let averageMarker = Color.primary
}
