import SwiftUI

// MARK: - Connection Settings
struct ConnectionSettingsView: View {
    @ObservedObject var session = SessionManager.shared
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                infoSection
                if let testResult { testBanner(testResult) }
                GradientButton(title: "Test Connection", icon: "antenna.radiowaves.left.and.right", isLoading: testing) {
                    testConnection()
                }
            }
            .padding(16)
        }
        .background(Color.synoBackground)
        .synoNavBar(title: "Connection", icon: "globe")
    }

    private var infoSection: some View {
        VStack(spacing: 12) {
            infoRow("Host", session.nasInfo?.hostname ?? "N/A")
            infoRow("DSM Version", session.nasInfo?.dsmVersion ?? "N/A")
            infoRow("Serial", session.nasInfo?.serial ?? "N/A")
            infoRow("Uptime", session.nasInfo?.uptimeFormatted ?? "N/A")
        }
        .padding(16).glassCard()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(.synoOnSurfaceVariant)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(.synoOnSurface)
        }
    }

    private func testBanner(_ result: String) -> some View {
        let success = result == "OK"
        return HStack(spacing: 8) {
            Image(systemName: success ? "checkmark.circle" : "xmark.circle").font(.system(size: 14))
            Text(success ? "Connection successful" : result).font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(success ? .synoSecondary : .synoError)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((success ? Color.synoSecondary : Color.synoError).opacity(0.12),
                     in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func testConnection() {
        testing = true; testResult = nil
        Task {
            guard let api = await SessionManager.shared.api else {
                await MainActor.run { testResult = "No active session"; testing = false }; return
            }
            if let resp = try? await api.getDsmInfo(), resp["success"] as? Bool == true {
                await MainActor.run { testResult = "OK"; testing = false }
            } else {
                await MainActor.run { testResult = "Connection failed"; testing = false }
            }
        }
    }
}

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var theme = "dark"
    @AppStorage("appLanguage") private var language = "en"

    private let languages: [(String, String)] = [
        ("en", "English"), ("vi", "Tiếng Việt"), ("zh", "中文"),
        ("ja", "日本語"), ("fr", "Français"), ("pt", "Português")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Theme
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Theme")
                    HStack(spacing: 12) {
                        themeChip("Dark", value: "dark", icon: "moon.fill")
                        themeChip("Light", value: "light", icon: "sun.max.fill")
                        themeChip("System", value: "system", icon: "gearshape")
                    }
                }
                .padding(16).glassCard()

                // Language
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Language")
                    ForEach(languages, id: \.0) { code, name in
                        Button {
                            withAnimation { language = code }
                        } label: {
                            HStack {
                                Text(name).font(.system(size: 14, weight: .medium)).foregroundColor(.synoOnSurface)
                                Spacer()
                                if language == code {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.synoPrimaryContainer)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16).glassCard()
            }
            .padding(16)
        }
        .background(Color.synoBackground)
        .synoNavBar(title: "Appearance", icon: "paintbrush")
    }

    private func themeChip(_ title: String, value: String, icon: String) -> some View {
        let active = theme == value
        return Button { withAnimation { theme = value } } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 20)).foregroundColor(active ? .synoPrimary : .synoOnSurfaceVariant)
                Text(title).font(.system(size: 11, weight: active ? .bold : .medium))
                    .foregroundColor(active ? .synoPrimary : .synoOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(active ? Color.synoPrimary.opacity(0.1) : Color.clear,
                         in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(active ? Color.synoPrimary.opacity(0.25) : Color.synoOutlineVariant.opacity(0.1)))
        }.buttonStyle(.plain)
    }
}

// MARK: - About
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Logo
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(colors: [.synoPrimary, .synoPrimaryContainer],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 90, height: 90)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("SynoHub")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(.synoOnSurface)

                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                Text("Version \(version) (\(build))")
                    .font(.system(size: 13)).foregroundColor(.synoOnSurfaceVariant)

                VStack(spacing: 12) {
                    aboutRow("Platform", UIDevice.current.systemName + " " + UIDevice.current.systemVersion)
                    aboutRow("Device", UIDevice.current.name)
                    aboutRow("Architecture", "arm64")
                }
                .padding(16).glassCard()

                Text("Synology NAS management app.\nBuilt with SwiftUI.")
                    .font(.system(size: 12))
                    .foregroundColor(.synoOnSurfaceVariant)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .background(Color.synoBackground)
        .synoNavBar(title: "About", icon: "info.circle")
    }

    private func aboutRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundColor(.synoOnSurfaceVariant)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(.synoOnSurface)
        }
    }
}
