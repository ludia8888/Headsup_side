import Foundation
import Security
import JiminCore

enum SharedResources {
    static let group = "group.com.jimin.mvp"
    static let transferIdentifier = "com.jimin.mvp.monitor-transfer"
    static func store() throws -> LockedStateStore {
        #if targetEnvironment(simulator)
        // Keep simulator preferences in the same container when switching between
        // unsigned and locally signed builds. Real Screen Time extensions use the
        // signed App Group on an actual iPhone.
        return LockedStateStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Jimin"))
        #else
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return LockedStateStore(directory: url.appendingPathComponent("Jimin", isDirectory: true))
        }
        throw NSError(domain: "Jimin", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group 서명이 필요합니다. Xcode에서 앱과 확장 기능의 그룹을 확인해 주세요."])
        #endif
    }

    // A normal user preference cannot open this gate. Both signed targets and the server
    // require an explicit Apple approval reference, recorded outside the product UI.
    static var automaticDispatchApproved: Bool {
        let enabled = Bundle.main.object(forInfoDictionaryKey: "AutomationApproved") as? String
        let reference = Bundle.main.object(forInfoDictionaryKey: "AutoCallApprovalReference") as? String ?? ""
        return enabled == "YES" && reference.trimmingCharacters(in: .whitespacesAndNewlines).count > 4
    }
}

struct APIConnection: Codable {
    let baseURL: URL
    let deviceID: String
    let token: String
}

enum SecureConnectionStore {
    static let service = "com.jimin.mvp.connection"
    private static var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: service, kSecAttrAccount as String: "device"]
        #if !targetEnvironment(simulator)
        // The prefix is read from the signed entitlements via an expanded Info.plist value.
        if let group = Bundle.main.object(forInfoDictionaryKey: "KeychainGroup") as? String, !group.isEmpty {
            q[kSecAttrAccessGroup as String] = group
        }
        #endif
        return q
    }
    static func read() throws -> APIConnection? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw error(status) }
        return try JSONDecoder().decode(APIConnection.self, from: data)
    }
    static func save(_ connection: APIConnection) throws {
        let data = try JSONEncoder().encode(connection)
        var attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            attributes.merge(query) { first, _ in first }
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else { throw error(status) }
        } else if updated != errSecSuccess { throw error(updated) }
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
    private static func error(_ status: OSStatus) -> NSError {
        NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "서버 연결 정보를 안전하게 저장하지 못했습니다. 서명과 Keychain 그룹을 확인해 주세요. (\(status))"])
    }
}
