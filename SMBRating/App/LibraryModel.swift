import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    @Published var settings: ConnectionSettings
    @Published var connected = false
    @Published var isDemo = false
    @Published var isConnecting = false
    @Published var isLoading = false
    @Published private(set) var includeSubfolders = false
    @Published var foldersExpanded = true
    @Published var isSaving = false
    @Published var isDeleting = false
    @Published private(set) var isMoving = false
    @Published var entries: [RemoteEntry] = []
    @Published var path = "/"
    @Published var ratings: [String: Int] = [:]
    @Published var error: String?
    @Published var credentialWarning: String?
    @Published var revision = UUID()
    @Published var savedConnections: [SavedConnection]
    @Published var activeConnectionID: UUID?
    @Published var showConnection = false
    @Published var isRestoring = false
    private(set) var connectionFormSettings: ConnectionSettings?
    private(set) var connectionFormMessage: String?
    var pipeline: ImagePipeline?
    private let history: ConnectionHistory
    private var store: (any PhotoStore)?
    private var writer: SafeRatingWriter?
    private var folderRequest = UUID()
    private var folderTask: Task<[RemoteEntry], Error>?
    private var rootPath = "/"
    private var attemptedRestore = false
    private var connectionID = UUID()

    init() {
        let history = ConnectionHistory()
        self.history = history
        savedConnections = history.connections
        settings = history.active?.settings ?? history.connections.first?.settings ?? ConnectionSettings()
    }

    var folders: [RemoteEntry] { entries.filter(\.isDirectory).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var photos: [RemoteEntry] { entries.filter { !$0.isDirectory && $0.isImage } }
    var canGoUp: Bool { path != rootPath }
    var locationName: String { path == rootPath ? (isDemo ? "Demobibliothek" : settings.share) : (path as NSString).lastPathComponent }
    var isBusy: Bool { isSaving || isDeleting || isMoving }

    func clearRatingOverride(for path: String) {
        // Mutating an absent dictionary key still publishes a model change to every tile.
        guard ratings[path] != nil else { return }
        ratings.removeValue(forKey: path)
    }

    // Keep the form draft separate from the active connection so editing the next
    // host does not change labels or settings of an already connected server.
    var savedConnectionSettings: ConnectionSettings {
        guard let data = UserDefaults.standard.data(forKey: "connectionDraft"),
              let draft = try? JSONDecoder().decode(ConnectionSettings.self, from: data) else { return settings }
        return draft
    }

    func rememberConnectionSettings(_ draft: ConnectionSettings) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: "connectionDraft")
    }

    func savedConnection(for settings: ConnectionSettings) -> SavedConnection? { history.matching(settings) }

    func storedPassword(for settings: ConnectionSettings) -> String? {
        guard let profile = history.matching(settings), profile.rememberPassword else { return nil }
        return CredentialStore.load(account: profile.credentialAccount)
    }

    func prepareConnection(_ profile: SavedConnection? = nil, message: String? = nil) {
        guard !isBusy, !isConnecting else { return }
        connectionFormSettings = profile?.settings
        connectionFormMessage = message
        showConnection = true
    }

    func restoreLastSession() async {
        guard !attemptedRestore else { return }
        attemptedRestore = true
        isRestoring = true
        defer { isRestoring = false }
        if let demoPath = history.restoredDemoPath { await openDemo(at: demoPath) }
        else if let profile = history.active { await reconnect(profile) }
    }

    func reconnect(_ profile: SavedConnection) async {
        guard !isConnecting, !isBusy else { return }
        let password = storedPassword(for: profile.settings)
        guard let password = password ?? (profile.settings.username.isEmpty && !profile.rememberPassword ? "" : nil) else {
            prepareConnection(profile, message: "Bitte das Passwort erneut eingeben. Danach wird der zuletzt geöffnete Ordner \(profile.lastPath) wiederhergestellt.")
            return
        }
        if !(await connect(settings: profile.settings, password: password, remember: profile.rememberPassword, restoring: true)) {
            let message = error
            error = nil
            prepareConnection(profile, message: message)
        }
    }

    func connect(settings: ConnectionSettings, password: String, remember: Bool, restoring: Bool = false) async -> Bool {
        guard !isConnecting, !isBusy else { return false }
        cancelLoading()
        isConnecting = true
        error = nil
        credentialWarning = nil
        defer { isConnecting = false }
        do {
            let client = try SMBStore(settings: settings, password: password)
            try await client.connect(share: settings.share.trimmingCharacters(in: .whitespaces), encrypted: settings.encrypted)
            let previous = history.matching(settings)
            var start = previous.flatMap { $0.settings.directory == settings.directory ? $0.lastPath : nil } ?? settings.startPath
            var initial: [RemoteEntry]
            var folderNotice: String?
            do { initial = try await client.list(start) }
            catch {
                guard previous != nil, start != "/", let code = (error as? POSIXError)?.code,
                      [.ENOENT, .ENOTDIR, .EACCES].contains(code) else { throw error }
                folderNotice = "Der zuletzt geöffnete Ordner \(start) ist nicht mehr verfügbar. Stattdessen wurde die Freigabe geöffnet."
                start = "/"
                initial = try await client.list(start)
            }
            initial = try await DirectoryBrowser.entries(in: start, includingSubfolders: false,
                                                        store: client, initial: initial)
            let encodedSettings = try JSONEncoder().encode(settings)
            let profile = history.save(settings: settings, path: start, rememberPassword: remember)
            let warning = restoring ? nil : CredentialStore.update(password: password, remember: remember) {
                try CredentialStore.save($0, account: profile.credentialAccount)
            }
            UserDefaults.standard.set(encodedSettings, forKey: "connection")
            await store?.disconnect()
            self.settings = settings
            install(client, demo: false, root: start, entries: initial)
            activeConnectionID = profile.id
            savedConnections = history.connections
            credentialWarning = [folderNotice, warning].compactMap { $0 }.joined(separator: "\n\n")
            if credentialWarning?.isEmpty == true { credentialWarning = nil }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func openDemo(at destination: String = "/") async {
        guard !isBusy, !isConnecting else { return }
        await store?.disconnect()
        let demo = DemoStore.make()
        let initial = (try? await DirectoryBrowser.entries(in: destination,
            includingSubfolders: false, store: demo)) ?? []
        install(demo, demo: true, root: destination, entries: initial)
        activeConnectionID = nil
        history.rememberDemo(path: destination)
        credentialWarning = nil
    }

    private func install(_ store: any PhotoStore, demo: Bool, root: String, entries: [RemoteEntry]) {
        connectionID = UUID()
        folderTask?.cancel(); folderTask = nil
        folderRequest = UUID()
        let server = (try? settings.serverURL().absoluteString.lowercased()) ?? settings.server.lowercased()
        let scope = demo ? "demo-\(connectionID)" : String(data: (try? JSONEncoder().encode([
            server, settings.share.trimmingCharacters(in: .whitespaces),
            settings.username, settings.domain
        ])) ?? Data(), encoding: .utf8) ?? "\(connectionID)"
        self.store = store; pipeline = ImagePipeline(store: store, scope: scope); writer = SafeRatingWriter(store: store)
        rootPath = "/"; path = root; self.entries = entries; ratings = [:]
        includeSubfolders = false; foldersExpanded = true
        isDemo = demo; connected = true; isLoading = false; revision = UUID()
    }

    @discardableResult
    func loadFolder(_ destination: String, includingSubfolders: Bool? = nil, refreshPreviews: Bool = false) async -> Bool {
        guard let store, !isBusy, !isConnecting else { return false }
        let endActivity = ReadExecutionCoordinator.shared.beginActivity()
        defer { endActivity() }
        let changesFolder = destination != path
        // Recursive browsing belongs to this location; refreshing it keeps the
        // selection, while navigating elsewhere always starts with direct children.
        let recursive = !changesFolder && (includingSubfolders ?? includeSubfolders)
        folderTask?.cancel()
        let request = UUID(); folderRequest = request; isLoading = true
        let task = Task { try await DirectoryBrowser.entries(in: destination, includingSubfolders: recursive, store: store) }
        folderTask = task
        defer {
            if folderRequest == request { isLoading = false; folderTask = nil }
        }
        do {
            let result = try await task.value
            guard folderRequest == request else { return false }
            if refreshPreviews {
                await pipeline?.invalidate(paths: result.filter { !$0.isDirectory }.map(\.path))
                guard folderRequest == request else { return false }
            }
            await pipeline?.acceptListing(result)
            guard folderRequest == request else { return false }
            path = destination; entries = result; ratings = [:]
            if changesFolder || recursive != includeSubfolders {
                foldersExpanded = !recursive
            }
            includeSubfolders = recursive
            revision = UUID()
            if isDemo { history.rememberDemo(path: destination) }
            else if let activeConnectionID {
                history.updatePath(destination, for: activeConnectionID)
                savedConnections = history.connections
            }
            return true
        } catch is CancellationError { return false }
        catch { if folderRequest == request { self.error = error.localizedDescription }; return false }
    }

    func cancelLoading() {
        folderRequest = UUID()
        folderTask?.cancel(); folderTask = nil; isLoading = false
    }

    func goUp() async {
        guard canGoUp else { return }
        let parent = (path as NSString).deletingLastPathComponent
        await loadFolder(parent.isEmpty ? "/" : parent)
    }

    func disconnect() async {
        guard !isBusy, !isConnecting else { return }
        connectionID = UUID()
        cancelLoading(); await store?.disconnect()
        store = nil; writer = nil; pipeline = nil
        connected = false; entries = []; ratings = [:]; isLoading = false; credentialWarning = nil
        includeSubfolders = false; foldersExpanded = true
        activeConnectionID = nil
        history.clearActive()
    }

    func save(rating: Int, entry: RemoteEntry, expected: Data) async throws -> RatingSaveResult {
        guard let writer, !isBusy, !isConnecting else { throw RatingError.busy }
        isSaving = true
        defer { isSaving = false }
        let result = try await writer.save(rating: rating, path: entry.path, expected: expected)
        try await pipeline?.update(result.data, path: entry.path)
        ratings[entry.path] = rating
        return result
    }

    func deletionRequest(for entry: RemoteEntry) -> FileDeletionRequest? {
        guard !isBusy, !isConnecting, !isLoading, !entry.isDirectory, entries.contains(entry) else { return nil }
        return FileDeletionRequest(entry: entry, connectionID: connectionID, isDemo: isDemo,
            location: "\(settings.server)/\(settings.share)")
    }

    func moveRequest(for entry: RemoteEntry) -> FileMoveRequest? {
        guard !isBusy, !isConnecting, !isLoading, !entry.isDirectory, !entry.isSymbolicLink,
              entries.contains(entry) else { return nil }
        return FileMoveRequest(entry: entry, connectionID: connectionID)
    }

    func moveDestinationContents(_ folder: String, for request: FileMoveRequest) async throws -> [RemoteEntry] {
        guard let store, request.connectionID == connectionID, entries.contains(request.entry),
              !isBusy, !isConnecting, !isLoading else { throw FileMoveError.staleRequest }
        guard FileMover.isValidFolder(folder) else { throw FileMoveError.invalidPath }
        let result = try await store.list(folder)
        try Task.checkCancellation()
        guard request.connectionID == connectionID else { throw FileMoveError.staleRequest }
        return result.filter {
            !$0.name.hasPrefix(".") && FileMover.isValidFolder($0.path)
                && $0.path == (folder as NSString).appendingPathComponent($0.name)
                && !$0.name.contains("/") && !$0.name.isEmpty
        }
    }

    func moveFile(_ request: FileMoveRequest, to folder: String) async throws {
        guard !isBusy, !isConnecting, !isLoading else { throw RatingError.busy }
        guard let store, request.connectionID == connectionID, entries.contains(request.entry)
        else { throw FileMoveError.staleRequest }
        isMoving = true
        defer { isMoving = false }
        let moved = try await FileMover.move(request.entry, to: folder, store: store)
        await pipeline?.remove(request.entry.path)
        await pipeline?.remove(moved.path)
        entries.removeAll { $0.path == request.entry.path || $0.path == moved.path }
        let parent = (moved.path as NSString).deletingLastPathComponent
        if parent == path || (includeSubfolders && moved.path.hasPrefix(path == "/" ? "/" : path + "/")) {
            entries.append(moved)
        }
        ratings.removeValue(forKey: request.entry.path)
        ratings.removeValue(forKey: moved.path)
    }

    // Only called after the user confirms the exact file in the deletion dialog.
    func deleteFile(_ request: FileDeletionRequest) async throws {
        guard !isBusy, !isConnecting, !isLoading else { throw RatingError.busy }
        guard let store, request.connectionID == connectionID, !request.entry.isDirectory,
              entries.contains(request.entry) else { throw FileDeletionError.staleRequest }
        isDeleting = true
        defer { isDeleting = false }
        try await store.remove(request.entry.path)
        await pipeline?.remove(request.entry.path)
        entries.removeAll { $0.path == request.entry.path }
        ratings.removeValue(forKey: request.entry.path)
    }
}

struct FileMoveRequest: Identifiable {
    let id = UUID()
    let entry: RemoteEntry
    let connectionID: UUID
    var sourceFolder: String { (entry.path as NSString).deletingLastPathComponent }
}

struct FileDeletionRequest {
    let entry: RemoteEntry
    let connectionID: UUID
    let isDemo: Bool
    let location: String

    var message: String {
        if isDemo {
            return "„\(entry.name)“ aus der Demobibliothek entfernen? Beim erneuten Öffnen der Demo ist das Beispielbild wieder vorhanden."
        }
        return "„\(entry.name)“ wird dauerhaft von \(location) gelöscht.\n\nPfad: \(entry.path)\n\nDies kann in der App nicht rückgängig gemacht werden."
    }
}

enum FileDeletionError: LocalizedError {
    case staleRequest
    var errorDescription: String? { "Die Verbindung oder Dateiliste wurde geändert. Bitte die Datei neu auswählen und das Löschen erneut bestätigen." }
}
