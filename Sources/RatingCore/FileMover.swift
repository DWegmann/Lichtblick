import Foundation

enum FileMoveError: LocalizedError {
    case invalidPath
    case sameFolder
    case destinationExists
    case sourceUnavailable
    case verification
    case staleRequest
    case notConfirmed(source: String, destination: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidPath: return String(localized: "Dieser Datei- oder Ordnerpfad kann nicht zum Verschieben verwendet werden.")
        case .sameFolder: return String(localized: "Die Datei befindet sich bereits in diesem Ordner.")
        case .destinationExists: return String(localized: "Im Zielordner gibt es bereits einen Eintrag mit diesem Namen. Es wurde nichts überschrieben.")
        case .sourceUnavailable: return String(localized: "Die Quelldatei ist nicht mehr vorhanden oder kann nicht verschoben werden. Bitte die Übersicht neu laden.")
        case .verification: return String(localized: "Quell- und Zielordner entsprechen nach dem Verschieben nicht dem erwarteten Stand.")
        case .staleRequest: return String(localized: "Die Verbindung oder Dateiliste wurde geändert. Bitte die Datei erneut zum Verschieben auswählen.")
        case let .notConfirmed(source, destination, reason):
            return String(localized: "Das Verschieben konnte nicht bestätigt werden. Bitte Quell- und Zielordner neu laden, um den aktuellen Stand zu prüfen.\n\nQuelle: \(String(source))\nZiel: \(String(destination))\n\n\(String(reason))")
        }
    }
}

enum FileMover {
    static func isValidFolder(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        return path == "/" || path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func destinationPath(for entry: RemoteEntry, in folder: String) throws -> String {
        guard isValidFolder(folder), isValidFolder(entry.path),
              !entry.isDirectory, !entry.isSymbolicLink, !entry.name.isEmpty, !entry.name.contains("/"),
              entry.name == (entry.path as NSString).lastPathComponent else { throw FileMoveError.invalidPath }
        let destination = (folder as NSString).appendingPathComponent(entry.name)
        guard destination != entry.path else { throw FileMoveError.sameFolder }
        return destination
    }

    static func move(_ entry: RemoteEntry, to folder: String,
                     store: any RemoteFileStore & RemoteDirectoryStore) async throws -> RemoteEntry {
        let destination = try destinationPath(for: entry, in: folder)
        let sourceFolder = (entry.path as NSString).deletingLastPathComponent
        let sourceEntries = try await store.list(sourceFolder)
        guard let source = sourceEntries.first(where: {
            $0.path == entry.path && $0.name == entry.name && !$0.isDirectory && !$0.isSymbolicLink
        }) else { throw FileMoveError.sourceUnavailable }
        let targetEntries = try await store.list(folder)
        guard !targetEntries.contains(where: { $0.name.localizedCaseInsensitiveCompare(entry.name) == .orderedSame })
        else { throw FileMoveError.destinationExists }
        try Task.checkCancellation()

        // SMBStore's rename uses replace_if_exist = 0, so a destination created
        // after the listing is also protected. Never fall back to copy/delete.
        do {
            try await store.move(entry.path, to: destination)
            let remaining = try await store.list(sourceFolder)
            let arrived = try await store.list(folder)
            guard !remaining.contains(where: { $0.path == entry.path }),
                  let moved = arrived.first(where: {
                      $0.path == destination && !$0.isDirectory && !$0.isSymbolicLink && $0.size == source.size
                  }) else { throw FileMoveError.verification }
            return moved
        } catch {
            // A lost rename response may still mean the server moved the file.
            // Report both locations and never repeat the mutation automatically.
            throw FileMoveError.notConfirmed(source: entry.path, destination: destination,
                                             reason: error.localizedDescription)
        }
    }
}
