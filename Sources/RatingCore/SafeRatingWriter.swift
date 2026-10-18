import Foundation

public protocol RemoteFileStore: Sendable {
    func read(_ path: String) async throws -> Data
    func write(_ data: Data, to path: String) async throws
    // Must fail if the destination already exists; never replace another file.
    func move(_ source: String, to destination: String) async throws
    func remove(_ path: String) async throws
}

public struct RatingSaveResult: Sendable {
    public let data: Data
    public let retainedBackup: String?
}

public actor SafeRatingWriter {
    private let store: any RemoteFileStore
    private var saving = false

    public init(store: any RemoteFileStore) { self.store = store }

    public func save(rating: Int, path: String, expected: Data) async throws -> RatingSaveResult {
        guard !saving else { throw RatingError.busy }
        saving = true
        defer { saving = false }
        try Task.checkCancellation()
        guard try await store.read(path) == expected else { throw RatingError.conflict }
        let updated = try PhotoMetadata.settingRating(rating, in: expected)
        let token = UUID().uuidString
        let directory = (path as NSString).deletingLastPathComponent
        let temporary = (directory as NSString).appendingPathComponent(".smbrating-\(token).tmp")
        let backup = (directory as NSString).appendingPathComponent(".smbrating-\(token).backup")

        do {
            try await store.write(updated, to: temporary)
            guard try await store.read(temporary) == updated else { throw RatingError.verification }
            try Task.checkCancellation()
            guard try await store.read(path) == expected else { throw RatingError.conflict }
        } catch {
            try? await store.remove(temporary)
            throw error
        }

        // Keep the original until the replacement has been read back successfully.
        // SMB rename does not offer compare-and-swap: other editors must stay idle.
        do { try await store.move(path, to: backup) }
        catch {
            if let current = try? await store.read(path), current == expected {
                try? await store.remove(temporary)
                throw error
            }
            // A disconnected server can have completed a rename despite a lost response.
            // Preserve temporary files and report the backup location for recovery.
            throw RatingError.recovery(backup)
        }
        do {
            // Verify the moved original too, closing the common concurrent-edit window.
            guard try await store.read(backup) == expected else { throw RatingError.conflict }
            try await store.move(temporary, to: path)
            guard try await store.read(path) == updated else { throw RatingError.verification }
        } catch {
            // Never remove a possibly changed destination after an ambiguous rename.
            // Restore only if the target is definitely absent (the adapter reports ENOENT).
            var missing = false
            do { _ = try await store.read(path) }
            catch { missing = (error as? POSIXError)?.code == .ENOENT }
            if missing {
                do { try await store.move(backup, to: path) }
                catch { throw RatingError.recovery(backup) }
                try? await store.remove(temporary)
                throw error
            }
            throw RatingError.recovery(backup)
        }
        var retainedBackup: String?
        do { try await store.remove(backup) }
        catch { retainedBackup = backup }
        return RatingSaveResult(data: updated, retainedBackup: retainedBackup)
    }
}
