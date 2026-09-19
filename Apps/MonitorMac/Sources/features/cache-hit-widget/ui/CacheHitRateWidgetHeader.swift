import MonitorCore
import SwiftUI

struct CacheHitRateWidgetHeader: View {
    let report: CacheHitRateWidgetReport
    let family: CacheHitRateWidgetAppearance.Family
    let appearance: CacheHitRateWidgetAppearance

    var body: some View {
        if family == .small {
            compactHeader
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: CacheHitRateWidgetLayout.headerSpacing) {
                    title.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: CacheHitRateWidgetLayout.headerSpacing)
                    summary
                }
                compactHeader
            }
        }
    }

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: CacheHitRateWidgetLayout.headerSpacing) {
            title
            HStack(alignment: .firstTextBaseline) {
                metric
                Spacer(minLength: CacheHitRateWidgetLayout.headerSpacing)
                delta
            }
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: CacheHitRateWidgetLayout.textSpacing) {
            Text(appearance.copy.title)
                .font(family == .large ? .title.weight(.semibold) : .headline)
                .fixedSize(horizontal: false, vertical: true)
            if family != .small {
                Text(CacheHitRateWidgetText.period(report.period)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .trailing, spacing: CacheHitRateWidgetLayout.textSpacing) {
            metric
            delta
            if family == .large, report.comparisonDeltaPercentagePoints != nil {
                Text(appearance.copy.comparisonLabel).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var metric: some View {
        Text(report.periodCacheHitRate.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "--")
            .font(family == .large ? .largeTitle.weight(.semibold) : .title.weight(.semibold))
            .monospacedDigit()
    }

    @ViewBuilder private var delta: some View {
        if let delta = report.comparisonDeltaPercentagePoints {
            Label {
                Text("\(delta > 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(1)))) pp")
            } icon: {
                Image(systemName: delta == 0 ? "minus" : "triangle.fill")
                    .rotationEffect(delta < 0 ? .degrees(180) : .zero)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(delta == 0 ? Color.secondary
                : delta > 0 ? appearance.palette.improvement : appearance.palette.degradation)
            .fixedSize()
        }
    }
}

enum CacheHitRateWidgetText {
    static func period(_ period: CacheHitRateWidgetPeriod) -> String {
        switch period {
        case .last24Hours: "Last 24 hours"
        case .last7Days: "Last 7 days"
        case .last14Days: "Last 14 days"
        case .last30Days: "Last 30 days"
        }
    }
}
