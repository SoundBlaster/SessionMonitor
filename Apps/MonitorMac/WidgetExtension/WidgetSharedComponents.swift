import Foundation
import MonitorCore
import SwiftUI
import WidgetKit

enum WidgetFormatting {
    static func periodTitle(_ period: WidgetUsagePeriod) -> String {
        switch period {
        case .today: "Today"
        case .last7Days: "Last 7 days"
        }
    }

    static func bucketTitle(_ date: Date, family: WidgetFamily) -> String {
        date.formatted(.dateTime.weekday(family == .systemSmall ? .narrow : .abbreviated))
    }

    static func percentage(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "--"
    }

    static func updated(_ date: Date) -> String {
        "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }
}

struct WidgetTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WidgetUpdatedLabel: View {
    let entry: SessionMonitorWidgetEntry

    var body: some View {
        HStack(spacing: 4) {
            if entry.isStale {
                Image(systemName: "clock.arrow.circlepath")
                Text("May be out of date")
            } else if let snapshot = entry.snapshot {
                Text(WidgetFormatting.updated(snapshot.generatedAt))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityLabel(entry.isStale ? "Snapshot may be out of date" : "Snapshot updated recently")
    }
}

struct WidgetUnavailableState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignTokens.chartSpacing) {
            Label(title, systemImage: "chart.bar.xaxis")
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
