import XCTest
@testable import RatingCore

final class DirectoryBrowserTests: XCTestCase {
    private func file(_ path: String, directory: Bool = false, link: Bool = false) -> RemoteEntry {
        RemoteEntry(path: path, name: (path as NSString).lastPathComponent,
                    isDirectory: directory, size: 0, isSymbolicLink: link)
    }

    func testDirectViewDoesNotReadSubfolders() async throws {
        let store = DirectoryFixture(["/Fotos": [file("/Fotos/a.jpg"), file("/Fotos/Sub", directory: true), file("/Fotos/readme.txt")]])
        let result = try await DirectoryBrowser.entries(in: "/Fotos", includingSubfolders: false, store: store)
        XCTAssertEqual(Set(result.map(\.path)), ["/Fotos/a.jpg", "/Fotos/Sub"])
        let visited = await store.visited
        XCTAssertEqual(visited, ["/Fotos"])
    }

    func testRecursiveViewPreservesDuplicateNamesAndOnlyDirectFolderTiles() async throws {
        let store = DirectoryFixture([
            "/Fotos": [file("/Fotos/a.jpg"), file("/Fotos/Sub", directory: true)],
            "/Fotos/Sub": [file("/Fotos/Sub/a.jpg"), file("/Fotos/Sub/Tief", directory: true)],
            "/Fotos/Sub/Tief": [file("/Fotos/Sub/Tief/a.jpg"), file("/Fotos/Sub/Tief/notes.txt")]
        ])
        let result = try await DirectoryBrowser.entries(in: "/Fotos", includingSubfolders: true, store: store)
        XCTAssertEqual(Set(result.filter { !$0.isDirectory }.map(\.path)),
                       ["/Fotos/a.jpg", "/Fotos/Sub/a.jpg", "/Fotos/Sub/Tief/a.jpg"])
        XCTAssertEqual(result.filter(\.isDirectory).map(\.path), ["/Fotos/Sub"])
        XCTAssertEqual(file("/Fotos/a.jpg").relativeFolder(to: "/Fotos"), "Dieser Ordner")
        XCTAssertEqual(file("/Fotos/Sub/Tief/a.jpg").relativeFolder(to: "/Fotos"), "Sub/Tief")
        XCTAssertEqual(file("/Fotos/a.jpg").relativeFolder(to: "/"), "Fotos")
    }

    func testHiddenFoldersLinksAndPathsOutsideTheTreeAreNotTraversed() async throws {
        let store = DirectoryFixture(["/Fotos": [
            file("/Fotos/.hidden", directory: true), file("/Fotos/.secret.jpg"),
            file("/Fotos/Link", directory: true, link: true),
            RemoteEntry(path: "/Andere/Bild.jpg", name: "Bild.jpg", isDirectory: false, size: 0),
            RemoteEntry(path: "/Fotos/..", name: "..", isDirectory: true, size: 0),
            RemoteEntry(path: "/Fotos/Sub/../Escape", name: "Sub/../Escape", isDirectory: true, size: 0)
        ]])
        let result = try await DirectoryBrowser.entries(in: "/Fotos", includingSubfolders: true, store: store)
        XCTAssertEqual(result.map(\.path), ["/Fotos/Link"])
        let visited = await store.visited
        XCTAssertEqual(visited, ["/Fotos"])
    }

    func testFailureInSubfolderDoesNotReturnAnIncompleteSuccess() async throws {
        let store = DirectoryFixture(["/Fotos": [file("/Fotos/a.jpg"), file("/Fotos/Private", directory: true)]])
        do {
            _ = try await DirectoryBrowser.entries(in: "/Fotos", includingSubfolders: true, store: store)
            XCTFail("Unreadable descendant must be reported")
        } catch let error as DirectoryReadError {
            XCTAssertEqual(error.path, "/Fotos/Private")
        }
    }

    func testCancellationStopsBeforeReadingMoreFolders() async throws {
        let store = DirectoryFixture(["/Fotos": [file("/Fotos/Sub", directory: true)]], cancelAfterListing: true)
        let task = Task { try await DirectoryBrowser.entries(in: "/Fotos", includingSubfolders: true, store: store) }
        do {
            _ = try await task.value
            XCTFail("Cancelled listing must not succeed")
        } catch is CancellationError {}
        let visited = await store.visited
        XCTAssertEqual(visited, ["/Fotos"])
    }

    func testExistingInitialListingIsReused() async throws {
        let store = DirectoryFixture(["/Fotos/Sub": [file("/Fotos/Sub/a.jpg")]])
        let result = try await DirectoryBrowser.entries(in: "/Fotos", includingSubfolders: true, store: store,
                                                       initial: [file("/Fotos/Sub", directory: true)])
        XCTAssertEqual(result.filter { !$0.isDirectory }.map(\.path), ["/Fotos/Sub/a.jpg"])
        let visited = await store.visited
        XCTAssertEqual(visited, ["/Fotos/Sub"])
    }
}

private actor DirectoryFixture: RemoteDirectoryStore {
    let tree: [String: [RemoteEntry]]
    let cancelAfterListing: Bool
    private(set) var visited: [String] = []
    init(_ tree: [String: [RemoteEntry]], cancelAfterListing: Bool = false) {
        self.tree = tree; self.cancelAfterListing = cancelAfterListing
    }
    func list(_ path: String) async throws -> [RemoteEntry] {
        visited.append(path)
        guard let entries = tree[path] else { throw POSIXError(.EACCES) }
        if cancelAfterListing { withUnsafeCurrentTask { $0?.cancel() } }
        return entries
    }
}
