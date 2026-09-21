import MonitorCore
import SwiftUI

struct TimelineEvidenceList: View {
    let points: [RequestTimelinePoint]
    let timeZone: TimeZone
    let palette: UsageChartPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Evidence")
                .font(.headline)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(points) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(palette.color(for: point.kind)).frame(width: 7, height: 7)
                            Text(point.kind.label)
                                .font(.callout)
                            if let cached = point.cachedInputTokens, let uncached = point.uncachedInputTokens {
                                Text("\(cached.formatted()) cached · \(uncached.formatted()) uncached")
                                    .foregroundStyle(.secondary)
                            } else if point.kind == .usageRequest {
                                Text("Unavailable")
                                    .foregroundStyle(palette.warning)
                            } else if let evidence = point.evidence {
                                Text(evidence)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(point.timestamp.formatted(evidenceDateFormat))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 260, alignment: .top)
        }
    }

    private var evidenceDateFormat: Date.FormatStyle {
        let first = points.first?.timestamp ?? .distantPast
        let last = points.last?.timestamp ?? first
        var format = Date.FormatStyle(
            date: last.timeIntervalSince(first) >= 24 * 60 * 60 ? .abbreviated : .omitted,
            time: .standard
        )
        format.timeZone = timeZone
        return format
    }
}
