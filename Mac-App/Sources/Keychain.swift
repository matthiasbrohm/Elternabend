import Foundation
import Security

/// Das Offizierspasswort liegt im Schlüsselbund des Macs – nicht in einer Datei.
enum Keychain {
    private static let service = "de.gilde-elternabend.abgleich"
    private static let account = "offizierspasswort"

    private static var base: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ password: String) -> Bool {
        SecItemDelete(base as CFDictionary)
        if password.isEmpty { return true }
        var q = base
        q[kSecValueData as String] = Data(password.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
