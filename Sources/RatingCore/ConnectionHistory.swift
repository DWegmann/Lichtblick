import Foundation

struct ConnectionSettings: Codable, Equatable {
    var server = ""
    var share = ""
    var directory = ""
    var username = ""
    var domain = ""
    var encrypted = false

    var startPath: String { "/" + directory.split(separator: "/").joined(separator: "/") }

    func matches(_ other: ConnectionSettings) -> Bool {
        func host(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let address = trimmed.hasPrefix("smb://") ? String(trimmed.dropFirst(6)) : trimmed
            return address.hasSuffix("/") ? String(address.dropLast()) : address
        }
        return host(server) == host(other.server)
            && share.trimmingCharacters(in: .whitespaces) == other.share.trimmingCharacters(in: .whitespaces)
            && username == other.username && domain == other.domain
    }

    func serverURL() throws -> URL {
        let value = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value.contains("://") ? value : "smb://\(value)"),
              url.scheme == "smb", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil,
              url.path.isEmpty || url.path == "/", url.query == nil, url.fragment == nil,
              !share.trimmingCharacters(in: .whitespaces).isEmpty,
              !share.contains("/"), !share.contains("\\"),
              !directory.split(separator: "/").contains("..")
        else { throw ConnectionError.invalidAddress }
        return url
    }
}

struct SavedConnection: Codable, Identifiable, Equatable {
    let id: UUID
    var settings: ConnectionSettings
    var lastPath: String
    var rememberPassword: Bool
    let credentialAccount: String

    init(settings: ConnectionSettings, lastPath: String, rememberPassword: Bool, credentialAccount: String? = nil) {
        let id = UUID()
        self.id = id
        self.settings = settings
        self.lastPath = lastPath
        self.rememberPassword = rememberPassword
        self.credentialAccount = credentialAccount ?? id.uuidString
    }
}

final class ConnectionHistory {
    private let defaults: UserDefaults
    private(set) var connections: [SavedConnection]
    private(set) var activeID: UUID?
    private var demoPath: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: "savedConnections"),
           let connections = try? decoder.decode([SavedConnection].self, from: data) {
            self.connections = connections
            activeID = defaults.string(forKey: "activeConnectionID").flatMap(UUID.init(uuidString:))
        } else if let data = defaults.data(forKey: "connection"),
                  let settings = try? decoder.decode(ConnectionSettings.self, from: data) {
            // Adopt the previous single connection without losing its keychain entry.
            let migrated = SavedConnection(settings: settings, lastPath: settings.startPath,
                rememberPassword: true, credentialAccount: "last-connection")
            connections = [migrated]; activeID = migrated.id
        } else {
            connections = []; activeID = nil
        }
        demoPath = defaults.string(forKey: "lastDemoPath")
        persist()
    }

    var active: SavedConnection? { connections.first { $0.id == activeID } }
    var restoredDemoPath: String? { defaults.bool(forKey: "restoreDemo") ? demoPath ?? "/" : nil }

    func matching(_ settings: ConnectionSettings) -> SavedConnection? {
        connections.first { $0.settings.matches(settings) }
    }

    @discardableResult
    func save(settings: ConnectionSettings, path: String, rememberPassword: Bool) -> SavedConnection {
        var connection = matching(settings) ?? SavedConnection(settings: settings, lastPath: path, rememberPassword: rememberPassword)
        connection.settings = settings; connection.lastPath = path; connection.rememberPassword = rememberPassword
        connections.removeAll { $0.id == connection.id }
        connections.insert(connection, at: 0)
        activeID = connection.id
        defaults.set(false, forKey: "restoreDemo")
        persist()
        return connection
    }

    func updatePath(_ path: String, for id: UUID) {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[index].lastPath = path
        persist()
    }

    func rememberDemo(path: String) {
        demoPath = path
        defaults.set(path, forKey: "lastDemoPath")
        defaults.set(true, forKey: "restoreDemo")
    }

    func clearActive() {
        activeID = nil
        defaults.set(false, forKey: "restoreDemo")
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: "savedConnections")
        if let activeID { defaults.set(activeID.uuidString, forKey: "activeConnectionID") }
        else { defaults.removeObject(forKey: "activeConnectionID") }
    }
}

enum ConnectionError: LocalizedError {
    case invalidAddress, notConnected
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return String(localized: "Bitte einen Server wie nas.local oder smb://192.168.1.10 und einen separaten Freigabenamen eingeben.")
        case .notConnected: return String(localized: "Bitte zuerst eine Verbindung herstellen.")
        }
    }
}

