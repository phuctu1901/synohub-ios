import Foundation

// MARK: - Permissions, Quotas, App Privileges
extension SynologyAPI {

    // MARK: Quota
    func listQuota() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.Quota", "version": "1", "method": "get"])
    }

    func setUserQuota(user: String, volume: String, quotaMB: Int) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.Core.Quota", "version": "1", "method": "set",
            "user": user, "volume": volume, "quota": "\(quotaMB * 1024 * 1024)"
        ])
    }

    func getDsmUserQuota(_ userName: String) async throws -> [String: Any] {
        try await dsmGet("entry.cgi", [
            "api": "SYNO.Core.Quota", "version": "1", "method": "get", "name": userName
        ])
    }

    func setDsmUserQuota(_ userName: String, quotas: [[String: Any]]) async throws -> Bool {
        let results = try await compoundGet([
            ["api": "SYNO.Core.Quota", "version": 1, "method": "set",
             "name": userName, "user_quota": quotas]
        ])
        return !results.isEmpty && results[0]["success"] as? Bool == true
    }

    // MARK: Share Permissions
    func listSharePermissions(name: String) async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.Core.Share.Permission", "version": "1", "method": "list", "name": name
        ])
    }

    func setSharePermission(name: String, userOrGroup: String, permission: String, isGroup: Bool = false) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.Core.Share.Permission", "version": "1", "method": "set",
            "name": name, "user_group_type": isGroup ? "local_group" : "local_user",
            "user_group": userOrGroup, "permission": permission
        ])
    }

    /// Set share permission via compound GET (bypasses DSM 7 CSRF).
    func setSharePermissionDsm(shareName: String, userName: String, perm: String) async throws -> Bool {
        let writable: Bool, readonly: Bool, deny: Bool
        switch perm {
        case "rw":   writable = true;  readonly = false; deny = false
        case "ro":   writable = false; readonly = true;  deny = false
        case "deny": writable = false; readonly = false; deny = true
        default:     writable = false; readonly = false; deny = false // "none" = inherit
        }
        let results = try await compoundGet([
            ["api": "SYNO.Core.Share.Permission", "version": 1, "method": "set",
             "name": shareName, "user_group_type": "local_user",
             "permissions": [
                ["name": userName, "is_writable": writable, "is_deny": deny, "is_readonly": readonly]
             ]] as [String : Any]
        ])
        return !results.isEmpty && results[0]["success"] as? Bool == true
    }

    func listDsmSharedFolders() async throws -> [String: Any] {
        try await dsmGet("entry.cgi", [
            "api": "SYNO.Core.Share", "version": "1", "method": "list"
        ])
    }

    func getSharePermissionsByUser(_ userName: String) async throws -> [String: Any] {
        let results = try await compoundGet([
            ["api": "SYNO.Core.Share.Permission", "version": 1, "method": "list_by_user",
             "name": userName, "user_group_type": "local_user"] as [String : Any]
        ])
        if !results.isEmpty && results[0]["success"] as? Bool == true {
            return ["success": true, "data": results[0]["data"] as Any]
        }
        let errCode = (results.first?["error"] as? [String: Any])?["code"] ?? -1
        return ["success": false, "error": ["code": errCode]]
    }

    // MARK: User Home
    func getUserHomeStatus() async throws -> [String: Any] {
        try await get("entry.cgi", ["api": "SYNO.Core.User.Home", "version": "1", "method": "get"])
    }

    func setUserHomeEnabled(_ enabled: Bool) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.Core.User.Home", "version": "1", "method": "set",
            "enable": enabled ? "true" : "false"
        ])
    }

    // MARK: Application Privileges
    func listAppPrivApps() async throws -> [String: Any] {
        try await dsmGet("entry.cgi", [
            "api": "SYNO.Core.AppPriv.App", "version": "2", "method": "list"
        ])
    }

    func getAppPrivRules(_ appId: String) async throws -> [[String: Any]] {
        let results = try await compoundGet([
            ["api": "SYNO.Core.AppPriv.Rule", "version": 1, "method": "list", "app_id": appId] as [String : Any]
        ])
        if !results.isEmpty && results[0]["success"] as? Bool == true {
            return (results[0]["data"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
        }
        return []
    }

    func getAllAppPrivRules(_ appIds: [String]) async throws -> [String: [[String: Any]]] {
        let items: [[String: Any]] = appIds.map {
            ["api": "SYNO.Core.AppPriv.Rule", "version": 1, "method": "list", "app_id": $0]
        }
        let results = try await compoundGet(items)
        var map: [String: [[String: Any]]] = [:]
        for i in 0..<min(results.count, appIds.count) {
            if results[i]["success"] as? Bool == true {
                map[appIds[i]] = (results[i]["data"] as? [String: Any])?["rules"] as? [[String: Any]] ?? []
            } else {
                map[appIds[i]] = []
            }
        }
        return map
    }

    func setAppPrivRules(_ rules: [[String: Any]]) async throws -> Bool {
        let results = try await compoundGet([
            ["api": "SYNO.Core.AppPriv.Rule", "version": 1, "method": "set", "rules": rules] as [String : Any]
        ])
        return !results.isEmpty && results[0]["success"] as? Bool == true
    }

    func setAppPrivForUser(appId: String, userName: String, action: String) async throws -> Bool {
        if action == "remove" {
            let results = try await compoundGet([
                ["api": "SYNO.Core.AppPriv.Rule", "version": 1, "method": "delete",
                 "app_id": appId, "entity_name": userName, "entity_type": "user"] as [String : Any]
            ])
            return !results.isEmpty && results[0]["success"] as? Bool == true
        }
        let allowIp: [String] = action == "allow" ? ["all"] : []
        let denyIp: [String] = action == "deny" ? ["all"] : []
        return try await setAppPrivRules([
            ["app_id": appId, "entity_name": userName, "entity_type": "user",
             "allow_ip": allowIp, "deny_ip": denyIp]
        ])
    }
}
