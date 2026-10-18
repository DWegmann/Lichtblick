import Foundation
import Security

enum CredentialStore {
    private static let service = "de.smbrating.connection"

    // Password persistence is optional and must never reject an established SMB session.
    // Return a visible notice, including failed deletion of any previously saved password.
    static func update(password: String, remember: Bool,
                       save: (String?) throws -> Void = { try CredentialStore.save($0) }) -> String? {
        do {
            try save(remember ? password : nil)
            return nil
        } catch {
            if remember {
                let signingHint = (error as NSError).code == Int(errSecMissingEntitlement)
                    ? " Zum dauerhaften Merken muss der Mac-Build mit einem Apple-Development-Team signiert werden."
                    : ""
                return "Die SMB-Verbindung wurde hergestellt. Das Passwort konnte nicht im Schlüsselbund gespeichert werden und wird für diese Verbindung nur in der laufenden Sitzung verwendet." + signingHint
            }
            return "Die SMB-Verbindung wurde hergestellt. Der Schlüsselbund ist nicht zugänglich. Ein eventuell früher gespeichertes Passwort konnte deshalb nicht gelöscht werden. Das eingegebene Passwort wird nicht neu gespeichert."
        }
    }

    static func load(account: String = "last-connection") -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ password: String?, account: String = "last-connection") throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        if let password {
            let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                let addStatus = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
                guard addStatus == errSecSuccess else { throw keychainError(addStatus) }
            } else if status != errSecSuccess { throw keychainError(status) }
        } else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
        }
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey:
            "Das Passwort konnte nicht im Schlüsselbund gespeichert oder gelöscht werden (\(status))."])
    }
}
