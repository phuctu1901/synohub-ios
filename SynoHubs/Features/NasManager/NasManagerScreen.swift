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

    private let gridCols = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.synoBackground.ignoresSafeArea()

                if profiles.isEmpty {
                    emptyState
                } else {
                    nasGrid
                }

                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showingAddNas = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Thêm NAS")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(Color(hex: "003543"))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 13)
                            .background(Color.synoPrimaryContainer)
                            .clipShape(Capsule())
                            .shadow(color: Color.synoPrimaryContainer.opacity(0.4), radius: 12)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 32)
                    }
                }

                if isConnecting {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView()
                        .tint(.synoPrimary)
                        .scaleEffect(1.5)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(Color.synoSurfaceContainer, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingAddNas) { AddNasView() }
            .fullScreenCover(isPresented: $navigateToShell) {
                MainShell(onDisconnect: { navigateToShell = false })
            }
        }
        .onAppear { Task { await pingAll() } }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.synoSurfaceContainerHigh)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "server.rack")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.synoPrimaryContainer)
                    }
                Text("SynoHub")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(.synoCyan400)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { showingAddNas = true }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.synoCyan400)
            }
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.synoPrimaryContainer.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "server.rack")
                    .font(.system(size: 36))
                    .foregroundColor(.synoPrimaryContainer.opacity(0.4))
            }
            Text("Chưa có NAS nào")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.synoOnSurface)
            Text("Nhấn + để thêm thiết bị Synology NAS của bạn")
                .font(.system(size: 13))
                .foregroundColor(.synoOnSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 48)
        }
    }

    // MARK: NAS Grid

    private var nasGrid: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Thiết bị của tôi")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.synoOnSurface)
                    Spacer()
                    Text("\(profiles.count) thiết bị")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.synoSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.synoSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                LazyVGrid(columns: gridCols, spacing: 12) {
                    ForEach(profiles) { profile in
                        NasCardView(
                            profile:  profile,
                            isOnline: onlineStatus[profile.id] ?? false
                        ) {
                            Task { await connect(profile) }
                        } onDelete: {
                            modelContext.delete(profile)
                        }
                        .aspectRatio(0.82, contentMode: .fit)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .padding(.top, 12)
        }
    }

    // MARK: Actions

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
    let onTap:    () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onTap) {
            GlassCard(
                cornerRadius: 20,
                hasGlow:      isOnline,
                borderColor:  isOnline ? .synoSecondary : .synoOutlineVariant,
                padding:      14
            ) {
                VStack(spacing: 0) {
                    // NAS illustration
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.synoSurfaceContainerLowest.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .overlay {
                            Image(systemName: "server.rack")
                                .font(.system(size: 32))
                                .foregroundColor(.synoPrimaryContainer)
                        }

                    Spacer(minLength: 10)

                    // Nickname
                    Text(profile.nickname.isEmpty ? profile.host : profile.nickname)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.synoOnSurface)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)

                    // Address
                    Text(profile.isQuickConnect ? profile.host : "\(profile.host):\(profile.port)")
                        .font(.system(size: 10))
                        .foregroundColor(.synoOnSurfaceVariant)
                        .lineLimit(1)
                        .padding(.top, 2)

                    Spacer(minLength: 6)

                    // Online/offline dot
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isOnline ? Color.synoSecondary : Color.synoError)
                            .frame(width: 6, height: 6)
                        Text(isOnline ? "Trực tuyến" : "Ngoại tuyến")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(isOnline ? .synoSecondary : .synoError)
                    }
                }
            }
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

