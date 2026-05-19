import SwiftUI

struct StorageManagerScreen: View {
    @State private var volumes: [VolumeInfo] = []
    @State private var disks: [DiskInfo] = []
    @State private var totalGb = 0
    @State private var usedGb = 0
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Overall capacity
                overallCapacityCard

                // Volumes
                if !volumes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(text: "Volumes")
                        ForEach(Array(volumes.enumerated()), id: \.offset) { _, v in volumeRow(v) }
                    }
                    .padding(16).glassCard()
                }

                // Disks
                if !disks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SectionTitle(text: "Disk Health")
                            Spacer()
                            if !volumes.isEmpty {
                                StatusBadge(text: volumes[0].raidType.isEmpty ? "BASIC" : volumes[0].raidType.uppercased(),
                                            color: .synoSecondary)
                            }
                        }
                        ForEach(Array(disks.enumerated()), id: \.offset) { i, d in diskRow(i + 1, d) }
                    }
                    .padding(16).glassCard()
                }
            }
            .padding(16)
        }
        .refreshable { await fetchStorage() }
        .background(Color.synoBackground)
        .synoNavBar(title: "Storage Manager", icon: "internaldrive")
        .task { await fetchStorage() }
    }

    private var overallCapacityCard: some View {
        let pct = totalGb > 0 ? Double(usedGb) / Double(totalGb) : 0
        return VStack(spacing: 16) {
            Text("STORAGE CAPACITY")
                .font(.system(size: 10, weight: .semibold)).tracking(2.5).foregroundColor(.synoOnSurfaceVariant)
            ZStack {
                Circle().stroke(Color.synoSurfaceContainerHighest, lineWidth: 12)
                Circle().trim(from: 0, to: pct)
                    .stroke(
                        AngularGradient(colors: [.synoPrimary, .synoPrimaryContainer], center: .center),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: pct)
                VStack(spacing: 2) {
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.synoOnSurface)
                    Text("\(SizeFormatter.formatGb(usedGb)) / \(SizeFormatter.formatGb(totalGb))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.synoOnSurfaceVariant)
                }
            }
            .frame(width: 160, height: 160)
        }
        .frame(maxWidth: .infinity)
        .padding(20).glassCard()
    }

    private func volumeRow(_ v: VolumeInfo) -> some View {
        let pct = v.totalSizeGb > 0 ? Double(v.usedSizeGb) / Double(v.totalSizeGb) : 0
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(v.id).font(.system(size: 12, weight: .semibold)).foregroundColor(.synoOnSurface)
                Text("\(SizeFormatter.formatGb(v.usedSizeGb)) / \(SizeFormatter.formatGb(v.totalSizeGb))")
                    .font(.system(size: 10)).foregroundColor(.synoOnSurfaceVariant)
            }
            Spacer()
            StatusBadge(text: v.status.capitalized, color: v.status == "normal" ? .synoSecondary : .synoTertiary)
            ProgressView(value: pct).frame(width: 60).tint(.synoPrimaryContainer)
        }
    }

    private func diskRow(_ bay: Int, _ d: DiskInfo) -> some View {
        HStack(spacing: 10) {
            IconBadge(icon: d.status == "normal" ? "checkmark.circle" : "exclamationmark.triangle",
                      color: d.status == "normal" ? .synoSecondary : .synoTertiary, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Bay \(bay)").font(.system(size: 11, weight: .bold)).foregroundColor(.synoOnSurface)
                Text(d.model).font(.system(size: 10)).foregroundColor(.synoOnSurfaceVariant).lineLimit(1)
            }
            Spacer()
            if d.temperatureC > 0 {
                Text("\(d.temperatureC)°C").font(.system(size: 10, weight: .semibold)).foregroundColor(.synoTertiary)
            }
            StatusBadge(text: d.status == "normal" ? "Normal" : d.status.capitalized,
                        color: d.status == "normal" ? .synoSecondary : .synoTertiary)
        }
    }

    private func fetchStorage() async {
        guard let api = await SessionManager.shared.api else { return }
        guard let resp = try? await api.getStorageInfo(), resp["success"] as? Bool == true else {
            await MainActor.run { loading = false }; return
        }
        let data = resp["data"] as? [String: Any] ?? [:]
        let vList = data["volumes"] as? [[String: Any]] ?? []
        var tB = 0, uB = 0
        let parsedVols = vList.map { v -> VolumeInfo in
            let sz = v["size"] as? [String: Any] ?? [:]
            let t = parseBytes(sz["total"]); let u = parseBytes(sz["used"])
            tB += t; uB += u
            return VolumeInfo(id: v["id"] as? String ?? v["vol_path"] as? String ?? "",
                              status: v["status"] as? String ?? "normal",
                              raidType: v["fs_type"] as? String ?? "",
                              totalSizeGb: t / (1024*1024*1024), usedSizeGb: u / (1024*1024*1024))
        }
        let dList = data["disks"] as? [[String: Any]] ?? []
        let parsedDisks = dList.map { d in
            DiskInfo(id: d["id"] as? String ?? "", name: d["name"] as? String ?? "",
                     model: d["model"] as? String ?? "Unknown", status: d["status"] as? String ?? "normal",
                     temperatureC: d["temp"] as? Int ?? 0, sizeGb: parseBytes(d["size_total"]) / (1024*1024*1024))
        }
        await MainActor.run {
            volumes = parsedVols; disks = parsedDisks
            totalGb = tB / (1024*1024*1024); usedGb = uB / (1024*1024*1024); loading = false
        }
    }

    private func parseBytes(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s) ?? 0 }
        if let d = v as? Double { return Int(d) }
        return 0
    }
}
