import XCTest
@testable import RatingCore

final class FileMoverTests: XCTestCase {
    private let bytes = Data("image bytes with embedded metadata".utf8)
    private var entry: RemoteEntry {
        RemoteEntry(path: "/A/image.jpg", name: "image.jpg", isDirectory: false,
                    size: Int64(bytes.count), modificationDate: Date(timeIntervalSince1970: 123))
    }

    func testMovePreservesBytesAndReturnsNewPath() async throws {
        let store = MoveFixture(files: [entry.path: bytes])
        let moved = try await FileMover.move(entry, to: "/B", store: store)
        XCTAssertEqual(moved.path, "/B/image.jpg")
        let files = await store.files
        XCTAssertNil(files[entry.path])
        XCTAssertEqual(files[moved.path], bytes)
        let operations = await store.moves
        XCTAssertEqual(operations, 1)
    }

    func testMoveToShareRoot() async throws {
        let store = MoveFixture(files: [entry.path: bytes])
        let moved = try await FileMover.move(entry, to: "/", store: store)
        XCTAssertEqual(moved.path, "/image.jpg")
    }

    func testSameFolderAndInvalidPathsNeverMutate() async throws {
        let store = MoveFixture(files: [entry.path: bytes])
        for folder in ["/A", "relative", "/B/../A", "/B//Sub", "/B/", "/B\\Sub", "/B\0"] {
            do {
                _ = try await FileMover.move(entry, to: folder, store: store)
                XCTFail("Must reject \(folder)")
            } catch is FileMoveError {}
        }
        let operations = await store.moves
        XCTAssertEqual(operations, 0)
    }

    func testExistingDestinationIncludingCaseVariantsAndDirectoriesIsProtected() async throws {
        for name in ["image.jpg", "IMAGE.JPG"] {
            let other = Data("existing image".utf8)
            let store = MoveFixture(files: [entry.path: bytes, "/B/\(name)": other])
            do {
                _ = try await FileMover.move(entry, to: "/B", store: store)
                XCTFail("Must reject collision")
            } catch FileMoveError.destinationExists {}
            let files = await store.files
            XCTAssertEqual(files["/B/\(name)"], other)
            XCTAssertEqual(files[entry.path], bytes)
            let operations = await store.moves
            XCTAssertEqual(operations, 0)
        }
        let store = MoveFixture(files: [entry.path: bytes], extraFolder: "/B/image.jpg")
        do {
            _ = try await FileMover.move(entry, to: "/B", store: store)
            XCTFail("Must reject directory collision")
        } catch FileMoveError.destinationExists {}
    }

    func testMissingSourceNeverMutates() async throws {
        let store = MoveFixture(files: [:])
        do {
            _ = try await FileMover.move(entry, to: "/B", store: store)
            XCTFail("Must reject missing source")
        } catch FileMoveError.sourceUnavailable {}
        let operations = await store.moves
        XCTAssertEqual(operations, 0)
    }

    func testMoveAfterRatingChangeUsesFreshFileSize() async throws {
        let updated = Data("new image bytes with freshly saved rating and different size".utf8)
        let store = MoveFixture(files: [entry.path: updated])
        let moved = try await FileMover.move(entry, to: "/B", store: store)
        let files = await store.files
        XCTAssertEqual(files[moved.path], updated)
        XCTAssertEqual(moved.size, Int64(updated.count))
    }

    func testDirectoriesAndSymbolicLinksAreNotMoved() async throws {
        for file in [RemoteEntry(path: "/A", name: "A", isDirectory: true, size: 0),
                     RemoteEntry(path: entry.path, name: entry.name, isDirectory: false,
                                 size: entry.size, isSymbolicLink: true)] {
            do {
                _ = try await FileMover.move(file, to: "/B", store: MoveFixture(files: [entry.path: bytes]))
                XCTFail("Must reject directory or symlink")
            } catch FileMoveError.invalidPath {}
        }
    }

    func testDestinationCreatedDuringMoveIsNotOverwritten() async throws {
        let store = MoveFixture(files: [entry.path: bytes], race: true)
        do {
            _ = try await FileMover.move(entry, to: "/B", store: store)
            XCTFail("Must report failed rename")
        } catch FileMoveError.notConfirmed {}
        let files = await store.files
        XCTAssertEqual(files[entry.path], bytes)
        XCTAssertEqual(files["/B/image.jpg"], Data("concurrent file".utf8))
    }

    func testPermissionFailureLeavesSourceAndReportsBothPaths() async throws {
        let store = MoveFixture(files: [entry.path: bytes], denied: true)
        do {
            _ = try await FileMover.move(entry, to: "/B", store: store)
            XCTFail("Must report denied rename")
        } catch let FileMoveError.notConfirmed(source, destination, _) {
            XCTAssertEqual(source, entry.path)
            XCTAssertEqual(destination, "/B/image.jpg")
        }
        let files = await store.files
        XCTAssertEqual(files[entry.path], bytes)
        XCTAssertNil(files["/B/image.jpg"])
    }

    func testLostResponseAndVerificationFailureAreNeverRetried() async throws {
        for lostResponse in [true, false] {
            let store = MoveFixture(files: [entry.path: bytes], lostResponse: lostResponse,
                                    failVerification: !lostResponse)
            do {
                _ = try await FileMover.move(entry, to: "/B", store: store)
                XCTFail("Must report uncertain result")
            } catch FileMoveError.notConfirmed {}
            let operations = await store.moves
            let files = await store.files
            XCTAssertEqual(operations, 1)
            XCTAssertEqual(files["/B/image.jpg"], bytes)
        }
    }

    func testCancellationDoesNotStartMove() async throws {
        let store = MoveFixture(files: [entry.path: bytes])
        let file = entry
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileMover.move(file, to: "/B", store: store)
        }
        do {
            _ = try await task.value
            XCTFail("Must honour cancellation")
        } catch is CancellationError {}
        let operations = await store.moves
        XCTAssertEqual(operations, 0)
    }
}

private actor MoveFixture: RemoteFileStore, RemoteDirectoryStore {
    var files: [String: Data]
    var moves = 0
    let directories: Set<String>
    let race: Bool
    let denied: Bool
    let lostResponse: Bool
    let failVerification: Bool

    init(files: [String: Data], extraFolder: String? = nil, race: Bool = false,
         denied: Bool = false, lostResponse: Bool = false, failVerification: Bool = false) {
        self.files = files
        directories = Set(["/", "/A", "/B"] + (extraFolder.map { [$0] } ?? []))
        self.race = race; self.denied = denied
        self.lostResponse = lostResponse; self.failVerification = failVerification
    }

    func list(_ path: String) async throws -> [RemoteEntry] {
        guard directories.contains(path) else { throw POSIXError(.ENOENT) }
        if failVerification && moves > 0 { throw POSIXError(.EIO) }
        let entries = files.map { path, data in
            RemoteEntry(path: path, name: (path as NSString).lastPathComponent, isDirectory: false,
                        size: Int64(data.count), modificationDate: Date(timeIntervalSince1970: 123))
        } + directories.filter { $0 != "/" }.map {
            RemoteEntry(path: $0, name: ($0 as NSString).lastPathComponent, isDirectory: true, size: 0)
        }
        return entries.filter { ($0.path as NSString).deletingLastPathComponent == path }
    }

    func move(_ source: String, to destination: String) async throws {
        moves += 1
        if denied { throw POSIXError(.EACCES) }
        if race { files[destination] = Data("concurrent file".utf8) }
        guard files[destination] == nil else { throw POSIXError(.EEXIST) }
        guard let data = files.removeValue(forKey: source) else { throw POSIXError(.ENOENT) }
        files[destination] = data
        if lostResponse { throw POSIXError(.ECONNRESET) }
    }
    func read(_ path: String) async throws -> Data { XCTFail("Move must not download image data"); return Data() }
    func write(_ data: Data, to path: String) async throws { XCTFail("Move must not re-upload image data") }
    func remove(_ path: String) async throws { XCTFail("Move must not delete source as a separate operation") }
}
