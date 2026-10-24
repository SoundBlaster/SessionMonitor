import SwiftUI

/// A form row whose formatted value uses the shared numeric typography; labels stay proportional.
struct DesignNumericRow: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value).monospaced()
        }
    }
}
