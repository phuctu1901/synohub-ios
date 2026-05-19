import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var session = SessionManager.shared
    var onDisconnect: (() -> Void)?

    var body: some View {
        List {
            // Connection Info
            if let info = session.nasInfo {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(info.model.isEmpty ? "Synology NAS" : info.model)
                                .font(.body).fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text("DSM \(info.dsmVersion)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(info.serial)
                                .font(.caption2).monospaced()
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            Text("Connected")
                                .font(.caption).fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Management
            Section("QUẢN LÝ") {
                settingsRow(icon: "server.rack", title: "NAS Manager", color: .blue) {
                    NasManagerScreen()
                }
                settingsRow(icon: "globe", title: "Kết nối", color: .green) {
                    ConnectionSettingsView()
                }
            }

            // Appearance
            Section("GIAO DIỆN") {
                settingsRow(icon: "paintbrush", title: "Chủ đề & Ngôn ngữ", color: .orange) {
                    AppearanceSettingsView()
                }
            }

            // About
            Section("THÔNG TIN") {
                settingsRow(icon: "info.circle", title: "Về SynoHub", color: .gray) {
                    AboutView()
                }
            }

            // Disconnect
            Section {
                Button(action: disconnect) {
                    HStack {
                        Spacer()
                        Image(systemName: "rectangle.portrait.and.arrow.forward")
                        Text("Ngắt kết nối")
                        Spacer()
                    }
                    .font(.body).fontWeight(.semibold)
                    .foregroundColor(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Cài đặt")
        .navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder
    private func settingsRow<Dest: View>(icon: String, title: String, color: Color,
                                         @ViewBuilder destination: @escaping () -> Dest) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
    }

    private func disconnect() {
        Task { await SessionManager.shared.logout() }
        onDisconnect?()
    }
}
