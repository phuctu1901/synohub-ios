import Foundation
import SwiftData

/// Represents a saved NAS connection profile (matches Flutter's NasProfile model).
@Model
final class NasProfile {
    var id: UUID
    var nickname: String
    var host: String
    var port: Int
    var protocolType: String   // "http" or "https"
    var username: String
    var isQuickConnect: Bool
    var model: String?         // detected after login, e.g. "DS923+"
    var dsmVersion: String?
    var lastConnected: Date?
    var isOnline: Bool

    init(id: UUID = UUID(), nickname: String, host: String, port: Int = 5001,
         protocolType: String = "https", username: String, isQuickConnect: Bool = false,
         model: String? = nil, dsmVersion: String? = nil, lastConnected: Date? = nil, isOnline: Bool = false) {
        self.id = id
        self.nickname = nickname
        self.host = host
        self.port = port
        self.protocolType = protocolType
        self.username = username
        self.isQuickConnect = isQuickConnect
        self.model = model
        self.dsmVersion = dsmVersion
        self.lastConnected = lastConnected
        self.isOnline = isOnline
    }

    var useHttps: Bool { protocolType == "https" }
    var displayAddress: String { "\(host):\(port)" }

    /// Password stored in Keychain, not in SwiftData.
    var password: String? {
        get { KeychainManager.shared.getPassword(for: keychainKey) }
        set {
            if let pw = newValue { try? KeychainManager.shared.save(password: pw, for: keychainKey) }
            else { try? KeychainManager.shared.deletePassword(for: keychainKey) }
        }
    }

    private var keychainKey: String { "synohubs_\(id.uuidString)" }
}
