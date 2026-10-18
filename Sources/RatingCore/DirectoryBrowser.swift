import Foundation

struct RemoteEntry: Identifiable, Sendable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    var isSymbolicLink = false
    var modificationDate: Date? = nil
    var id: String { path }
    var isImage: Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp", "bmp", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"].contains((name as NSString).pathExtension.lowercased())
    }

    func relativeFolder(to root: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        let prefix = root == "/" ? "/" : root + "/"
        return parent == root ? "Dieser Ordner" : String(parent.dropFirst(prefix.count))
    }
}

protocol RemoteDirectoryStore: Sendable {
    func list(_ path: String) async throws -> [RemoteEntry]
}

enum DirectoryBrowser {
    // Retain only the current folder's navigation tiles, plus images from the
    // requested subtree. Original full paths remain the identity for all edits.
    static func entries(in root: String, includingSubfolders: Bool,
                        store: any RemoteDirectoryStore, initial: [RemoteEntry]? = nil) async throws -> [RemoteEntry] {
        var pending = [root]
        var visited = Set<String>()
        var result: [RemoteEntry] = []
        while let directory = pending.popLast() {
            try Task.checkCancellation()
            guard visited.insert(directory).inserted else { continue }
            let contents: [RemoteEntry]
            if directory == root, let initial { contents = initial }
            else {
                do { contents = try await store.list(directory) }
                catch is CancellationError { throw CancellationError() }
                catch { throw DirectoryReadError(path: directory, reason: error.localizedDescription) }
            }
            try Task.checkCancellation()
            for entry in contents {
                try Task.checkCancellation()
                // Accept direct children only; never follow hidden directories,
                // symbolic links or malformed entries outside this subtree.
                guard !entry.name.isEmpty, !entry.name.hasPrefix("."), !entry.name.contains("/"),
                      entry.path == (directory as NSString).appendingPathComponent(entry.name) else { continue }
                if entry.isDirectory {
                    if directory == root { result.append(entry) }
                    if includingSubfolders && !entry.isSymbolicLink { pending.append(entry.path) }
                } else if entry.isImage { result.append(entry) }
            }
            if !includingSubfolders { break }
        }
        return result
    }
}

struct DirectoryReadError: LocalizedError {
    let path: String
    let reason: String
    var errorDescription: String? {
        "Der Ordner \(path) konnte nicht gelesen werden: \(reason)\nDie bisherige Ansicht bleibt erhalten."
    }
}
