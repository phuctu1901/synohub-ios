import SwiftUI

// MARK: - DashboardScreen (Apple HIG Design)

struct DashboardScreen: View {
    var onDisconnect: (() -> Void)?

    @ObservedObject private var session = SessionManager.shared
    @State private var isLoading = false

    private var info: NasInfo? { session.nasInfo }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading && info == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let err = session.lastError, info == nil {
                    errorView(err)
                } else if let info {
                    // ① Hero Card
                    deviceHeroCard(info)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // ② Resource Monitor
                    sectionHeader("TÀI NGUYÊN HỆ THỐNG")
                    resourceCard(info)
                        .padding(.horizontal, 16)
                    statsCards(info)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    // ③ Quick Actions
                    sectionHeader("CÔNG CỤ")
                    toolsGrid
                        .padding(.horizontal, 16)

                    Spacer(minLength: 32)
                }
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("SynoHub")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { appBarItems }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var appBarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 12) {
                Button(action: { onDisconnect?() }) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(.blue)
                }
                NavigationLink(destination: SettingsScreen(onDisconnect: onDisconnect)) {
                    Image(systemName: "gear")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: ① Hero Card — Apple Wallet Style

    @ViewBuilder
    private func deviceHeroCard(_ info: NasInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: model + online badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Synology \(info.model)")
                        .font(.title3).fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(info.lanIp)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("ONLINE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.2), in: Capsule())
            }

            Spacer(minLength: 32)

            // Bottom: DSM version + uptime
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PHIÊN BẢN")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text("DSM \(info.dsmVersion)")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("UPTIME")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(info.uptimeFormatted)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.04, green: 0.52, blue: 1.0), Color(red: 0.19, green: 0.13, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "xserve")
                    .font(.system(size: 100, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.08))
                    .offset(x: 100, y: -20)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 16, x: 0, y: 8)
    }

    // MARK: ② Resource Monitor — CPU/RAM + Storage + Services

    @ViewBuilder
    private func resourceCard(_ info: NasInfo) -> some View {
        VStack(spacing: 16) {
            AppleProgressBar(label: "CPU", percentage: info.cpuLoad, color: .blue)
            AppleProgressBar(label: "RAM", percentage: info.ramUsage, color: .green)
            AppleProgressBar(
                label: "Dung lượng",
                percentage: info.storageUsage,
                color: storageColor(info.storageUsage)
            )
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Color shifts from blue → orange → red as storage fills
    private func storageColor(_ usage: Double) -> Color {
        if usage < 0.7 { return .blue }
        if usage < 0.9 { return .orange }
        return .red
    }

    @ViewBuilder
    private func statsCards(_ info: NasInfo) -> some View {
        let totalPkgs = info.packages.count
        let runningPkgs = info.packages.filter(\.isRunning).count
        let storagePercent = Int(info.storageUsage * 100)
        let usedStr = SizeFormatter.formatGb(info.storageUsedGb)
        let totalStr = SizeFormatter.formatGb(info.storageTotalGb)

        HStack(spacing: 10) {
            miniStatCard(
                icon: "thermometer.medium",
                iconColor: .orange,
                label: "Nhiệt độ CPU",
                value: "\(info.temperatureC)°C"
            )
            miniStatCard(
                icon: "internaldrive",
                iconColor: storageColor(info.storageUsage),
                label: "\(usedStr) / \(totalStr)",
                value: "\(storagePercent)%"
            )
        }

        HStack(spacing: 10) {
            miniStatCard(
                icon: "shippingbox",
                iconColor: .indigo,
                label: "Dịch vụ đang chạy",
                value: "\(runningPkgs)/\(totalPkgs)"
            )
            miniStatCard(
                icon: "internaldrive.trianglebadge.exclamationmark",
                iconColor: .purple,
                label: "Ổ đĩa hoạt động",
                value: "\(info.disks.count)"
            )
        }
        .padding(.top, 10)
    }

    private func miniStatCard(icon: String, iconColor: Color, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(iconColor)
            Spacer(minLength: 16)
            Text(label)
                .font(.footnote).fontWeight(.medium)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2).fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(2 / 1.2, contentMode: .fit)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: ③ Quick Actions — Control Center Style

    private var toolsGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
        return LazyVGrid(columns: cols, spacing: 10) {
            controlWidget(icon: "waveform.path.ecg", label: "Tài nguyên", color: .red,
                          destination: AnyView(ResourceMonitorScreen()))
            controlWidget(icon: "cube", label: "Docker", color: .blue,
                          destination: AnyView(DockerScreen()))
            controlWidget(icon: "archivebox", label: "Gói cài đặt", color: .orange,
                          destination: AnyView(PackagesScreen()))
            controlWidget(icon: "person.2", label: "Tài khoản", color: .green,
                          destination: AnyView(UserGroupScreen()))
            controlWidget(icon: "arrow.clockwise", label: "Làm mới", color: .indigo,
                          destination: nil, action: { Task { await refresh() } })
            controlWidget(icon: "doc.text", label: "Nhật ký", color: .gray,
                          destination: AnyView(LogCenterScreen()))
            controlWidget(icon: "internaldrive", label: "Lưu trữ", color: .purple,
                          destination: AnyView(StorageManagerScreen()))
            controlWidget(icon: "photo.on.rectangle.angled", label: "Ảnh", color: .cyan,
                          destination: AnyView(PhotosScreen()))
        }
    }

    @ViewBuilder
    private func controlWidget(icon: String, label: String, color: Color,
                               destination: AnyView? = nil, action: (() -> Void)? = nil) -> some View {
        if let destination {
            NavigationLink(destination: destination) {
                controlWidgetContent(icon: icon, label: label, color: color)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: action ?? {}) {
                controlWidgetContent(icon: icon, label: label, color: color)
            }
            .buttonStyle(.plain)
        }
    }

    private func controlWidgetContent(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(color)
                .clipShape(Circle())
            Text(label)
                .font(.caption2).fontWeight(.medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.footnote).fontWeight(.medium)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text(msg)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Thử lại") { Task { await refresh() } }
                .buttonStyle(.bordered)
                .tint(.blue)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Data

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        await session.refreshData()
    }
}

// MARK: - Apple-style Progress Bar

private struct AppleProgressBar: View {
    let label: String
    let percentage: Double  // 0.0 … 1.0
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(Int(percentage * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(height: 6)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(percentage, 1.0)), height: 6)
                        .animation(.easeInOut(duration: 0.6), value: percentage)
                }
            }
            .frame(height: 6)
        }
    }
}

#Preview {
    NavigationStack { DashboardScreen() }
}
