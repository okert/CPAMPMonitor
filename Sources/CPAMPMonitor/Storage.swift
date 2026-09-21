import Foundation
import Security
import MonitorCore

enum Storage {
    static let defaults = UserDefaults.standard
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    static func credential(_ server: String) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "local.cpamp.monitor",
                                    kSecAttrAccount as String: server,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = value as? Data else { throw MonitorError("无法读取钥匙串（\(status)）。") }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func storeCredential(_ secret: String, server: String) throws {
        guard !secret.isEmpty else { throw MonitorError("请填写 CPAMP 管理密钥。") }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "local.cpamp.monitor",
                                    kSecAttrAccount as String: server]
        let values: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query.merging(values) { _, new in new }
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(insert as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw MonitorError("无法保存至钥匙串（\(status)）。") }
    }
}
