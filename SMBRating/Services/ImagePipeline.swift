import UIKit
import ImageIO

struct LoadedPhoto {
    let image: UIImage
    let metadata: PhotoMetadata
}

actor ImagePipeline {
    private struct PreviewResult {
        let image: UIImage
        // Exists only during a fresh transfer, never in either cache.
        let sourceData: Data?
    }

    private struct Request {
        let id: UUID
        let path: String
        let task: Task<PreviewResult, Error>
        var consumers: Int
        var speculative: Bool
    }
    private struct Waiter {
        let id: UUID
        var speculative: Bool
        let continuation: CheckedContinuation<Void, Error>
    }

    private let store: any PhotoStore
    private let scope: String
    private let disk: PreviewDiskCache
    private let cache = NSCache<NSString, UIImage>()
    private var keysByPath: [String: Set<String>] = [:]
    private var changedPaths = Set<String>()
    private var invalidationIDs: [String: UUID] = [:]
    private var requests: [String: Request] = [:]
    private var active = 0
    private var waiting: [Waiter] = []
    private var consumers = Set<UUID>()

    init(store: any PhotoStore, scope: String, disk: PreviewDiskCache = .shared) {
        self.store = store
        self.scope = scope
        self.disk = disk
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    private func acquire(id: UUID, speculative: Bool) async throws {
        try Task.checkCancellation()
        if active < 3 { active += 1; return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting.append(Waiter(id: id, speculative: speculative, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func promote(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.id == id }) { waiting[index].speculative = false }
    }

    private func release() {
        guard !waiting.isEmpty else { active -= 1; return }
        let index = waiting.firstIndex(where: { !$0.speculative }) ?? 0
        waiting.remove(at: index).continuation.resume()
    }

    func load(_ entry: RemoteEntry, large: Bool = false,
              onPreview: (@MainActor @Sendable (UIImage) -> Void)? = nil) async throws -> LoadedPhoto {
        let invalidationID = invalidationIDs[entry.path]
        let preview = try await preview(entry, large: large, speculative: false)
        try Task.checkCancellation()
        await onPreview?(preview.image)
        let data: Data
        if let sourceData = preview.sourceData {
            data = sourceData
        } else {
            // Even a memory/disk hit must read current metadata from the store.
            try await acquire(id: UUID(), speculative: false)
            defer { release() }
            try Task.checkCancellation()
            data = try await store.read(entry.path)
        }
        try Task.checkCancellation()
        guard invalidationIDs[entry.path] == invalidationID else { throw CancellationError() }
        return LoadedPhoto(image: preview.image, metadata: try PhotoMetadata.read(data))
    }

    private func preview(_ entry: RemoteEntry, large: Bool, speculative: Bool) async throws -> PreviewResult {
        try Task.checkCancellation()
        let key = PreviewDiskCache.memoryKey(entry, large: large)
        if let image = cache.object(forKey: key as NSString) { return PreviewResult(image: image, sourceData: nil) }
        var request: Request
        if var existing = requests[key] {
            existing.consumers += 1
            if !speculative { existing.speculative = false }
            requests[key] = existing
            request = existing
            if !speculative { promote(existing.id) }
        } else {
            let id = UUID()
            let task = Task(priority: speculative ? .utility : .userInitiated) {
                try await self.fetch(entry, large: large, key: key, id: id, speculative: speculative)
            }
            request = Request(id: id, path: entry.path, task: task, consumers: 1, speculative: speculative)
            requests[key] = request
        }
        let id = request.id
        let consumer = UUID()
        // A cancelled tile releases its share immediately; a visible consumer
        // can keep an overlapping prefetch alive without a second SMB read.
        consumers.insert(consumer)
        defer { finishConsumer(consumer, key: key, requestID: id) }
        return try await withTaskCancellationHandler {
            let photo = try await request.task.value
            try Task.checkCancellation()
            return photo
        } onCancel: {
            Task { await self.finishConsumer(consumer, key: key, requestID: id) }
        }
    }

    private func finishConsumer(_ consumer: UUID, key: String, requestID: UUID) {
        guard consumers.remove(consumer) != nil,
              var request = requests[key], request.id == requestID else { return }
        request.consumers -= 1
        if request.consumers == 0 {
            request.task.cancel()
            requests.removeValue(forKey: key)
        } else { requests[key] = request }
    }

    private func fetch(_ entry: RemoteEntry, large: Bool, key: String, id: UUID, speculative: Bool) async throws -> PreviewResult {
        try await acquire(id: id, speculative: requests[key]?.speculative ?? speculative)
        defer { release() }
        try Task.checkCancellation()
        if !large, !changedPaths.contains(entry.path),
           let data = await disk.load(scope: scope, entry: entry),
           let image = decodeCachedImage(data) {
            try Task.checkCancellation()
            remember(image, key: key, path: entry.path)
            return PreviewResult(image: image, sourceData: nil)
        }
        let data = try await store.read(entry.path)
        try Task.checkCancellation()
        let image = try decodeImage(data, maxPixels: large ? 3200 : 520)
        if !large, !changedPaths.contains(entry.path), let thumbnail = encodeThumbnail(image) {
            await disk.store(thumbnail, scope: scope, entry: entry)
        }
        try Task.checkCancellation()
        remember(image, key: key, path: entry.path)
        return PreviewResult(image: image, sourceData: data)
    }

    private func remember(_ image: UIImage, key: String, path: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
        keysByPath[path, default: []].insert(key)
    }

    private func decodeCachedImage(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private func encodeThumbnail(_ image: UIImage) -> Data? {
        switch image.cgImage?.alphaInfo {
        case .first?, .last?, .premultipliedFirst?, .premultipliedLast?: return image.pngData()
        default: return image.jpegData(compressionQuality: 0.85)
        }
    }

    func prefetch(_ entries: [RemoteEntry]) async {
        // Only one speculative transfer per window; visible tiles take queue priority.
        for entry in entries {
            guard !Task.isCancelled else { return }
            do { _ = try await preview(entry, large: false, speculative: true) }
            catch is CancellationError { return }
            catch { /* A visible tile owns error display and retries. */ }
        }
    }

    func original(_ path: String) async throws -> Data { try await store.read(path) }

    func detail(_ entry: RemoteEntry) async throws -> (LoadedPhoto, Data) {
        try await acquire(id: UUID(), speculative: false)
        defer { release() }
        try Task.checkCancellation()
        let data = try await store.read(entry.path)
        try Task.checkCancellation()
        return (LoadedPhoto(image: try decodeImage(data, maxPixels: 3200), metadata: try PhotoMetadata.read(data)), data)
    }

    func update(_ data: Data, path: String) async throws {
        _ = try PhotoMetadata.read(data)
        // The current listing still has the original size/timestamp. Do not
        // persist a changed image under that old version before the next listing.
        changedPaths.insert(path)
        await invalidate(paths: [path])
    }

    func remove(_ path: String) async {
        changedPaths.insert(path)
        await invalidate(paths: [path])
    }

    func acceptListing(_ entries: [RemoteEntry]) {
        changedPaths.subtract(entries.map(\.path))
    }

    func invalidate(paths: [String]) async {
        let pathsToRemove = Set(paths)
        for path in paths {
            invalidationIDs[path] = UUID()
            for key in keysByPath.removeValue(forKey: path) ?? [] { cache.removeObject(forKey: key as NSString) }
        }
        for (key, request) in requests where pathsToRemove.contains(request.path) {
            request.task.cancel()
            requests.removeValue(forKey: key)
        }
        await disk.remove(scope: scope, paths: paths)
    }

    private func decodeImage(_ data: Data, maxPixels: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw RatingError.invalidImage }
        return UIImage(cgImage: cgImage)
    }
}
