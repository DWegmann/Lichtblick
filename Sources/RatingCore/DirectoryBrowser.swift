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

/// Build once when entries, search or sorting change, never for scroll events.
struct BrowserListing: Equatable {
    let photos: [RemoteEntry]
    let folders: [RemoteEntry]
    let photoIndices: [String: Int]

    private init(photos: [RemoteEntry], folders: [RemoteEntry]) {
        self.photos = photos
        self.folders = folders
        photoIndices = Dictionary(photos.enumerated().map { ($0.element.path, $0.offset) },
                                  uniquingKeysWith: { first, _ in first })
    }

    func filtered(by filter: RatingFilter, ratings: [String: Int]) -> BrowserListing {
        guard filter != .all else { return self }
        return BrowserListing(photos: photos.filter { filter.matches(ratings[$0.path]) }, folders: folders)
    }

    init(entries: [RemoteEntry] = [], query: String = "", descending: Bool = false) {
        let matching = entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        func ordered(_ lhs: RemoteEntry, _ rhs: RemoteEntry) -> Bool {
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.path < rhs.path : order == .orderedAscending
        }
        let images = matching.filter { !$0.isDirectory && $0.isImage }.sorted(by: ordered)
        let directories = matching.filter(\.isDirectory).sorted(by: ordered)
        photos = descending ? Array(images.reversed()) : images
        folders = descending ? Array(directories.reversed()) : directories
        photoIndices = Dictionary(photos.enumerated().map { ($0.element.path, $0.offset) },
                                  uniquingKeysWith: { first, _ in first })
    }
}

enum RatingFilter: Int, CaseIterable, Identifiable, Sendable {
    case all = 6, unrated = 0, one = 1, two = 2, three = 3, four = 4, five = 5, rejected = -1
    var id: Self { self }
    var title: String {
        switch self {
        case .all: return "Alle Bewertungen"
        case .unrated: return "Ohne Bewertung"
        case .one: return "1 Stern"
        case .rejected: return "Abgelehnt"
        default: return "\(rawValue) Sterne"
        }
    }
    func matches(_ rating: Int?) -> Bool {
        self == .all || rating == rawValue
    }
}

struct RatingScanResult: Sendable {
    let ratings: [String: Int]
    let failedPaths: [String]
}

enum RatingScanner {
    /// Fresh reads for this filter operation only. Unknown values never mean zero stars.
    static func scan(_ entries: [RemoteEntry],
                     read: @escaping @Sendable (RemoteEntry) async throws -> Int,
                     update: @escaping @Sendable (String, Int?, Int) async -> Void = { _, _, _ in },
                     progress: @escaping @Sendable (Int) async -> Void = { _ in }) async throws -> RatingScanResult {
        try Task.checkCancellation()
        return try await withThrowingTaskGroup(of: (String, Int?).self) { group in
            func enqueue(_ entry: RemoteEntry) {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let rating = try await read(entry)
                        try Task.checkCancellation()
                        guard (-1...5).contains(rating) else { return (entry.path, nil) }
                        return (entry.path, rating)
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        try Task.checkCancellation()
                        return (entry.path, nil)
                    }
                }
            }
            var next = 0
            while next < min(3, entries.count) { enqueue(entries[next]); next += 1 }
            var ratings: [String: Int] = [:]
            var failed: [String] = []
            var completed = 0
            while let (path, rating) = try await group.next() {
                try Task.checkCancellation()
                if let rating { ratings[path] = rating } else { failed.append(path) }
                completed += 1
                await progress(completed)
                try Task.checkCancellation()
                await update(path, rating, completed)
                try Task.checkCancellation()
                if next < entries.count { enqueue(entries[next]); next += 1 }
            }
            return RatingScanResult(ratings: ratings, failedPaths: failed)
        }
    }
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
