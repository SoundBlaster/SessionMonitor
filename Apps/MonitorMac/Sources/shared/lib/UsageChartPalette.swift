import MonitorCore
import SwiftUI

/// Semantic colors shared by the cache-hit and request-timeline visualizations.
/// Layout and mark semantics stay owned by each chart feature.
struct UsageChartPalette {
    let accent: Color
    let neutral: Color
    let average: Color
    let notable: Color
    let warning: Color
    let improvement: Color
    let degradation: Color
    let grid: Color
    /// Background bands for context fill zones. Opacity is baked in so monochrome stays distinguishable.
    let zoneLow: Color
    let zoneModerate: Color
    let zoneHigh: Color
    let zoneCritical: Color

    func color(for zone: ContextFillZone) -> Color {
        switch zone {
        case .low: zoneLow
        case .moderate: zoneModerate
        case .high: zoneHigh
        case .critical: zoneCritical
        }
    }

    func color(for event: TimelineEventKind) -> Color {
        switch event {
        case .usageRequest: accent
        case .humanTurn: improvement
        case .goalTurn: notable
        case .compaction: warning
        case .tool: neutral
        case .wait: degradation
        case .unknown: average.opacity(0.65)
        }
    }

    static let system = Self(
        accent: .blue,
        neutral: .secondary,
        average: .primary,
        notable: .secondary,
        warning: .red,
        improvement: .green,
        degradation: .orange,
        grid: .secondary.opacity(0.2),
        zoneLow: .green.opacity(0.10),
        zoneModerate: .yellow.opacity(0.12),
        zoneHigh: .orange.opacity(0.14),
        zoneCritical: .red.opacity(0.16)
    )

    static let monochrome = Self(
        accent: .gray,
        neutral: .secondary,
        average: .primary,
        notable: .secondary,
        warning: .red,
        improvement: .primary,
        degradation: .red,
        grid: .secondary.opacity(0.2),
        zoneLow: .gray.opacity(0.04),
        zoneModerate: .gray.opacity(0.09),
        zoneHigh: .gray.opacity(0.16),
        zoneCritical: .gray.opacity(0.26)
    )
}

enum UsageChartPaletteSelection: String, CaseIterable, Identifiable {
    case system
    case monochrome

    static let storageKey = "usageChartPalette"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System colors"
        case .monochrome: "Monochrome"
        }
    }

    var palette: UsageChartPalette {
        switch self {
        case .system: .system
        case .monochrome: .monochrome
        }
    }
}
