import SwiftUI

// MARK: - Section Title
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(2)
            .foregroundColor(.synoOnSurfaceVariant)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 9)) }
            Text(text)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Icon Badge (small icon in tinted container)
struct IconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.52))
            .foregroundColor(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

// MARK: - Resource Bar
struct ResourceBar: View {
    let label: String
    let value: Double // 0…1
    let displayValue: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.synoOnSurfaceVariant)
                Spacer()
                Text(displayValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.synoSurfaceContainerHighest)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                        .animation(.easeInOut(duration: 0.5), value: value)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Info Cell (label + value)
struct InfoCell: View {
    let label: String
    let value: String
    var valueColor: Color = .synoOnSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(.synoOnSurfaceVariant)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(valueColor)
                .lineLimit(1)
        }
    }
}

// MARK: - Stat Card (icon + value + label)
struct StatCard: View {
    let icon: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.synoOnSurface)
                    .lineLimit(1)
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(.synoOnSurfaceVariant)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard()
    }
}

// MARK: - Action Button (small tappable icon)
struct ActionButton: View {
    let icon: String
    let color: Color
    var isPending: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isPending {
                    ProgressView().tint(color)
                } else {
                    Image(systemName: icon).font(.system(size: 14))
                }
            }
            .foregroundColor(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .disabled(isPending)
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.synoOnSurfaceVariant.opacity(0.3))
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.synoOnSurface)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.synoOnSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            if let buttonTitle, let buttonAction {
                Button(action: buttonAction) {
                    Label(buttonTitle, systemImage: "plus.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.synoPrimaryContainer)
            }
        }
        .padding(32)
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 14))
            Text(message).font(.system(size: 12, weight: .medium)).lineLimit(3)
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 10))
                }
            }
        }
        .foregroundColor(.synoError)
        .padding(12)
        .background(Color.synoError.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Gradient Button
struct GradientButton: View {
    let title: String
    var icon: String? = nil
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white).scaleEffect(0.8)
                } else {
                    if let icon { Image(systemName: icon).font(.system(size: 16)) }
                    Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundColor(.white)
            .background(
                LinearGradient(colors: [.synoPrimary, .synoPrimaryContainer],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(color: .synoPrimaryContainer.opacity(0.35), radius: 24, y: 8)
        }
        .disabled(isLoading)
    }
}

// MARK: - Search Bar
struct SynoSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(.synoOnSurfaceVariant)
            TextField(placeholder, text: $text)
                .font(.system(size: 13))
                .foregroundColor(.synoOnSurface)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.synoOnSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard()
    }
}

// MARK: - Helpers
extension View {
    func synoNavBar(title: String, icon: String, iconColor: Color = .synoPrimaryContainer) -> some View {
        self.navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        IconBadge(icon: icon, color: iconColor, size: 28)
                        Text(title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.synoOnSurface)
                    }
                }
            }
            .toolbarBackground(Color.synoSurfaceContainer, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Size Formatter
enum SizeFormatter {
    static func format(_ bytes: Int) -> String {
        if bytes <= 0 { return "0 B" }
        if bytes >= 1_099_511_627_776 { return String(format: "%.1f TB", Double(bytes) / 1_099_511_627_776) }
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }
        if bytes >= 1_048_576 { return String(format: "%.0f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.0f KB", Double(bytes) / 1024)
    }

    static func formatGb(_ gb: Int) -> String {
        gb >= 1024 ? String(format: "%.1f TB", Double(gb) / 1024) : "\(gb) GB"
    }
}
