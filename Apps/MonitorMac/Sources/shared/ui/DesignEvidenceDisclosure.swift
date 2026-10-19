import SwiftUI

/// Evidence expansion stays owned by the caller so extracting the surface cannot reset its state.
struct DesignEvidenceDisclosure<Content: View>: View {
    let title: Text
    @Binding var isExpanded: Bool
    private let content: Content

    init(title: Text, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.item) {
                content
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.top, DesignTokens.Spacing.item)
        } label: {
            title
        }
        .font(.caption)
    }
}
