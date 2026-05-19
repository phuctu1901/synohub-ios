import Foundation
import Combine

// MARK: - Parsed NAS Info
struct NasInfo {
    let model: String
    let dsmVersion: String
    let serial: String
    let hostname: String
    let uptimeSeconds: Int
    let temperatureC: Int
    let cpuLoad: Double  // 0…1
    let ramTotalMb: Int
    let ramUsedMb: Int
    let storageTotalGb: Int
    let storageUsedGb: Int
    let volumes: [VolumeInfo]
    let disks: [DiskInfo]
    let lanIp: String
    let packages: [PackageInfo]

    var ramUsage: Double { ramTotalMb > 0 ? Double(ramUsedMb) / Double(ramTotalMb) : 0 }
    var storageUsage: Double { storageTotalGb > 0 ? Double(storageUsedGb) / Double(storageTotalGb) : 0 }
    var uptimeFormatted: String {
        let d = uptimeSeconds / 86400; let h = (uptimeSeconds % 86400) / 3600
        return d > 0 ? "\(d) Days, \(h) Hours" : "\(h) Hours"
    }
}

struct VolumeInfo {
    let id: String, status: String, raidType: String, totalSizeGb: Int, usedSizeGb: Int
}
struct DiskInfo {
    let id: String, name: String, model: String, status: String, temperatureC: Int, sizeGb: Int
}
struct PackageInfo: Identifiable {
    let id: String, name: String, version: String, isRunning: Bool
}

// MARK: - SessionManager
/// Singleton holding login state and NAS data. Publishes changes via Combine.
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()
    private init() {}

    @Published var api: SynologyAPI?
    @Published var nasInfo: NasInfo?
    @Published var lastError: String?
    @Published var isAdmin: Bool = false

    private(set) var host = ""
    private(set) var port = 5001
    private(set) var useHttps = true
    private(set) var account = ""
    private(set) var password = ""

    var isLoggedIn: Bool { api != nil }

    /// Returns nil on success, or error string. Returns "2FA_REQUIRED" for OTP prompt.
    func login(host: String, port: Int, useHttps: Bool, account: String, password: String, otpCode: String? = nil) async -> String? {
        self.host = host; self.port = port; self.useHttps = useHttps
        self.account = account; self.password = password; lastError = nil

        let newApi = SynologyAPI(host: host, port: port, useHttps: useHttps)
        do {
            let resp = try await newApi.login(account: account, passwd: password, otpCode: otpCode)
            if resp["success"] as? Bool != true {
                let code = (resp["error"] as? [String: Any])?["code"] as? Int
                if code == 403 || code == 406 { api = nil; return "2FA_REQUIRED" }
                let msg = authErrorMessage(code)
                lastError = msg; api = nil; return msg
            }
            api = newApi
            isAdmin = await newApi.checkAdmin()
            await refreshData()
            return nil
        } catch {
            lastError = error.localizedDescription; api = nil
            return lastError
        }
    }

    func refreshData() async {
        guard let api else { return }
        do {
            if isAdmin {
                async let dsmResp = api.getDsmInfo()
                async let utilResp = api.getSystemUtilization()
                async let storResp = api.getStorageInfo()
                async let pkgResp = api.getPackages()
                let (dsm, util, stor, pkg) = try await (dsmResp, utilResp, storResp, pkgResp)
                nasInfo = parseNasInfo(
                    dsm: dsm["data"] as? [String: Any] ?? [:],
                    util: util["data"] as? [String: Any] ?? [:],
                    storage: stor["data"] as? [String: Any] ?? [:],
                    pkg: pkg["data"] as? [String: Any] ?? [:]
                )
            } else {
                let dsmResp = (try? await api.getDsmInfo()) ?? [:]
                let dsmData = dsmResp["success"] as? Bool == true ? dsmResp["data"] as? [String: Any] ?? [:] : [:]
                nasInfo = parseNasInfo(dsm: dsmData, util: [:], storage: [:], pkg: [:])
            }
            lastError = nil
        } catch {
            lastError = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func logout() async {
        if let api { await api.logout() }
        api = nil; nasInfo = nil; lastError = nil; isAdmin = false; password = ""
        // Clear keychain
        try? KeychainManager.shared.deletePassword(for: "synohubs_nas_pass")
    }

    // MARK: - Parsing
    private func parseNasInfo(dsm: [String: Any], util: [String: Any], storage: [String: Any], pkg: [String: Any]) -> NasInfo {
        let model = dsm["model"] as? String ?? "Unknown"
        let dsmVersion = dsm["version_string"] as? String ?? "DSM \(dsm["version"] ?? "")"
        let serial = dsm["serial"] as? String ?? ""
        let hostname = dsm["hostname"] as? String ?? ""
        let uptime = dsm["uptime"] as? Int ?? 0
        let temp = dsm["temperature"] as? Int ?? 0

        // CPU
        let cpu = util["cpu"] as? [String: Any] ?? [:]
        let cpuUser = (cpu["user_load"] as? NSNumber)?.doubleValue ?? 0
        let cpuSys = (cpu["system_load"] as? NSNumber)?.doubleValue ?? 0
        let cpuLoad = min(max((cpuUser + cpuSys) / 100.0, 0), 1)

        // Memory
        let mem = util["memory"] as? [String: Any] ?? [:]
        let ramTotalKb = (mem["total_real"] as? NSNumber)?.intValue ?? 0
        let ramAvail = (mem["avail_real"] as? NSNumber)?.intValue ?? 0
        let ramBuffer = (mem["buffer"] as? NSNumber)?.intValue ?? 0
        let ramCached = (mem["cached"] as? NSNumber)?.intValue ?? 0
        let physicalRamMb = (dsm["ram_size"] as? NSNumber)?.intValue ?? 0
        let ramTotalMb = physicalRamMb > 0 ? physicalRamMb : ramTotalKb / 1024
        let ramUsedKb = ramTotalKb - ramAvail - ramBuffer - ramCached
        let ramUsedMb = ramTotalKb > 0 ? ramUsedKb / 1024 : 0

        // Volumes
        let volumesList = storage["volumes"] as? [[String: Any]] ?? []
        var totalBytes = 0, usedBytes = 0
        var volumes: [VolumeInfo] = []
        for v in volumesList {
            let tB = parseSizeBytes(v["size"].flatMap { ($0 as? [String: Any])?["total"] })
            let uB = parseSizeBytes(v["size"].flatMap { ($0 as? [String: Any])?["used"] })
            totalBytes += tB; usedBytes += uB
            volumes.append(VolumeInfo(
                id: v["id"] as? String ?? v["vol_path"] as? String ?? "",
                status: v["status"] as? String ?? "normal",
                raidType: v["fs_type"] as? String ?? "",
                totalSizeGb: tB / (1024*1024*1024), usedSizeGb: uB / (1024*1024*1024)
            ))
        }

        // Disks
        let disksList = storage["disks"] as? [[String: Any]] ?? []
        let disks: [DiskInfo] = disksList.map { d in
            DiskInfo(id: d["id"] as? String ?? "", name: d["name"] as? String ?? d["id"] as? String ?? "",
                     model: d["model"] as? String ?? "Unknown", status: d["status"] as? String ?? "normal",
                     temperatureC: d["temp"] as? Int ?? 0, sizeGb: parseSizeBytes(d["size_total"]) / (1024*1024*1024))
        }

        // Packages
        let pkgList = pkg["packages"] as? [[String: Any]] ?? []
        let packages: [PackageInfo] = pkgList.map { p in
            let add = p["additional"] as? [String: Any] ?? [:]
            let running = add["status"] as? String == "running" || add["running_status"] as? String == "running"
                || p["status"] as? String == "running" || add["is_running"] as? Bool == true || p["is_running"] as? Bool == true
            return PackageInfo(
                id: p["id"] as? String ?? "", name: p["dname"] as? String ?? p["name"] as? String ?? p["id"] as? String ?? "",
                version: p["version"] as? String ?? "", isRunning: running)
        }

        return NasInfo(model: model, dsmVersion: dsmVersion, serial: serial, hostname: hostname,
                       uptimeSeconds: uptime, temperatureC: temp, cpuLoad: cpuLoad,
                       ramTotalMb: ramTotalMb, ramUsedMb: ramUsedMb,
                       storageTotalGb: totalBytes / (1024*1024*1024), storageUsedGb: usedBytes / (1024*1024*1024),
                       volumes: volumes, disks: disks, lanIp: host, packages: packages)
    }

    private func parseSizeBytes(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let s = value as? String { return Int(s) ?? 0 }
        if let d = value as? Double { return Int(d) }
        return 0
    }

    private func authErrorMessage(_ code: Int?) -> String {
        switch code {
        case 400: return "No such account or incorrect password"
        case 401: return "Account is disabled"
        case 402: return "Permission denied"
        case 403: return "2-step verification required"
        case 404: return "Authentication failed — 2-step verification failed"
        case 406: return "OTP enforcement required"
        case 407: return "Max login attempts reached — try later"
        case 408: return "IP blocked — too many failed attempts"
        case 409: return "Insufficient permissions"
        case 410: return "Password change required"
        default:  return "Login failed (error \(code ?? -1))"
        }
    }
}
