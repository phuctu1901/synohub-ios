import SwiftUI

// MARK: - GlassCard (mirrors Flutter GlassCard exactly)
struct GlassCard<Content: View>: View {
    let cornerRadius:   CGFloat
    let hasGlow:        Bool
    let borderColor:    Color
    let contentPadding: CGFloat
    let content:        Content

    init(
        cornerRadius:   CGFloat = 24,
        hasGlow:        Bool    = false,
        borderColor:    Color   = .synoPrimary,
        padding:        CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius   = cornerRadius
        self.hasGlow        = hasGlow
        self.borderColor    = borderColor
        self.contentPadding = padding
        self.content        = content()
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
    }
}

// MARK: - Legacy glassBackground modifier (backward compat)
extension View {
    func glassBackground(cornerRadius: CGFloat = 20, opacity: Double = 0.5, shadowRadius: CGFloat = 10) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    /// Lightweight glass card modifier – used by all screens
    func glassCard(cornerRadius: CGFloat = 20, borderColor: Color? = nil) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}
