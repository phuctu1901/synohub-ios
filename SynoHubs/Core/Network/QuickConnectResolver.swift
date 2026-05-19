import Foundation

/// Result of a QuickConnect resolution.
struct QuickConnectResult {
    let host: String
    let port: Int
    let useHttps: Bool

    var description: String { "\(useHttps ? "https" : "http")://\(host):\(port)" }
}

/// Resolves a Synology QuickConnect ID to a direct connection address.
/// Flow: POST global.quickconnect.to → parse server info → probe LAN/WAN/DDNS/relay → first reachable.
enum QuickConnectResolver {
    private static let timeout: TimeInterval = 5

    /// Whether input looks like a QuickConnect ID or URL.
    static func isQuickConnect(_ input: String) -> Bool {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.contains(".direct.quickconnect.to") || cleaned.contains(".relay.quickconnect.to") { return false }
        if cleaned.contains("quickconnect.to") { return true }
        if cleaned.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9\-]{0,62}$"#, options: .regularExpression) != nil
            && !cleaned.contains(".") && !cleaned.contains(":") { return true }
        return false
    }

    /// Extract the QuickConnect ID from user input.
    static func extractId(_ input: String) -> String {
        var raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("https://") { raw = String(raw.dropFirst(8)) }
        if raw.hasPrefix("http://") { raw = String(raw.dropFirst(7)) }
        if raw.hasPrefix("quickconnect.to/") { raw = String(raw.dropFirst(16)) }
        while raw.hasSuffix("/") { raw = String(raw.dropLast()) }
        return raw
    }

    /// Resolve a QuickConnect ID to a reachable NAS endpoint. Throws on failure.
    static func resolve(_ qcId: String) async throws -> QuickConnectResult {
        let serverInfo = try await getServerInfo(qcId)
        let service = serverInfo["service"] as? [String: Any] ?? [:]
        let server = serverInfo["server"] as? [String: Any] ?? [:]
        let smartdns = serverInfo["smartdns"] as? [String: Any] ?? [:]

        let dsmPort = toInt(service["port"]) ?? 5001
        var candidates: [QuickConnectResult] = []

        // 1. LAN IPs
        for iface in (server["interface"] as? [[String: Any]] ?? []) {
            if let ip = iface["ip"] as? String, !ip.isEmpty {
                candidates.append(QuickConnectResult(host: ip, port: dsmPort, useHttps: true))
            }
        }
        // 2. WAN IP + ext_port
        if let extIp = (server["external"] as? [String: Any])?["ip"] as? String, !extIp.isEmpty {
            if let extPort = toInt(service["ext_port"]), extPort > 0 {
                candidates.append(QuickConnectResult(host: extIp, port: extPort, useHttps: true))
            }
            candidates.append(QuickConnectResult(host: extIp, port: dsmPort, useHttps: true))
        }
        // 3. SmartDNS external
        if let smartExt = smartdns["external"] as? String, !smartExt.isEmpty {
            candidates.append(QuickConnectResult(host: smartExt, port: dsmPort, useHttps: true))
        }
        // 4. SmartDNS host
        if let smartHost = smartdns["host"] as? String, !smartHost.isEmpty {
            candidates.append(QuickConnectResult(host: smartHost, port: dsmPort, useHttps: true))
        }
        // 5. SmartDNS LAN
        for lanHost in (smartdns["lan"] as? [String] ?? []) where !lanHost.isEmpty {
            candidates.append(QuickConnectResult(host: lanHost, port: dsmPort, useHttps: true))
        }
        // 6. DDNS
        if let ddns = server["ddns"] as? String, !ddns.isEmpty, ddns != "NULL" {
            candidates.append(QuickConnectResult(host: ddns, port: dsmPort, useHttps: true))
        }
        // 7. Relay tunnel
        if let relayIp = service["relay_ip"] as? String, !relayIp.isEmpty,
           let relayPort = toInt(service["relay_port"]), relayPort > 0 {
            candidates.append(QuickConnectResult(host: relayIp, port: relayPort, useHttps: true))
        }
        // 8. Relay DN
        if let relayDn = service["relay_dn"] as? String, !relayDn.isEmpty {
            candidates.append(QuickConnectResult(host: relayDn, port: dsmPort, useHttps: true))
        }

        return try await probeFirst(candidates)
    }

    // MARK: - Private

    private static func getServerInfo(_ qcId: String) async throws -> [String: Any] {
        let payload: [[String: Any]] = [
            ["version": 1, "command": "get_server_info", "stop_when_error": false,
             "stop_when_success": false, "id": "mainapp_https", "serverID": qcId, "is_gofile": false, "path": ""],
            ["version": 1, "command": "get_server_info", "stop_when_error": false,
             "stop_when_success": false, "id": "mainapp_http", "serverID": qcId, "is_gofile": false, "path": ""]
        ]
        guard let url = URL(string: "https://global.quickconnect.to/Serv.php") else {
            throw NSError(domain: "QC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid QC URL"])
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        let decoded = try JSONSerialization.jsonObject(with: data)

        if let arr = decoded as? [[String: Any]] {
            for item in arr {
                let errno = item["errno"] as? Int
                if errno == nil || errno == 0 { return item }
            }
            // Check region redirect
            for item in arr {
                if let sites = item["sites"] as? [Any], !sites.isEmpty {
                    return try await getServerInfoFromRegion(qcId, sites: sites)
                }
            }
            throw NSError(domain: "QC", code: -2, userInfo: [NSLocalizedDescriptionKey: "QuickConnect error: \(arr.first?["errinfo"] ?? arr.first?["errno"] ?? "unknown")"])
        }
        if let json = decoded as? [String: Any] {
            if let errno = json["errno"] as? Int, errno != 0 {
                if let sites = json["sites"] as? [Any], !sites.isEmpty {
                    return try await getServerInfoFromRegion(qcId, sites: sites)
                }
                throw NSError(domain: "QC", code: errno, userInfo: [NSLocalizedDescriptionKey: "QuickConnect error: \(json["errinfo"] ?? errno)"])
            }
            return json
        }
        throw NSError(domain: "QC", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid QC response"])
    }

    private static func getServerInfoFromRegion(_ qcId: String, sites: [Any]) async throws -> [String: Any] {
        for site in sites {
            let host: String?
            if let s = site as? String { host = s }
            else { host = (site as? [String: Any])?["host"] as? String }
            guard let h = host, !h.isEmpty else { continue }

            let payload: [[String: Any]] = [
                ["version": 1, "command": "get_server_info", "stop_when_error": false,
                 "stop_when_success": false, "id": "mainapp_https", "serverID": qcId, "is_gofile": false, "path": ""],
                ["version": 1, "command": "get_server_info", "stop_when_error": false,
                 "stop_when_success": false, "id": "mainapp_http", "serverID": qcId, "is_gofile": false, "path": ""]
            ]
            guard let url = URL(string: "https://\(h)/Serv.php") else { continue }
            var req = URLRequest(url: url, timeoutInterval: timeout)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let decoded = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let arr = decoded as? [[String: Any]] {
                for item in arr { if (item["errno"] as? Int ?? 0) == 0 { return item } }
            } else if let json = decoded as? [String: Any], (json["errno"] as? Int ?? 0) == 0 {
                return json
            }
        }
        throw NSError(domain: "QC", code: -4, userInfo: [NSLocalizedDescriptionKey: "All regional servers failed for \"\(qcId)\""])
    }

    private static func probeFirst(_ candidates: [QuickConnectResult]) async throws -> QuickConnectResult {
        guard !candidates.isEmpty else {
            throw NSError(domain: "QC", code: -5, userInfo: [NSLocalizedDescriptionKey: "No QuickConnect endpoints found"])
        }
        // Deduplicate
        var seen = Set<String>()
        let unique = candidates.filter { let k = "\($0.host):\($0.port):\($0.useHttps)"; return seen.insert(k).inserted }

        // Race: first successful DSM API response wins
        return try await withThrowingTaskGroup(of: QuickConnectResult?.self) { group in
            for c in unique {
                group.addTask {
                    let scheme = c.useHttps ? "https" : "http"
                    guard let url = URL(string: "\(scheme)://\(c.host):\(c.port)/webapi/entry.cgi?api=SYNO.API.Info&version=1&method=query&query=SYNO.API.Auth") else { return nil }
                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 4
                    let session = URLSession(configuration: config, delegate: NASSessionDelegate.shared, delegateQueue: nil)
                    let (data, _) = try await session.data(from: url)
                    let body = String(data: data, encoding: .utf8) ?? ""
                    if body.contains("\"success\"") && body.contains("SYNO.API.Auth") { return c }
                    return nil
                }
            }
            for try await result in group {
                if let r = result {
                    group.cancelAll()
                    return r
                }
            }
            // Fallback: first hostname-based candidate
            if let hostBased = unique.first(where: { !$0.host.first!.isNumber }) { return hostBased }
            throw NSError(domain: "QC", code: -6, userInfo: [NSLocalizedDescriptionKey: "None of the resolved endpoints are reachable"])
        }
    }

    private static func toInt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s) }
        return nil
    }
}
