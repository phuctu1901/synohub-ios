import SwiftUI

struct ResourceMonitorScreen: View {
    @State private var cpuLoad: Double = 0
    @State private var ramUsage: Double = 0
    @State private var ramUsedMb = 0
    @State private var ramTotalMb = 0
    @State private var connections: [[String: Any]] = []
    @State private var loading = true
    @State private var timer: Timer?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // CPU & RAM gauges
                HStack(spacing: 16) {
                    gaugeCard("CPU", value: cpuLoad, color: .synoPrimaryContainer)
                    gaugeCard("RAM", value: ramUsage, color: .synoSecondary,
                              subtitle: "\(ramUsedMb)MB / \(ramTotalMb)MB")
                }

                // Resource bars
                VStack(spacing: 16) {
                    ResourceBar(label: "CPU", value: cpuLoad,
                                displayValue: "\(Int(cpuLoad * 100))%", color: .synoPrimaryContainer)
                    ResourceBar(label: "RAM", value: ramUsage,
                                displayValue: String(format: "%.1f / %.1f GB", Double(ramUsedMb)/1024, Double(ramTotalMb)/1024),
                                color: .synoSecondary)
                }
                .padding(16).glassCard()

                // Active connections
                if !connections.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Active Connections")
                        ForEach(Array(connections.prefix(20).enumerated()), id: \.offset) { _, conn in
                            connectionRow(conn)
                        }
                    }
                    .padding(16).glassCard()
                }
            }
            .padding(16)
        }
        .refreshable { await fetchData() }
        .background(Color.synoBackground)
        .synoNavBar(title: "Resource Monitor", icon: "gauge.with.dots.needle.33percent")
        .task { await fetchData() }
        .onAppear { timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { await fetchData() } } }
        .onDisappear { timer?.invalidate() }
    }

    private func gaugeCard(_ label: String, value: Double, color: Color, subtitle: String? = nil) -> some View {
        VStack(spacing: 8) {
            Gauge(value: value) {
                Text(label).font(.system(size: 9, weight: .bold)).tracking(1.5)
            } currentValueLabel: {
                Text("\(Int(value * 100))%")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(color)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [color.opacity(0.5), color]))
            .scaleEffect(1.6)
            .frame(height: 80)
            if let subtitle {
                Text(subtitle).font(.system(size: 10)).foregroundColor(.synoOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .glassCard()
    }

    private func connectionRow(_ c: [String: Any]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "network").font(.system(size: 12)).foregroundColor(.synoPrimary)
            VStack(alignment: .leading, spacing: 1) {
                Text(c["who"] as? String ?? "Unknown")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.synoOnSurface)
                Text(c["from"] as? String ?? "")
                    .font(.system(size: 10)).foregroundColor(.synoOnSurfaceVariant)
            }
            Spacer()
            Text(c["type"] as? String ?? "")
                .font(.system(size: 10, weight: .medium)).foregroundColor(.synoPrimaryContainer)
        }
    }

    private func fetchData() async {
        guard let api = await SessionManager.shared.api else { return }
        if let util = try? await api.getSystemUtilization(), util["success"] as? Bool == true {
            let data = util["data"] as? [String: Any] ?? [:]
            let cpu = data["cpu"] as? [String: Any] ?? [:]
            let mem = data["memory"] as? [String: Any] ?? [:]
            let userLoad = (cpu["user_load"] as? NSNumber)?.doubleValue ?? 0
            let sysLoad = (cpu["system_load"] as? NSNumber)?.doubleValue ?? 0
            let totalKb = (mem["total_real"] as? NSNumber)?.intValue ?? 0
            let availKb = (mem["avail_real"] as? NSNumber)?.intValue ?? 0
            let bufKb = (mem["buffer"] as? NSNumber)?.intValue ?? 0
            let cachedKb = (mem["cached"] as? NSNumber)?.intValue ?? 0
            let usedKb = totalKb - availKb - bufKb - cachedKb
            await MainActor.run {
                cpuLoad = min(max((userLoad + sysLoad) / 100, 0), 1)
                ramTotalMb = totalKb / 1024
                ramUsedMb = usedKb / 1024
                ramUsage = totalKb > 0 ? Double(usedKb) / Double(totalKb) : 0
                loading = false
            }
        }
        if let conn = try? await api.getCurrentConnections(), conn["success"] as? Bool == true {
            let list = ((conn["data"] as? [String: Any])?["items"] as? [[String: Any]]) ?? []
            await MainActor.run { connections = list }
        }
    }
}
