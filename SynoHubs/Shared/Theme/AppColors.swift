import SwiftUI

// MARK: - AppColors (Mapped to Apple HIG Semantic Colors)
extension Color {

    // Surface / Background
    static let synoBackground               = Color(UIColor.systemGroupedBackground)
    static let synoSurfaceContainer         = Color(UIColor.secondarySystemGroupedBackground)
    static let synoSurfaceContainerHigh     = Color(UIColor.secondarySystemGroupedBackground)
    static let synoSurfaceContainerHighest  = Color(UIColor.tertiarySystemFill)
    static let synoSurfaceContainerLowest   = Color(UIColor.tertiarySystemGroupedBackground)

    // Primary
    static let synoPrimary                  = Color.blue
    static let synoPrimaryContainer         = Color.blue

    // Secondary
    static let synoSecondary                = Color.green

    // Tertiary
    static let synoTertiary                 = Color.orange

    // Text
    static let synoOnSurface                = Color.primary
    static let synoOnSurfaceVariant         = Color.secondary

    // Secondary
    static let synoSecondaryContainer       = Color(UIColor.secondarySystemGroupedBackground)
    static let synoOnSecondary              = Color.primary

    // Tertiary
    static let synoTertiaryContainer        = Color.orange

    // On Primary
    static let synoOnPrimary                = Color.white

    // Outline
    static let synoOutline                  = Color(UIColor.tertiaryLabel)
    static let synoOutlineVariant           = Color(UIColor.separator)

    // Error
    static let synoError                    = Color.red

    // Convenience
    static let synoCyan400                  = Color.blue
    static let synoSlate950                 = Color(UIColor.systemGroupedBackground)
    static let synoSlate800                 = Color(UIColor.secondarySystemGroupedBackground)
    static let synoSlate500                 = Color.secondary

    // MARK: Hex initializer
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red:     Double(r) / 255,
            green:   Double(g) / 255,
            blue:    Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
