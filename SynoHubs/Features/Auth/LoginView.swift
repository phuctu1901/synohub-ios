import SwiftUI

struct LoginView: View {
    var onLoginSuccess: () -> Void

    @State private var address = ""
    @State private var port = "5001"
    @State private var username = ""
    @State private var password = ""
    @State private var useHttps = true
    @State private var rememberMe = true
    @State private var obscure = true
    @State private var loading = false
    @State private var error: String?
    @State private var showOtp = false
    @State private var otpCode = ""
    @State private var bgPhase: CGFloat = 0

    var body: some View {
        ZStack {
            // Animated gradient background
            animatedBackground
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 40)
                    logoSection
                    Spacer().frame(height: 36)
                    formCard
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 28)
            }
        }
        .onAppear(perform: loadSavedCredentials)
        .alert("2-Step Verification", isPresented: $showOtp) {
            TextField("6-digit code", text: $otpCode)
                .keyboardType(.numberPad)
            Button("Verify") { doLogin(otp: otpCode) }
            Button("Cancel", role: .cancel) { otpCode = "" }
        } message: {
            Text("Enter the 6-digit code from your authenticator app.")
        }
    }

    // MARK: - Background
    private var animatedBackground: some View {
        Color(UIColor.systemGroupedBackground)
            .ignoresSafeArea()
    }

    // MARK: - Logo
    private var logoSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(colors: [.synoPrimary, .synoPrimaryContainer],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 100, height: 100)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .synoPrimaryContainer.opacity(0.35), radius: 40, y: 2)

            Text("SynoHub")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundColor(.synoOnSurface)
            Text("Synology NAS Management")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.synoOnSurfaceVariant)
        }
    }

    // MARK: - Form
    private var formCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            fieldLabel("NAS ADDRESS")
            loginField(icon: "server.rack", placeholder: "IP, hostname, or QuickConnect ID", text: $address)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("PORT")
                    loginField(icon: "number", placeholder: "5001", text: $port)
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("PROTOCOL")
                    protocolToggle
                }
            }

            fieldLabel("USERNAME")
            loginField(icon: "person", placeholder: "admin", text: $username)

            fieldLabel("PASSWORD")
            loginField(icon: "lock", placeholder: "••••••••", text: $password, isSecure: obscure)
                .overlay(alignment: .trailing) {
                    Button { obscure.toggle() } label: {
                        Image(systemName: obscure ? "eye.slash" : "eye")
                            .font(.system(size: 16))
                            .foregroundColor(.synoOnSurfaceVariant)
                            .padding(.trailing, 12)
                    }
                }

            if let error {
                ErrorBanner(message: error) { self.error = nil }
            }

            Toggle(isOn: $rememberMe) {
                Text("Remember Me")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.synoOnSurfaceVariant)
            }
            .toggleStyle(.switch)
            .tint(.synoPrimaryContainer)

            GradientButton(title: "Connect", icon: "link", isLoading: loading) {
                doLogin()
            }
        }
        .padding(24)
        .glassCard(cornerRadius: 28)
    }

    // MARK: - Protocol Toggle
    private var protocolToggle: some View {
        HStack(spacing: 0) {
            protocolChip("HTTP", selected: !useHttps) { useHttps = false }
            protocolChip("HTTPS", selected: useHttps) { useHttps = true }
        }
        .padding(4)
        .glassCard(cornerRadius: 14)
    }

    private func protocolChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(selected ? .synoPrimary : .synoOnSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selected ? Color.synoPrimary.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(2)
            .foregroundColor(.synoOnSurfaceVariant)
    }

    private func loginField(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.synoPrimary)
                .frame(width: 24)
            if isSecure {
                SecureField(placeholder, text: text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.synoOnSurface)
            } else {
                TextField(placeholder, text: text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.synoOnSurface)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.synoSurfaceContainerLowest.opacity(0.3),
                     in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.synoOutlineVariant.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Login Logic
    private func doLogin(otp: String? = nil) {
        let rawAddr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password
        guard !rawAddr.isEmpty, !user.isEmpty, !pass.isEmpty else {
            error = "All fields are required"; return
        }
        guard let portInt = Int(port), portInt > 0, portInt <= 65535 else {
            error = "Invalid port number"; return
        }
        loading = true; error = nil

        Task {
            var host = rawAddr
            var resolvedPort = portInt
            var resolvedHttps = useHttps

            // QuickConnect resolution
            if QuickConnectResolver.isQuickConnect(rawAddr) {
                do {
                    let qc = try await QuickConnectResolver.resolve(QuickConnectResolver.extractId(rawAddr))
                    host = qc.host; resolvedPort = qc.port; resolvedHttps = qc.useHttps
                } catch {
                    await MainActor.run { self.error = "QuickConnect failed: \(error.localizedDescription)"; loading = false }
                    return
                }
            } else {
                // Parse URL
                if host.hasPrefix("https://") { host = String(host.dropFirst(8)); resolvedHttps = true }
                else if host.hasPrefix("http://") { host = String(host.dropFirst(7)); resolvedHttps = false }
                host = host.components(separatedBy: "/").first ?? host
                if let colonIdx = host.lastIndex(of: ":") {
                    let portStr = String(host[host.index(after: colonIdx)...])
                    if let p = Int(portStr) { resolvedPort = p; host = String(host[..<colonIdx]) }
                }
            }

            let result = await SessionManager.shared.login(
                host: host, port: resolvedPort, useHttps: resolvedHttps,
                account: user, password: pass, otpCode: otp
            )
            await MainActor.run {
                loading = false
                if let result {
                    if result == "2FA_REQUIRED" { showOtp = true }
                    else { error = result }
                } else {
                    if rememberMe { saveCredentials() }
                    onLoginSuccess()
                }
            }
        }
    }

    private func saveCredentials() {
        UserDefaults.standard.set(address, forKey: "nas_host")
        UserDefaults.standard.set(port, forKey: "nas_port")
        UserDefaults.standard.set(username, forKey: "nas_user")
        UserDefaults.standard.set(useHttps, forKey: "nas_https")
        try? KeychainManager.shared.save(password: password, for: "synohubs_nas_pass")
    }

    private func loadSavedCredentials() {
        if let h = UserDefaults.standard.string(forKey: "nas_host"), !h.isEmpty {
            address = h
            port = UserDefaults.standard.string(forKey: "nas_port") ?? "5001"
            username = UserDefaults.standard.string(forKey: "nas_user") ?? ""
            useHttps = UserDefaults.standard.bool(forKey: "nas_https")
            password = KeychainManager.shared.getPassword(for: "synohubs_nas_pass") ?? ""
            if !address.isEmpty && !username.isEmpty && !password.isEmpty {
                doLogin()
            }
        }
    }
}
