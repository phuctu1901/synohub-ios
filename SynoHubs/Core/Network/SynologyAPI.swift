import Foundation

// MARK: - SSL Bypass Delegate
/// Accepts self-signed certificates typical on consumer NAS devices.
final class NASSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    static let shared = NASSessionDelegate()
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - SynologyAPI Actor
/// Low-level Synology DSM Web API client (Swift port of Flutter synology_api.dart).
/// Uses Actor for thread-safety. All calls append sid once authenticated.
actor SynologyAPI {
    let host: String
    let port: Int
    let useHttps: Bool

    private var sid: String?
    private var resolvedIp: String?
    private var dsmSid: String?
    private var synoToken: String?

    var isAuthenticated: Bool { sid != nil }
    var currentSid: String? { sid }
    var effectiveHost: String { resolvedIp ?? host }
    var baseUrl: String { "\(useHttps ? "https" : "http")://\(effectiveHost):\(port)/webapi" }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: NASSessionDelegate.shared, delegateQueue: nil)
    }()

    init(host: String, port: Int, useHttps: Bool = true) {
        self.host = host
        self.port = port
        self.useHttps = useHttps
    }

    // MARK: - DNS Resolution with DoH Fallback
    private func ensureHostResolved() async {
        if host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil { return }
        if resolvedIp != nil { return }
        // System DNS
        let hostRef = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        var resolved = DarwinBoolean(false)
        CFHostStartInfoResolution(hostRef, .addresses, nil)
        if let _ = CFHostGetAddressing(hostRef, &resolved)?.takeUnretainedValue(), resolved.boolValue { return }
        // DoH fallback
        for doh in ["cloudflare-dns.com", "dns.google"] {
            guard let url = URL(string: "https://\(doh)/dns-query?name=\(host)&type=A") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 5)
            req.setValue("application/dns-json", forHTTPHeaderField: "Accept")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let answers = json["Answer"] as? [[String: Any]] else { continue }
            for a in answers where (a["type"] as? Int) == 1 {
                if let ip = a["data"] as? String { resolvedIp = ip; return }
            }
        }
    }

    // MARK: - HTTP Helpers
    /// GET request - returns raw JSON dictionary.
    func get(_ endpoint: String, _ params: [String: String]) async throws -> [String: Any] {
        var p = params
        if let s = sid { p["_sid"] = s }
        var comps = URLComponents(string: "\(baseUrl)/\(endpoint)")!
        comps.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw SynologyError.invalidURL }
        let (data, _) = try await session.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SynologyError.decodingError
        }
        return json
    }

    /// POST request (x-www-form-urlencoded).
    func post(_ endpoint: String, _ params: [String: String]) async throws -> [String: Any] {
        var p = params
        if let s = sid { p["_sid"] = s }
        guard let url = URL(string: "\(baseUrl)/\(endpoint)") else { throw SynologyError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body = p.map { "\($0.key.urlEncoded)=\($0.value.urlEncoded)" }.joined(separator: "&")
        req.httpBody = body.data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SynologyError.decodingError
        }
        return json
    }

    /// POST with raw body string (for package install APIs that need JSON-quoted values).
    func postRaw(_ endpoint: String, body: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseUrl)/\(endpoint)") else { throw SynologyError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SynologyError.decodingError
        }
        return json
    }

    /// GET with DSM session + X-SYNO-TOKEN header.
    func dsmGet(_ endpoint: String, _ params: [String: String]) async throws -> [String: Any] {
        var p = params
        let s = dsmSid ?? sid
        if let s { p["_sid"] = s }
        var comps = URLComponents(string: "\(baseUrl)/\(endpoint)")!
        comps.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw SynologyError.invalidURL }
        var req = URLRequest(url: url)
        if let token = synoToken { req.setValue(token, forHTTPHeaderField: "X-SYNO-TOKEN") }
        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SynologyError.decodingError
        }
        return json
    }

    /// Compound GET via SYNO.Entry.Request (for admin APIs).
    func compoundGet(_ items: [[String: Any]]) async throws -> [[String: Any]] {
        let s = dsmSid ?? sid
        guard let s else { return [] }
        let compoundJson = try JSONSerialization.data(withJSONObject: items)
        let compoundStr = String(data: compoundJson, encoding: .utf8) ?? "[]"
        let params: [String: String] = [
            "api": "SYNO.Entry.Request", "version": "1", "method": "request",
            "stop_when_error": "false", "compound": compoundStr, "_sid": s
        ]
        var comps = URLComponents(string: "\(baseUrl)/entry.cgi")!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        if let token = synoToken { req.setValue(token, forHTTPHeaderField: "X-SYNO-TOKEN") }
        let (data, _) = try await session.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true,
              let results = (json["data"] as? [String: Any])?["result"] as? [[String: Any]] else { return [] }
        return results
    }

    // MARK: - Authentication
    func login(account: String, passwd: String, otpCode: String? = nil) async throws -> [String: Any] {
        await ensureHostResolved()
        var params: [String: String] = [
            "api": "SYNO.API.Auth", "version": "6", "method": "login",
            "account": account, "passwd": passwd, "session": "FileStation", "format": "sid"
        ]
        if let otp = otpCode, !otp.isEmpty { params["otp_code"] = otp }
        let resp = try await get("auth.cgi", params)
        if resp["success"] as? Bool == true {
            sid = (resp["data"] as? [String: Any])?["sid"] as? String
        }
        return resp
    }

    func logout() async {
        guard sid != nil else { return }
        _ = try? await get("auth.cgi", [
            "api": "SYNO.API.Auth", "version": "6", "method": "logout", "session": "FileStation"
        ])
        sid = nil; dsmSid = nil; synoToken = nil
    }

    func checkAdmin() async -> Bool {
        guard sid != nil else { return false }
        let resp = (try? await get("entry.cgi", [
            "api": "SYNO.Core.System.Utilization", "version": "1", "method": "get"
        ])) ?? [:]
        return resp["success"] as? Bool == true
    }

    /// DSM admin session for admin-only APIs.
    func ensureDsmSession(account: String, passwd: String) async {
        if dsmSid != nil && synoToken != nil { return }
        await ensureHostResolved()
        let resp = (try? await get("entry.cgi", [
            "api": "SYNO.API.Auth", "version": "7", "method": "login",
            "account": account, "passwd": passwd, "session": "DSM",
            "format": "sid", "enable_syno_token": "yes"
        ])) ?? [:]
        if resp["success"] as? Bool == true, let data = resp["data"] as? [String: Any] {
            dsmSid = data["sid"] as? String
            synoToken = data["synotoken"] as? String
        }
    }

    func clearDsmSession() { dsmSid = nil; synoToken = nil }

    // MARK: - DSM Info
    func getDsmInfo() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.DSM.Info", "version": "2", "method": "getinfo"])
    }

    // MARK: - System
    func getSystemUtilization() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.System.Utilization", "version": "1", "method": "get"])
    }

    func getStorageInfo() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Storage.CGI.Storage", "version": "1", "method": "load_info"])
    }

    func getNetworkInfo() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.System", "version": "1", "method": "info", "type": "network"])
    }

    func reboot() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.System", "version": "1", "method": "reboot"])
    }

    func shutdown() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.System", "version": "1", "method": "shutdown"])
    }

    func findMe() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.System", "version": "1", "method": "info", "type": "identify"])
    }

    // MARK: - Packages
    func getPackages() async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.Core.Package", "version": "2", "method": "list",
            "additional": "[\"status\",\"startable\",\"install_type\",\"ctl_uninstall\",\"description\"]"
        ])
    }

    func packageListServer() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.Package.Server", "version": "2", "method": "list"])
    }

    func packageStart(_ id: String) async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.Package.Control", "version": "1", "method": "start", "id": id])
    }

    func packageStop(_ id: String) async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.Package.Control", "version": "1", "method": "stop", "id": id])
    }

    func packageUninstall(_ id: String) async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.Package.Uninstallation", "version": "1", "method": "uninstall", "id": id])
    }

    func packageInstallDownload(id: String, url: String, size: Int, md5: String) async throws -> [String: Any] {
        let s = sid ?? ""
        var body = "api=SYNO.Core.Package.Installation&version=1&method=install"
        + "&name=\"\(id)\"&url=\"\(url)\"&filesize=\(size)&type=0&blqinst=false"
        + "&operation=\"install\""
        if !md5.isEmpty { body += "&checksum=\"\(md5)\"" }
        body += "&_sid=\(s)"
        return try await postRaw("entry.cgi", body: body)
    }

    func packageInstallStatus(taskId: String) async throws -> [String: Any] {
        let s = sid ?? ""
        let body = "api=SYNO.Core.Package.Installation.Download&version=1&method=check&taskid=\"\(taskId)\"&_sid=\(s)"
        return try await postRaw("entry.cgi", body: body)
    }

    func packageInstallFinal(filename: String, volume: String) async throws -> [String: Any] {
        let s = sid ?? ""
        let body = "api=SYNO.Core.Package.Installation&version=1&method=install&path=\"\(filename)\"&volume=\"\(volume)\"&_sid=\(s)"
        return try await postRaw("entry.cgi", body: body)
    }

    // MARK: - Docker
    func dockerList() async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.Docker.Container", "version": "1", "method": "list",
            "limit": "-1", "offset": "0", "type": "all"
        ])
    }

    func dockerGetResources() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Docker.Container.Resource", "version": "1", "method": "get"])
    }

    func dockerStart(_ name: String) async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Docker.Container", "version": "1", "method": "start", "name": name])
    }

    func dockerStop(_ name: String) async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Docker.Container", "version": "1", "method": "stop", "name": name])
    }

    func dockerRestart(_ name: String) async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Docker.Container", "version": "1", "method": "restart", "name": name])
    }

    // MARK: - Users & Groups
    func listUsers(offset: Int = 0, limit: Int = 200) async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.Core.User", "version": "1", "method": "list",
            "offset": "\(offset)", "limit": "\(limit)",
            "additional": "[\"email\",\"description\",\"expired\",\"cannot_chg_passwd\",\"is_manager\"]"
        ])
    }

    func getUserInfo(_ name: String) async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.Core.User", "version": "1", "method": "get", "name": name,
            "additional": "[\"email\",\"description\",\"expired\",\"cannot_chg_passwd\",\"is_manager\",\"groups\"]"
        ])
    }

    func createUser(name: String, password: String, description: String = "", email: String = "", sendNotification: Bool = false) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.Core.User", "version": "1", "method": "create",
            "name": name, "password": password, "description": description,
            "email": email, "send_notification_mail": sendNotification ? "true" : "false"
        ])
    }

    func editUser(name: String, description: String? = nil, email: String? = nil, password: String? = nil) async throws -> [String: Any] {
        var p: [String: String] = ["api": "SYNO.Core.User", "version": "1", "method": "set", "name": name]
        if let d = description { p["description"] = d }
        if let e = email { p["email"] = e }
        if let pw = password { p["password"] = pw }
        return try await post("entry.cgi", p)
    }

    func setUserEnabled(name: String, enabled: Bool) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.Core.User", "version": "1", "method": "set",
            "name": name, "expired": enabled ? "false" : "true"
        ])
    }

    func deleteUser(_ name: String) async throws -> [String: Any] {
        try await post("entry.cgi", ["api": "SYNO.Core.User", "version": "1", "method": "delete", "name": name])
    }

    func listGroups(offset: Int = 0, limit: Int = 200) async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.Core.Group", "version": "1", "method": "list",
            "offset": "\(offset)", "limit": "\(limit)", "additional": "[\"description\",\"members\"]"
        ])
    }

    func createGroup(name: String, description: String = "") async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.Core.Group", "version": "1", "method": "create",
            "name": name, "description": description
        ])
    }

    func editGroup(name: String, description: String? = nil) async throws -> [String: Any] {
        var p: [String: String] = ["api": "SYNO.Core.Group", "version": "1", "method": "set", "name": name]
        if let d = description { p["description"] = d }
        return try await post("entry.cgi", p)
    }

    func deleteGroup(_ name: String) async throws -> [String: Any] {
        try await post("entry.cgi", ["api": "SYNO.Core.Group", "version": "1", "method": "delete", "name": name])
    }

    func addGroupMembers(group: String, members: [String]) async throws -> [String: Any] {
        let membersJson = try String(data: JSONSerialization.data(withJSONObject: members), encoding: .utf8) ?? "[]"
        return try await post("entry.cgi", [
            "api": "SYNO.Core.Group.Member", "version": "1", "method": "add",
            "group": group, "member": membersJson
        ])
    }

    func removeGroupMembers(group: String, members: [String]) async throws -> [String: Any] {
        let membersJson = try String(data: JSONSerialization.data(withJSONObject: members), encoding: .utf8) ?? "[]"
        return try await post("entry.cgi", [
            "api": "SYNO.Core.Group.Member", "version": "1", "method": "remove",
            "group": group, "member": membersJson
        ])
    }

    func listGroupMembers(_ groupName: String) async throws -> [String: Any] {
        try await dsmGet("entry.cgi", [
            "api": "SYNO.Core.Group.Member", "version": "1", "method": "list",
            "group": groupName, "offset": "0", "limit": "200"
        ])
    }

    // MARK: - Resource Monitor
    func getCurrentConnections() async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.Core.CurrentConnection", "version": "1", "method": "list",
            "offset": "0", "limit": "50"
        ])
    }

    func getServices() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.Service", "version": "1", "method": "get"])
    }

    // MARK: - Log Center
    func getLogs(offset: Int = 0, limit: Int = 50, logType: String = "") async throws -> [String: Any] {
        var p: [String: String] = [
            "api": "SYNO.Core.SyslogClient.Log", "version": "1", "method": "list",
            "offset": "\(offset)", "limit": "\(limit)"
        ]
        if !logType.isEmpty { p["logtype"] = logType }
        return try await get("entry.cgi", p)
    }

    func getLogStatusCount() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.SyslogClient.Status", "version": "1", "method": "cnt_get"])
    }

    func getLatestLogs() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.SyslogClient.Status", "version": "1", "method": "latestlog_get"])
    }

    func getConnectionLogs(offset: Int = 0, limit: Int = 50) async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.Core.CurrentConnection", "version": "1", "method": "list",
            "offset": "\(offset)", "limit": "\(limit)"
        ])
    }
}

// MARK: - URL Encoding Helper
private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

// MARK: - Errors
enum SynologyError: Error, LocalizedError {
    case invalidConfiguration, invalidURL, decodingError
    case networkError(statusCode: Int)
    case apiError(code: Int)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Base URL not configured."
        case .invalidURL: return "Invalid URL."
        case .networkError(let c): return "Network error (HTTP \(c))"
        case .decodingError: return "JSON decoding error."
        case .apiError(let c): return "Synology API error (code: \(c))"
        }
    }
}
