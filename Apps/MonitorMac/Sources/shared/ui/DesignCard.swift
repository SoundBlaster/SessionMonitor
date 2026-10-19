import SwiftUI

/// A surface with content slots. Adds no domain behavior, state, selection, or accessibility grouping.
struct DesignCard<Content: View>: View {
    enum Surface {
        case subdued
        case floating
        case tinted(Color)
    }

    let surface: Surface
    private let content: Content

    init(surface: Surface = .subdued, @ViewBuilder content: () -> Content) {
        self.surface = surface
        self.content = content()
    }

    var body: some View {
        let inset = content
            .padding(DesignTokens.Card.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Card.cornerRadius)
        switch surface {
        case .subdued:
            inset.background(.quaternary.opacity(DesignTokens.Card.subduedOpacity), in: shape)
        case .floating:
            inset.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.quaternary))
                .shadow(color: .black.opacity(DesignTokens.Card.shadowOpacity),
                        radius: DesignTokens.Card.shadowRadius, y: DesignTokens.Card.shadowOffset)
        case let .tinted(color):
            inset.background(color, in: shape)
        }
    }
}
