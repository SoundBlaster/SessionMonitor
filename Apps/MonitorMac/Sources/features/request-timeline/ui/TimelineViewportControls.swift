import NestedA11yIDs
import SwiftUI

struct TimelineViewportControls: View {
    let model: RequestTimelineModel
    let axis: RequestTimelineAxis
    @State private var from = Date.distantPast
    @State private var until = Date.distantFuture
    @State private var isEditingSlider = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { dateFields; applyButton }
                VStack(alignment: .leading) { dateFields; applyButton }
            }
            .environment(\.timeZone, model.displayTimeZone)
            HStack {
                Button { model.pan(by: -0.5) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Earlier range")
                    .disabled(axis.visibleDomain.start <= axis.navigationDomain.start)
                Slider(value: Binding(get: { model.scrollPosition }, set: { model.scroll(to: $0) }),
                       in: 0...1, onEditingChanged: sliderEditingChanged)
                    .accessibilityLabel("Timeline position")
                    .disabled(axis.visibleDomain.duration >= axis.navigationDomain.duration)
                Button { model.pan(by: 0.5) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Later range")
                    .disabled(axis.visibleDomain.end >= axis.navigationDomain.end)
                Button { model.zoom(by: 0.5) } label: { Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel("Zoom in")
                    .disabled(axis.visibleDomain.duration <= TimelineViewport.minimumSpan)
                Button { model.zoom(by: 2) } label: { Image(systemName: "minus.magnifyingglass") }
                    .accessibilityLabel("Zoom out")
                    .disabled(axis.visibleDomain.duration >= axis.navigationDomain.duration)
            }
            if let error = model.rangeError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Text("Dates in \(model.displayTimeZone.identifier) · drag the slider to scroll through time")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .nestedAccessibilityIdentifier("viewportControls")
        .onChange(of: axis.visibleDomain, initial: true) { _, range in
            guard !isEditingSlider else { return }
            from = range.start
            until = range.end
        }
    }

    private func sliderEditingChanged(_ isEditing: Bool) {
        isEditingSlider = isEditing
        guard !isEditing, let range = model.axis?.visibleDomain else { return }
        from = range.start
        until = range.end
    }

    @ViewBuilder
    private var dateFields: some View {
        DatePicker("From", selection: $from, displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.field)
            .nestedAccessibilityIdentifier("from")
            .accessibilityValue(timelineDateLabel(from, timeZone: model.displayTimeZone))
        DatePicker("To", selection: $until, displayedComponents: [.date, .hourAndMinute])
            .datePickerStyle(.field)
            .nestedAccessibilityIdentifier("to")
            .accessibilityValue(timelineDateLabel(until, timeZone: model.displayTimeZone))
    }

    private var applyButton: some View {
        Button("Apply range") { model.applyRange(from: from, to: until) }
            .nestedAccessibilityIdentifier("applyRange")
    }
}
