import SwiftUI

/// Keeps the accessory beside the title when it fits, otherwise moves it below the title.
struct DesignCardHeader<Title: View, Accessory: View>: View {
    private let title: Title
    private let accessory: Accessory

    init(@ViewBuilder title: () -> Title, @ViewBuilder accessory: () -> Accessory) {
        self.title = title()
        self.accessory = accessory()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                title.font(.callout.weight(.semibold))
                Spacer(minLength: DesignTokens.Spacing.item)
                accessory
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
                title.font(.callout.weight(.semibold))
                accessory
            }
        }
    }
}
