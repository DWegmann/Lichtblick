import XCTest
@testable import RatingCore

final class ConnectionHistoryTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func preferences() -> UserDefaults {
        let suite = "de.lichtblick.tests.\(UUID().uuidString)"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }

    private func settings(server: String = "nas.local", share: String = "Fotos") -> ConnectionSettings {
        var value = ConnectionSettings()
        value.server = server; value.share = share; value.username = "test-user"
        return value
    }

    func testRestoresActiveConnectionAndLatestFolder() {
        let defaults = preferences()
        let history = ConnectionHistory(defaults: defaults)
        let profile = history.save(settings: settings(), path: "/", rememberPassword: true)
        history.updatePath("/Urlaub/2026/Schöne Bilder", for: profile.id)

        let restored = ConnectionHistory(defaults: defaults)
        XCTAssertEqual(restored.active?.id, profile.id)
        XCTAssertEqual(restored.active?.lastPath, "/Urlaub/2026/Schöne Bilder")
        XCTAssertEqual(restored.active?.settings.share, "Fotos")
        XCTAssertEqual(restored.active?.settings.server, "nas.local")
    }

    func testConnectionsKeepIndependentFoldersAndKeychainAccounts() {
        let defaults = preferences()
        let history = ConnectionHistory(defaults: defaults)
        let first = history.save(settings: settings(), path: "/Sommer", rememberPassword: true)
        let second = history.save(settings: settings(share: "Archiv"), path: "/2024", rememberPassword: false)
        history.updatePath("/Sommer/Auswahl", for: first.id)

        let restored = ConnectionHistory(defaults: defaults)
        XCTAssertEqual(restored.connections.count, 2)
        XCTAssertEqual(restored.active?.id, second.id)
        XCTAssertEqual(restored.matching(settings())?.lastPath, "/Sommer/Auswahl")
        XCTAssertEqual(restored.matching(settings(share: "Archiv"))?.lastPath, "/2024")
        XCTAssertNotEqual(first.credentialAccount, second.credentialAccount)
        XCTAssertFalse(restored.active?.rememberPassword ?? true)
    }

    func testEquivalentHostDoesNotCreateDuplicateAndUpdatesExistingPreferences() {
        let history = ConnectionHistory(defaults: preferences())
        let first = history.save(settings: settings(), path: "/Sommer", rememberPassword: true)
        let updated = history.save(settings: settings(server: "smb://NAS.local/"), path: "/Winter", rememberPassword: false)
        XCTAssertEqual(history.connections.count, 1)
        XCTAssertEqual(first.id, updated.id)
        XCTAssertEqual(first.credentialAccount, updated.credentialAccount)
        XCTAssertEqual(updated.lastPath, "/Winter")
        XCTAssertFalse(updated.rememberPassword)
    }

    func testDisconnectRetainsSavedConnectionsButDisablesAutomaticRestore() {
        let defaults = preferences()
        let history = ConnectionHistory(defaults: defaults)
        history.save(settings: settings(), path: "/Bilder", rememberPassword: false)
        history.clearActive()
        let restored = ConnectionHistory(defaults: defaults)
        XCTAssertNil(restored.active)
        XCTAssertEqual(restored.connections.count, 1)
        XCTAssertEqual(restored.connections.first?.lastPath, "/Bilder")
    }

    func testPreviousSingleConnectionIsMigratedWithExistingCredentialAccount() throws {
        let defaults = preferences()
        var previous = settings()
        previous.directory = "Urlaub/2026"
        defaults.set(try JSONEncoder().encode(previous), forKey: "connection")
        let history = ConnectionHistory(defaults: defaults)
        XCTAssertEqual(history.active?.lastPath, "/Urlaub/2026")
        XCTAssertEqual(history.active?.credentialAccount, "last-connection")
        let restored = ConnectionHistory(defaults: defaults)
        XCTAssertEqual(history.active?.id, restored.active?.id)
    }

    func testDemoFolderIsRestoredAndSuccessfulSMBConnectionTakesPrecedence() {
        let defaults = preferences()
        let history = ConnectionHistory(defaults: defaults)
        history.rememberDemo(path: "/Landschaften/Auswahl")
        XCTAssertEqual(ConnectionHistory(defaults: defaults).restoredDemoPath, "/Landschaften/Auswahl")
        history.save(settings: settings(), path: "/Fotos", rememberPassword: false)
        XCTAssertNil(ConnectionHistory(defaults: defaults).restoredDemoPath)
    }

    func testDifferentUsersOnSameShareHaveSeparateConnections() {
        let history = ConnectionHistory(defaults: preferences())
        var second = settings()
        second.username = "other-user"
        let first = history.save(settings: settings(), path: "/Privat", rememberPassword: true)
        let other = history.save(settings: second, path: "/Arbeit", rememberPassword: true)
        XCTAssertEqual(history.connections.count, 2)
        XCTAssertNotEqual(first.credentialAccount, other.credentialAccount)
    }
}
