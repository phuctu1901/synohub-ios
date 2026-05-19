import SwiftUI

struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let level: String // info, warning, error
    let message: String
    let user: String

    var levelColor: Color {
        switch level.lowercased() {
        case "err", "error", "crit", "alert", "emerg": return .synoError
        case "warning", "warn": return .synoTertiary
        default: return .synoSecondary
        }
    }
    var levelIcon: String {
        switch level.lowercased() {
        case "err", "error", "crit", "alert", "emerg": return "exclamationmark.circle"
        case "warning", "warn": return "exclamationmark.triangle"
        default: return "info.circle"
        }
    }
}

struct LogCenterScreen: View {
    @State private var logs: [LogEntry] = []
    @State private var loading = true
    @State private var filter = "all" // all, error, warning, info
    @State private var offset = 0
    @State private var hasMore = true

    var filteredLogs: [LogEntry] {
        guard filter != "all" else { return logs }
        return logs.filter {
            switch filter {
            case "error": return ["err","error","crit","alert","emerg"].contains($0.level.lowercased())
            case "warning": return ["warning","warn"].contains($0.level.lowercased())
            case "info": return ["info","notice","debug"].contains($0.level.lowercased())
            default: return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All", value: "all")
                    filterChip("Error", value: "error", color: .synoError)
                    filterChip("Warning", value: "warning", color: .synoTertiary)
                    filterChip("Info", value: "info", color: .synoSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if loading && logs.isEmpty {
                Spacer(); ProgressView().tint(.synoPrimary); Spacer()
            } else if filteredLogs.isEmpty {
                Spacer()
                EmptyStateView(icon: "doc.text", title: "No logs", message: "No log entries match the current filter.")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredLogs) { log in logRow(log) }
                        if hasMore {
                            Button("Load More") { loadMore() }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.synoPrimary)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .refreshable { offset = 0; await fetchLogs(reset: true) }
            }
        }
        .background(Color.synoBackground)
        .synoNavBar(title: "Log Center", icon: "doc.text.magnifyingglass")
        .task { await fetchLogs(reset: true) }
    }

    private func filterChip(_ title: String, value: String, color: Color = .synoPrimary) -> some View {
        let active = filter == value
        return Button { withAnimation { filter = value } } label: {
            Text(title)
                .font(.system(size: 12, weight: active ? .bold : .medium))
                .foregroundColor(active ? color : .synoOnSurfaceVariant)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? color.opacity(0.12) : Color.clear,
                             in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(active ? color.opacity(0.25) : Color.synoOutlineVariant.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func logRow(_ log: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: log.levelIcon)
                .font(.system(size: 12))
                .foregroundColor(log.levelColor)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(log.time).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.synoOnSurfaceVariant)
                    Spacer()
                    StatusBadge(text: log.level.uppercased(), color: log.levelColor)
                }
                Text(log.message).font(.system(size: 12)).foregroundColor(.synoOnSurface).lineLimit(3)
                if !log.user.isEmpty {
                    Text(log.user).font(.system(size: 10)).foregroundColor(.synoOnSurfaceVariant)
                }
            }
        }
        .padding(12)
        .glassCard()
    }

    private func fetchLogs(reset: Bool) async {
        if reset { offset = 0 }
        guard let api = await SessionManager.shared.api else { return }
        let resp = (try? await api.getLogs(offset: offset, limit: 50)) ?? [:]
        if resp["success"] as? Bool == true {
            let items = ((resp["data"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
            let parsed = items.map { l in
                let ts = l["time"] as? String ?? l["logtime"] as? String ?? ""
                return LogEntry(time: ts,
                               level: l["level"] as? String ?? l["log_level"] as? String ?? "info",
                               message: l["msg"] as? String ?? l["log"] as? String ?? l["message"] as? String ?? "",
                               user: l["who"] as? String ?? l["user"] as? String ?? "")
            }
            await MainActor.run {
                if reset { logs = parsed } else { logs.append(contentsOf: parsed) }
                hasMore = parsed.count >= 50
                loading = false
            }
        } else {
            await MainActor.run { loading = false }
        }
    }

    private func loadMore() {
        offset += 50
        Task { await fetchLogs(reset: false) }
    }
}
