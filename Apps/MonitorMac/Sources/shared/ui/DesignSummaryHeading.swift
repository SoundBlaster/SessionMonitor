import SwiftUI

/// An inline title/accessory heading that stacks when their natural widths cannot fit.
struct DesignSummaryHeading<Title: View, Accessory: View>: View {
    private let title: Title
    private let accessory: Accessory

    init(@ViewBuilder title: () -> Title, @ViewBuilder accessory: () -> Accessory) {
        self.title = title()
        self.accessory = accessory()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.group) {
                title.font(.largeTitle.bold()).fixedSize(horizontal: true, vertical: true)
                accessory.fixedSize(horizontal: true, vertical: true)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
                title.font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                accessory
            }
        }
    }
}
