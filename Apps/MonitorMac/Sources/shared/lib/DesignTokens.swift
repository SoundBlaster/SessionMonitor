import SwiftUI

/// Visual values shared by app components. Domain thresholds and chart semantics live in their features.
enum DesignTokens {
    enum Spacing {
        static let micro: CGFloat = 2
        static let inline: CGFloat = 4
        static let item: CGFloat = 8
        static let section: CGFloat = 12
        static let group: CGFloat = 24
    }

    enum Card {
        static let padding: CGFloat = 14
        static let cornerRadius: CGFloat = 12
        static let shadowRadius: CGFloat = 8
        static let shadowOffset: CGFloat = 2
        static let shadowOpacity = 0.15
        static let subduedOpacity = 0.4
        static let separatorWidth: CGFloat = 1
    }

    enum Badge {
        static let backgroundOpacity = 0.10
    }

    enum Layout {
        static let metricMinimumWidth: CGFloat = 150
        static let compactMetricMinimumWidth: CGFloat = 70
        static let pageInset: CGFloat = 28
        static let helpPopoverWidth: CGFloat = 360
    }
}
