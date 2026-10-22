import SwiftUI

/// A keyboard-accessible help button with a native dismissible popover.
struct DesignInfoButton<Content: View>: View {
    let title: Text
    private let content: Content
    @State private var isPresented = false

    init(title: Text, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label { title } icon: { Image(systemName: "info.circle") }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
        .popover(isPresented: $isPresented) {
            content
                .padding(DesignTokens.Card.padding)
                .frame(idealWidth: DesignTokens.Layout.helpPopoverWidth,
                       maxWidth: DesignTokens.Layout.helpPopoverWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
