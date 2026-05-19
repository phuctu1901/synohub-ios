import SwiftUI

// MARK: - Container Model
struct DockerContainer: Identifiable {
    let id: String
    let name: String
    let image: String
    let status: String
    let upTime: Int
    var cpu: Double?
    var memory: Int?
    var isRunning: Bool { status == "running" }
}

// MARK: - DockerScreen
struct DockerScreen: View {
    @State private var containers: [DockerContainer] = []
    @State private var loading = true
    @State private var available = true
    @State private var error: String?
    @State private var search = ""
    @State private var pendingAction: String?
    @State private var timer: Timer?

    private var filtered: [DockerContainer] {
        let q = search.lowercased()
        return q.isEmpty ? containers : containers.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.image.localizedCaseInsensitiveContains(q)
        }
    }
    private var running: [DockerContainer] { filtered.filter(\.isRunning) }
    private var stopped: [DockerContainer] { filtered.filter { !$0.isRunning } }

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(.synoPrimary)
            } else if !available {
                EmptyStateView(icon: "icloud.slash", title: "Docker Not Available",
                               message: "Container Manager is not installed or not running.\nInstall it from Package Center.")
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.synoBackground)
        .synoNavBar(title: "Docker", icon: "cloud")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { fetchContainers() } label: {
                    Image(systemName: "arrow.clockwise").foregroundColor(.synoOnSurfaceVariant)
                }
            }
        }
        .task { fetchContainers() }
        .onAppear { timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in fetchContainers() } }
        .onDisappear { timer?.invalidate() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                SynoSearchBar(text: $search, placeholder: "Search containers...")
                statsRow
                if let error { ErrorBanner(message: error) { self.error = nil } }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if filtered.isEmpty {
                Spacer()
                EmptyStateView(icon: "cloud", title: search.isEmpty ? "No containers found" : "No results")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !running.isEmpty { sectionLabel("Running (\(running.count))"); ForEach(running) { containerCard($0) } }
                        if !stopped.isEmpty { sectionLabel("Stopped (\(stopped.count))"); ForEach(stopped) { containerCard($0) } }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statBadge("\(containers.count)", "Total", .synoPrimaryContainer)
            statBadge("\(containers.filter(\.isRunning).count)", "Running", .synoSecondary)
            statBadge("\(containers.filter { !$0.isRunning }.count)", "Stopped", .synoOnSurfaceVariant)
        }
    }

    private func statBadge(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundColor(color)
            Text(label).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundColor(.synoOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassCard()
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.synoOnSurfaceVariant)
            Spacer()
        }.padding(.top, 8)
    }

    private func containerCard(_ c: DockerContainer) -> some View {
        let isPending = pendingAction == c.name
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(icon: "cloud", color: c.isRunning ? .synoSecondary : .synoOnSurfaceVariant, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.system(size: 14, weight: .bold)).foregroundColor(.synoOnSurface).lineLimit(1)
                    Text(c.image).font(.system(size: 10)).foregroundColor(.synoOnSurfaceVariant).lineLimit(1)
                }
                Spacer()
                StatusBadge(text: c.isRunning ? "Running" : "Stopped",
                            color: c.isRunning ? .synoSecondary : .synoOnSurfaceVariant,
                            icon: c.isRunning ? "play.fill" : "stop.fill")
            }
            HStack(spacing: 12) {
                if c.isRunning && c.upTime > 0 {
                    Label(formatUptime(c.upTime), systemImage: "clock")
                        .font(.system(size: 10)).foregroundColor(.synoOnSurfaceVariant)
                }
                if let cpu = c.cpu {
                    Label(String(format: "%.1f%%", cpu), systemImage: "cpu")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.synoPrimaryContainer)
                }
                if let mem = c.memory {
                    Label(SizeFormatter.format(mem), systemImage: "memorychip")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(.synoTertiary)
                }
                Spacer()
                if c.isRunning {
                    ActionButton(icon: "arrow.clockwise", color: .synoPrimaryContainer, isPending: isPending) { handleAction(c.name, "restart") }
                    ActionButton(icon: "stop.fill", color: .synoError, isPending: isPending) { handleAction(c.name, "stop") }
                } else {
                    ActionButton(icon: "play.fill", color: .synoSecondary, isPending: isPending) { handleAction(c.name, "start") }
                }
            }
        }
        .padding(14)
        .glassCard(borderColor: c.isRunning ? .synoSecondary.opacity(0.3) : nil)
    }

    // MARK: - Data
    private func fetchContainers() {
        Task {
            guard let api = await SessionManager.shared.api else { return }
            do {
                let resp = try await api.dockerList()
                guard resp["success"] as? Bool == true else {
                    let code = (resp["error"] as? [String: Any])?["code"] as? Int
                    if code == 109 || code == 119 { await MainActor.run { available = false; loading = false } }
                    return
                }
                let rawList = ((resp["data"] as? [String: Any])?["containers"] as? [[String: Any]]) ?? []
                var parsed = rawList.map { m in
                    DockerContainer(id: m["name"] as? String ?? UUID().uuidString,
                                    name: m["name"] as? String ?? "unknown",
                                    image: m["image"] as? String ?? "",
                                    status: (m["status"] as? String ?? "stopped").lowercased(),
                                    upTime: m["up_time"] as? Int ?? 0)
                }
                // Resource usage
                if let resResp = try? await api.dockerGetResources(),
                   resResp["success"] as? Bool == true,
                   let resources = ((resResp["data"] as? [String: Any])?["resources"] as? [[String: Any]]) {
                    for res in resources {
                        let name = res["name"] as? String ?? ""
                        if let idx = parsed.firstIndex(where: { $0.name == name }) {
                            parsed[idx].cpu = (res["cpu"] as? NSNumber)?.doubleValue
                            parsed[idx].memory = (res["memory"] as? NSNumber)?.intValue
                        }
                    }
                }
                await MainActor.run { containers = parsed; loading = false; available = true }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; loading = false }
            }
        }
    }

    private func handleAction(_ name: String, _ action: String) {
        pendingAction = name
        Task {
            guard let api = await SessionManager.shared.api else { return }
            switch action {
            case "start":   _ = try? await api.dockerStart(name)
            case "stop":    _ = try? await api.dockerStop(name)
            case "restart": _ = try? await api.dockerRestart(name)
            default: break
            }
            try? await Task.sleep(for: .seconds(1.5))
            fetchContainers()
            await MainActor.run { pendingAction = nil }
        }
    }

    private func formatUptime(_ s: Int) -> String {
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
