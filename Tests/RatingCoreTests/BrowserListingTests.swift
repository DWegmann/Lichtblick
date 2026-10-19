import XCTest
@testable import RatingCore

final class BrowserListingTests: XCTestCase {
    private func entry(_ path: String, folder: Bool = false) -> RemoteEntry {
        RemoteEntry(path: path, name: (path as NSString).lastPathComponent, isDirectory: folder, size: 1)
    }

    func testNaturalSortSearchAndSeparateFolderSection() {
        let entries = [entry("/Bild10.jpg"), entry("/Bild2.jpg"), entry("/Bild1.jpg"),
                       entry("/Ordner10", folder: true), entry("/Ordner2", folder: true), entry("/readme.txt")]
        let listing = BrowserListing(entries: entries)
        XCTAssertEqual(listing.photos.map(\.name), ["Bild1.jpg", "Bild2.jpg", "Bild10.jpg"])
        XCTAssertEqual(listing.folders.map(\.name), ["Ordner2", "Ordner10"])
        XCTAssertEqual(BrowserListing(entries: entries, descending: true).photos.map(\.name),
                       ["Bild10.jpg", "Bild2.jpg", "Bild1.jpg"])
        let search = BrowserListing(entries: entries, query: "bILD2")
        XCTAssertEqual(search.photos.map(\.name), ["Bild2.jpg"])
        XCTAssertEqual(search.photoIndices["/Bild2.jpg"], 0)
        XCTAssertTrue(search.folders.isEmpty)
    }

    func testDuplicateNamesRetainDistinctPathsInBothSortDirections() {
        let entries = [entry("/B/same.jpg"), entry("/A/same.jpg")]
        let ascending = BrowserListing(entries: entries)
        let descending = BrowserListing(entries: entries, descending: true)
        XCTAssertEqual(ascending.photos.map(\.path), ["/A/same.jpg", "/B/same.jpg"])
        XCTAssertEqual(descending.photos.map(\.path), ["/B/same.jpg", "/A/same.jpg"])
        XCTAssertEqual(descending.photoIndices["/A/same.jpg"], 1)
        XCTAssertEqual(descending.photoIndices["/B/same.jpg"], 0)
    }

    func testIndexedPrefetchMatchesReferenceAcrossLargeCollectionAndSortChanges() {
        let entries = (0..<1200).map { entry("/Foto\($0).jpg") }
        for descending in [false, true] {
            let listing = BrowserListing(entries: entries, descending: descending)
            XCTAssertEqual(listing.photos.count, 1200)
            for start in stride(from: 0, to: 1200, by: 17) {
                let paths = Set(listing.photos[start..<min(start + 16, 1200)].map(\.path))
                let indices = paths.compactMap { listing.photoIndices[$0] }
                let indexed = PreviewPrefetchWindow.entries(in: listing.photos, visibleIndices: indices)
                let reference = PreviewPrefetchWindow.entries(in: listing.photos, visible: paths)
                XCTAssertEqual(indexed, reference)
                XCTAssertLessThanOrEqual(indexed.count, 24)
                XCTAssertTrue(Set(indexed.map(\.path)).isDisjoint(with: paths))
            }
        }
    }

    func testPrefetchIgnoresStaleIndicesAndEmptyVisibility() {
        let photos = (0..<30).map { entry("/\($0).jpg") }
        XCTAssertTrue(PreviewPrefetchWindow.entries(in: photos, visibleIndices: [-1, 30, 800]).isEmpty)
        XCTAssertTrue(PreviewPrefetchWindow.entries(in: photos, visibleIndices: []).isEmpty)
        XCTAssertTrue(PreviewPrefetchWindow.entries(in: photos, visibleIndices: [0], margin: 0).isEmpty)
        XCTAssertEqual(PreviewPrefetchWindow.entries(in: photos, visibleIndices: [0, 1, -1, 500]).count, 12)
    }
}
