import SwiftUI

struct NasPackage: Identifiable {
    let id: String
    let name: String
    let version: String
    let isRunning: Bool
    var icon: String {
        let l = id.lowercased()
        if l.contains("docker") || l.contains("container") { return "cloud" }
        if l.contains("plex") || l.contains("media") { return "play.circle.fill" }
        if l.contains("download") { return "arrow.down.circle" }
        if l.contains("surveillance") || l.contains("camera") { return "video" }
        if l.contains("photo") { return "photo" }
        if l.contains("audio") || l.contains("music") { return "music.note" }
        if l.contains("drive") { return "folder" }
        if l.contains("hyper") || l.contains("backup") { return "arrow.clockwise.icloud" }
        if l.contains("antivirus") || l.contains("security") { return "shield" }
        return "shippingbox"
    }
}

struct PackagesScreen: View {
    @State private var packages: [NasPackage] = []
    @State private var loading = true
    @State private var search = ""
    @State private var pendingId: String?

    private var filtered: [NasPackage] {
        let q = search.lowercased()
        return q.isEmpty ? packages : packages.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(.synoPrimary)
            } else {
                VStack(spacing: 0) {
                    SynoSearchBar(text: $search, placeholder: "Search packages...")
                        .padding(.horizontal, 16).padding(.top, 12)
                    statsRow.padding(.horizontal, 16).padding(.top, 12)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { pkg in packageRow(pkg) }
                        }
                        .padding(16)
                    }
                    .refreshable { await fetchPackages() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.synoBackground)
        .synoNavBar(title: "Packages", icon: "shippingbox")
        .task { await fetchPackages() }
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statBadge("\(packages.count)", "Total", .synoPrimaryContainer)
            statBadge("\(packages.filter(\.isRunning).count)", "Running", .synoSecondary)
            statBadge("\(packages.filter { !$0.isRunning }.count)", "Stopped", .synoOnSurfaceVariant)
        }
    }

    private func statBadge(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(c)
            Text(l).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundColor(.synoOnSurfaceVariant)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8).glassCard()
    }

    private func packageRow(_ pkg: NasPackage) -> some View {
        let isPending = pendingId == pkg.id
        return HStack(spacing: 12) {
            IconBadge(icon: pkg.icon, color: pkg.isRunning ? .synoPrimary : .synoOnSurfaceVariant)
            VStack(alignment: .leading, spacing: 2) {
                Text(pkg.name).font(.system(size: 14, weight: .bold)).foregroundColor(.synoOnSurface).lineLimit(1)
                Text("v\(pkg.version)").font(.system(size: 10)).foregroundColor(.synoOnSurfaceVariant)
            }
            Spacer()
            StatusBadge(text: pkg.isRunning ? "Running" : "Stopped",
                        color: pkg.isRunning ? .synoSecondary : .synoOnSurfaceVariant)
            if pkg.isRunning {
                ActionButton(icon: "stop.fill", color: .synoError, isPending: isPending) { togglePackage(pkg) }
            } else {
                ActionButton(icon: "play.fill", color: .synoSecondary, isPending: isPending) { togglePackage(pkg) }
            }
        }
        .padding(14)
        .glassCard()
    }

    private func fetchPackages() async {
        guard let api = await SessionManager.shared.api else { return }
        let resp = (try? await api.getPackages()) ?? [:]
        if resp["success"] as? Bool == true {
            let list = ((resp["data"] as? [String: Any])?["packages"] as? [[String: Any]]) ?? []
            let parsed = list.map { p -> NasPackage in
                let add = p["additional"] as? [String: Any] ?? [:]
                let running = add["status"] as? String == "running" || add["running_status"] as? String == "running"
                    || p["status"] as? String == "running" || add["is_running"] as? Bool == true
                return NasPackage(id: p["id"] as? String ?? "",
                                  name: p["dname"] as? String ?? p["name"] as? String ?? "",
                                  version: p["version"] as? String ?? "", isRunning: running)
            }
            await MainActor.run { packages = parsed; loading = false }
        } else {
            await MainActor.run { loading = false }
        }
    }

    private func togglePackage(_ pkg: NasPackage) {
        pendingId = pkg.id
        Task {
            guard let api = await SessionManager.shared.api else { return }
            _ = pkg.isRunning ? try? await api.packageStop(pkg.id) : try? await api.packageStart(pkg.id)
            try? await Task.sleep(for: .seconds(1.5))
            await fetchPackages()
            await MainActor.run { pendingId = nil }
        }
    }
}
