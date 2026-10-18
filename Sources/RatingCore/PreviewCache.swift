import Foundation
import CryptoKit
import ImageIO

/// Stores only encoded thumbnail pixels, never original metadata or ratings.
/// All connections share one size limit; filenames contain no server or file names.
actor PreviewDiskCache {
    private static let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    static let shared = PreviewDiskCache(legacyDirectory: cacheRoot?
        .appendingPathComponent("PhotoPreviews-v1", isDirectory: true))

    private let directory: URL?
    private let maximumBytes: Int
    private let files = FileManager.default

    init(directory: URL? = cacheRoot?.appendingPathComponent("PhotoPreviews-v2", isDirectory: true),
         maximumBytes: Int = 256 * 1024 * 1024, legacyDirectory: URL? = nil) {
        self.directory = directory
        self.maximumBytes = maximumBytes
        // Remove thumbnails from the old format, which included original metadata.
        if let legacyDirectory { try? FileManager.default.removeItem(at: legacyDirectory) }
    }

    static func memoryKey(_ entry: RemoteEntry, large: Bool) -> String {
        "\(entry.path)|\(entry.size)|\(entry.modificationDate?.timeIntervalSince1970.description ?? "session")|\(large)"
    }

    func load(scope: String, entry: RemoteEntry) -> Data? {
        guard let url = url(scope: scope, entry: entry) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            try? files.removeItem(at: url)
            return nil
        }
        // Modification time of the cache file is its last access time (LRU).
        try? files.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    func store(_ data: Data, scope: String, entry: RemoteEntry) {
        guard let directory, let url = url(scope: scope, entry: entry), data.count <= maximumBytes else { return }
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            trim()
        } catch { /* Cache failures must never prevent displaying a photo. */ }
    }

    func remove(scope: String, paths: [String]) {
        guard let directory else { return }
        let prefixes = Set(paths.map { Self.digest([scope, $0]) })
        for url in (try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            if prefixes.contains(String(url.lastPathComponent.prefix(64))) { try? files.removeItem(at: url) }
        }
    }

    private func url(scope: String, entry: RemoteEntry) -> URL? {
        // Without a server timestamp we cannot validate a thumbnail across sessions.
        guard let directory, entry.modificationDate != nil else { return nil }
        return directory.appendingPathComponent(Self.digest([scope, entry.path]) + "-"
            + Self.digest([Self.memoryKey(entry, large: false)]) + ".preview")
    }

    private static func digest(_ parts: [String]) -> String {
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func trim() {
        guard let directory,
              let urls = try? files.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let entries = urls.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (url, size, _) in entries where total > maximumBytes {
            if (try? files.removeItem(at: url)) != nil { total -= size }
        }
    }
}

enum PreviewPrefetchWindow {
    /// A small margin on both sides also supports scrolling back up.
    static func entries(in photos: [RemoteEntry], visible: Set<String>, margin: Int = 12) -> [RemoteEntry] {
        let indices = photos.indices.filter { visible.contains(photos[$0].path) }
        guard let first = indices.first, let last = indices.last else { return [] }
        let next = photos[(last + 1)..<min(photos.count, last + 1 + margin)]
        let previous = photos[max(0, first - margin)..<first].reversed()
        // Alternate near neighbours so both scroll directions warm up first.
        var result: [RemoteEntry] = []
        let before = Array(previous)
        for offset in 0..<max(next.count, before.count) {
            if offset < next.count { result.append(next[next.startIndex + offset]) }
            if offset < before.count { result.append(before[offset]) }
        }
        return result
    }
}
