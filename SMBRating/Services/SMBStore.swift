import Foundation
import AMSMB2

protocol PhotoStore: RemoteFileStore, RemoteDirectoryStore {
    func disconnect() async
}

actor SMBStore: PhotoStore {
    private let manager: SMB2Manager
    static let maximumBytes = 128 * 1024 * 1024

    init(settings: ConnectionSettings, password: String) throws {
        let url = try settings.serverURL()
        let credential = URLCredential(user: settings.username.isEmpty ? "guest" : settings.username,
                                       password: password, persistence: .forSession)
        guard let manager = SMB2Manager(url: url, domain: settings.domain, credential: credential)
        else { throw ConnectionError.invalidAddress }
        manager.timeout = 30
        self.manager = manager
    }

    func connect(share: String, encrypted: Bool) async throws {
        try await manager.connectShare(name: share, encrypted: encrypted)
    }

    func list(_ path: String) async throws -> [RemoteEntry] {
        try await ReadExecutionCoordinator.shared.read { try await self.listOnce(path) }
    }

    private func listOnce(_ path: String) async throws -> [RemoteEntry] {
        try await manager.contentsOfDirectory(atPath: path).compactMap { item in
            guard let name = item[.nameKey] as? String, !name.hasPrefix(".") else { return nil }
            return RemoteEntry(path: (path as NSString).appendingPathComponent(name), name: name,
                isDirectory: (item[.isDirectoryKey] as? NSNumber)?.boolValue
                    ?? (item[.fileResourceTypeKey] as? URLFileResourceType == .directory),
                size: (item[.fileSizeKey] as? NSNumber)?.int64Value ?? 0,
                isSymbolicLink: (item[.isSymbolicLinkKey] as? NSNumber)?.boolValue ?? false,
                modificationDate: item[.contentModificationDateKey] as? Date)
        }
    }

    func read(_ path: String) async throws -> Data {
        try await ReadExecutionCoordinator.shared.read { try await self.readOnce(path) }
    }

    private func readOnce(_ path: String) async throws -> Data {
        let attributes = try await manager.attributesOfItem(atPath: path)
        try Task.checkCancellation()
        let size = (attributes[.fileSizeKey] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maximumBytes else { throw RatingError.tooLarge }
        let cancellation = ReadCancellation()
        let data: Data = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await manager.contents(atPath: path, range: 0..<(Self.maximumBytes + 1),
                progress: { _, _ in cancellation.shouldContinue })
        } onCancel: {
            cancellation.cancel()
        }
        // AMSMB2 may return the transferred prefix when its progress callback
        // stops a read. Never decode or publish such an interrupted file.
        try Task.checkCancellation()
        guard data.count <= Self.maximumBytes else { throw RatingError.tooLarge }
        return data
    }

    func write(_ data: Data, to path: String) async throws {
        try await manager.write(data: data, toPath: path, progress: nil)
    }
    func move(_ source: String, to destination: String) async throws {
        try await manager.moveItem(atPath: source, toPath: destination)
    }
    func remove(_ path: String) async throws { try await manager.removeFile(atPath: path) }
    func disconnect() async { try? await manager.disconnectShare(gracefully: true) }
}

private final class ReadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var shouldContinue: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !cancelled
    }
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
