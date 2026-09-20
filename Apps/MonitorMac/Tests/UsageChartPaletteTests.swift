import XCTest
@testable import SessionMonitor

final class UsageChartPaletteTests: XCTestCase {
    func testBothChartsResolveTheirSemanticRolesFromOnePalette() {
        for selection in UsageChartPaletteSelection.allCases {
            let palette = selection.palette
            let cacheChart = CacheHitRateWidgetAppearance.Palette(chart: palette)

            XCTAssertEqual(cacheChart.accent, palette.color(for: .usageRequest))
            XCTAssertEqual(cacheChart.average, palette.average)
            XCTAssertEqual(cacheChart.notableOutlier, palette.notable)
            XCTAssertEqual(cacheChart.strongOutlier, palette.warning)
            XCTAssertEqual(palette.color(for: .unknown), palette.average.opacity(0.65))
        }
    }

    func testPaletteChoicesArePersistableAndDifferVisually() {
        XCTAssertEqual(UsageChartPaletteSelection(rawValue: "system"), .system)
        XCTAssertEqual(UsageChartPaletteSelection(rawValue: "monochrome"), .monochrome)
        XCTAssertNil(UsageChartPaletteSelection(rawValue: "unsupported"))
        XCTAssertNotEqual(UsageChartPaletteSelection.system.palette.accent,
                          UsageChartPaletteSelection.monochrome.palette.accent)
        XCTAssertEqual(UsageChartPaletteSelection.storageKey, "usageChartPalette")
    }
}
