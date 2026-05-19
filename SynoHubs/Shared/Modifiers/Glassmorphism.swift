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
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.synoSurfaceContainer.opacity(0.55))
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        )
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            borderColor.opacity(hasGlow ? 0.35 : 0.15),
                            lineWidth: hasGlow ? 1.2 : 0.8
                        )
                }
            }
            .shadow(
                color:  borderColor.opacity(hasGlow ? 0.25 : 0.06),
                radius: hasGlow ? 32 : 12
            )
    }
}

// MARK: - Legacy glassBackground modifier (backward compat)
extension View {
    func glassBackground(cornerRadius: CGFloat = 20, opacity: Double = 0.5, shadowRadius: CGFloat = 10) -> some View {
        self.background {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.synoSurfaceContainer.opacity(opacity))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.synoPrimary.opacity(0.15), lineWidth: 0.8)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: shadowRadius)
    }

    /// Lightweight glass card modifier – used by all screens
    func glassCard(cornerRadius: CGFloat = 20, borderColor: Color? = nil) -> some View {
        self.background {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.synoSurfaceContainer.opacity(0.55))
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder((borderColor ?? Color.synoPrimary).opacity(0.15), lineWidth: 0.8)
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 8)
    }
}
