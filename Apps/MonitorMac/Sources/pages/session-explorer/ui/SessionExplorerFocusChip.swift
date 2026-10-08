import SwiftUI

/// Shows the interval the report is narrowed to; a click shows the whole period again.
struct SessionExplorerFocusChip: View {
    let interval: DateInterval
    let timeZoneIdentifier: String
    let clear: () -> Void

    var body: some View {
        let label = CacheHitRateWidgetBucketDetail.focusLabel(interval, timeZoneIdentifier: timeZoneIdentifier)
        Button(action: clear) {
            Label(label, systemImage: "xmark.circle.fill")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, SessionExplorerSidebarLayout.sectionInset)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Showing only \(label)")
        .accessibilityHint("Show the whole period again.")
    }
}
