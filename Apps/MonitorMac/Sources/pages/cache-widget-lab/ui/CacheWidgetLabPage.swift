#if DEBUG
import SwiftUI

/// Uses the production component with synthetic reports; has no runtime/store dependency.
struct CacheWidgetLabPage: View {
    @State private var fixture = CacheHitRateWidgetFixture.reference
    @State private var width = 560.0
    @State private var dark = true
    @State private var monochrome = false
    @State private var customCopy = false
    @State private var largeType = false
    @State private var family = "Large"
    private let families = ["Large", "Medium", "Small"]

    var body: some View {
        VStack(spacing: 16) {
            controls
            ScrollView([.horizontal, .vertical]) {
                CacheHitRateWidget(report: fixture.report, family: selectedFamily, appearance: appearance)
                    .frame(width: width)
                    .environment(\.dynamicTypeSize, largeType ? .accessibility2 : .large)
                    .padding(32)
                    .frame(minWidth: 760, minHeight: 540, alignment: .top)
            }
            .background(dark ? Color(red: 0.04, green: 0.06, blue: 0.13) : Color.gray.opacity(0.08))
            Text("Synthetic fixtures · fixed UTC clock · no database access")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .preferredColorScheme(dark ? .dark : .light)
        .frame(minWidth: 800, minHeight: 680)
    }

    private var controls: some View {
        VStack {
            HStack {
                Picker("Scenario", selection: $fixture) {
                    ForEach(CacheHitRateWidgetFixture.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Family", selection: $family) { ForEach(families, id: \.self) { Text($0) } }
                    .frame(width: 180)
            }
            Toggle("Long custom title and legend", isOn: $customCopy)
            HStack {
                Text("Width \(Int(width)) pt").monospacedDigit()
                Slider(value: $width, in: 220...720, step: 20)
                Toggle("Dark", isOn: $dark)
                Toggle("Monochrome", isOn: $monochrome)
                Toggle("Large text", isOn: $largeType)
            }
        }
    }

    private var selectedFamily: CacheHitRateWidgetAppearance.Family {
        family == "Large" ? .large : family == "Medium" ? .medium : .small
    }

    private var appearance: CacheHitRateWidgetAppearance {
        .init(palette: monochrome ? .monochrome : .system, copy: customCopy ? .init(
            title: "Cache effectiveness across the selected period",
            rangeLegend: "Typical session range (P10 – P90)", averageLegend: "Weighted average",
            outlierLegend: "Exceptional sessions", comparisonLabel: "Compared with the preceding period",
            noDataMessage: "No applicable observations in this period") : .default)
    }
}

#Preview("Widget Lab") { CacheWidgetLabPage() }
#endif
