import SwiftUI
import SwiftData

// MARK: - NasManagerScreen

struct NasManagerScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [NasProfile]

    @State private var showingAddNas   = false
    @State private var navigateToShell = false
    @State private var onlineStatus: [UUID: Bool] = [:]
    @State private var isConnecting    = false
    @State private var pulseOpacity    = 0.3

    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Header Section
                        headerView
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        if profiles.isEmpty {
                            emptyState
                                .padding(.top, 60)
                        } else {
                            nasList
                        }
                    }
                    .padding(.bottom, 120)
                }

                // Floating Action Button (FAB)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showingAddNas = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                                Text("Thêm NAS")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .clipShape(Capsule())
                            .shadow(color: Color.blue.opacity(0.35), radius: 24, y: 8)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 40)
                    }
                }

                if isConnecting {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView()
                        .tint(.blue)
                        .scaleEffect(1.5)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddNas) { AddNasView() }
            .fullScreenCover(isPresented: $navigateToShell) {
                MainShell(onDisconnect: { navigateToShell = false })
            }
        }
        .onAppear {
            Task { await pingAll() }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseOpacity = 1.0
            }
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            HStack(spacing: 12) {
                LinearGradient(colors: [.blue, Color(red: 0.1, green: 0.1, blue: 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
                    .overlay(
                        Image(systemName: "server.rack")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                Text("SynoHub")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Spacer()
            Button(action: { showingAddNas = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color(UIColor.tertiarySystemFill), in: Circle())
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 100, height: 100)
                Image(systemName: "server.rack")
                    .font(.system(size: 40))
                    .foregroundColor(.blue.opacity(0.4))
            }
            Text("Chưa có NAS nào")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            Text("Nhấn + để thêm thiết bị Synology NAS của bạn")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
    }

    // MARK: - NAS List
    private var nasList: some View {
        VStack(spacing: 16) {
            // Section Title & Badge
            HStack(alignment: .bottom) {
                Text("Thiết bị của tôi")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                
                let onlineCount = profiles.filter { onlineStatus[$0.id] == true }.count
                HStack(spacing: 6) {
                    Circle()
                        .fill(onlineCount > 0 ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                        .opacity(onlineCount > 0 ? pulseOpacity : 1.0)
                    Text("\(profiles.count) thiết bị")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(UIColor.tertiarySystemFill), in: Capsule())
                .overlay(Capsule().stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1))
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            // Device Cards
            LazyVStack(spacing: 16) {
                ForEach(profiles) { profile in
                    NasCardView(
                        profile:  profile,
                        isOnline: onlineStatus[profile.id] ?? false,
                        pulseOpacity: pulseOpacity
                    ) {
                        Task { await connect(profile) }
                    } onDelete: {
                        modelContext.delete(profile)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Actions
    private func pingAll() async {
        await withTaskGroup(of: (UUID, Bool).self) { group in
            for profile in profiles {
                group.addTask {
                    let ok = await ping(profile)
                    return (profile.id, ok)
                }
            }
            for await (id, ok) in group {
                onlineStatus[id] = ok
            }
        }
    }

    private func ping(_ profile: NasProfile) async -> Bool {
        let scheme = profile.useHttps ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(profile.host):\(profile.port)/webapi/query.cgi?api=SYNO.API.Info&version=1&method=query") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        return (try? await URLSession.shared.data(for: req).1 as? HTTPURLResponse)?.statusCode == 200
    }

    private func connect(_ profile: NasProfile) async {
        isConnecting = true
        defer { isConnecting = false }
        guard let pw = profile.password else { return }
        let err = await SessionManager.shared.login(
            host: profile.host, port: profile.port, useHttps: profile.useHttps,
            account: profile.username, password: pw
        )
        if err == nil {
            navigateToShell = true
        }
    }
}

// MARK: - NAS Card View
private struct NasCardView: View {
    let profile:  NasProfile
    let isOnline: Bool
    let pulseOpacity: Double
    let onTap:    () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Background subtle icon
                Image(systemName: "server.rack")
                    .font(.system(size: 140))
                    .foregroundColor(Color(UIColor.label).opacity(0.03))
                    .offset(x: 20, y: -20)
                
                VStack(spacing: 24) {
                    // Top row: Icon + Status Pill
                    HStack(alignment: .top) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(12)
                            .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        Spacer()

                        // Status Pill
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isOnline ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                                .opacity(isOnline ? pulseOpacity : 1.0)
                            Text(isOnline ? "TRỰC TUYẾN" : "NGOẠI TUYẾN")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(isOnline ? .green : .red)
                                .tracking(0.5)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            (isOnline ? Color.green : Color.red).opacity(0.1),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke((isOnline ? Color.green : Color.red).opacity(0.2), lineWidth: 1))
                    }

                    // Bottom row: Info + Chevron
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.nickname.isEmpty ? profile.host : profile.nickname)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Text(profile.isQuickConnect ? profile.host : "\(profile.host):\(profile.port)")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .background(Color(UIColor.tertiarySystemFill), in: Circle())
                    }
                }
                .padding(20)
            }
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(UIColor.separator).opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Xóa NAS này", systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NasManagerScreen()
        .modelContainer(for: NasProfile.self, inMemory: true)
}
