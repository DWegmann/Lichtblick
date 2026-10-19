import XCTest
@testable import RatingCore

final class RatingFilterTests: XCTestCase {
    private func entry(_ path: String, folder: Bool = false) -> RemoteEntry {
        RemoteEntry(path: path, name: (path as NSString).lastPathComponent, isDirectory: folder, size: 1)
    }

    func testExactRatingsAndUnknownValues() {
        for filter in RatingFilter.allCases where filter != .all {
            for rating in -1...5 { XCTAssertEqual(filter.matches(rating), filter.rawValue == rating) }
            XCTAssertFalse(filter.matches(nil), "An unreadable rating must not mean unrated")
        }
        XCTAssertTrue(RatingFilter.all.matches(nil))
        XCTAssertTrue(RatingFilter.all.matches(-1))
        XCTAssertTrue(RatingFilter.unrated.matches(0))
        XCTAssertFalse(RatingFilter.unrated.matches(-1))
    }

    func testCombinesSearchSortAndRatingWithoutFilteringFoldersOrLosingPaths() {
        let source = [entry("/A/Bild2.jpg"), entry("/B/Bild2.jpg"), entry("/Bild10.jpg"),
                      entry("/Bild1.jpg"), entry("/Bildordner", folder: true), entry("/Anders.jpg")]
        let base = BrowserListing(entries: source, query: "Bild", descending: true)
        let ratings = ["/A/Bild2.jpg": 4, "/B/Bild2.jpg": 1, "/Bild10.jpg": 4, "/Bild1.jpg": 0]
        let result = base.filtered(by: .four, ratings: ratings)
        XCTAssertEqual(result.photos.map(\.path), ["/Bild10.jpg", "/A/Bild2.jpg"])
        XCTAssertEqual(result.folders.map(\.path), ["/Bildordner"])
        XCTAssertEqual(result.photoIndices["/A/Bild2.jpg"], 1)
        XCTAssertNil(result.photoIndices["/B/Bild2.jpg"])
        XCTAssertEqual(base.filtered(by: .unrated, ratings: ratings).photos.map(\.path), ["/Bild1.jpg"])
        XCTAssertEqual(base.filtered(by: .all, ratings: [:]), base)
        XCTAssertTrue(base.filtered(by: .five, ratings: ratings).photos.isEmpty)
    }

    func testScanPreservesRejectionAndSeparatesErrorsFromZeroStars() async throws {
        let source = (-1...5).map { entry("/\($0).jpg") } + [entry("/denied.jpg"), entry("/invalid.jpg")]
        let result = try await RatingScanner.scan(source) { entry in
            if entry.path == "/denied.jpg" { throw POSIXError(.EACCES) }
            if entry.path == "/invalid.jpg" { return 99 }
            return Int((entry.name as NSString).deletingPathExtension)!
        }
        XCTAssertEqual(result.ratings.count, 7)
        XCTAssertEqual(result.ratings["/0.jpg"], 0)
        XCTAssertEqual(result.ratings["/-1.jpg"], -1)
        XCTAssertNil(result.ratings["/denied.jpg"])
        XCTAssertNil(result.ratings["/invalid.jpg"])
        XCTAssertEqual(Set(result.failedPaths), ["/denied.jpg", "/invalid.jpg"])
    }

    func testReadsAreBoundedAndProgressCountsAllEntries() async throws {
        let source = (0..<40).map { entry("/\($0).jpg") }
        let fixture = RatingReadFixture(delay: 2_000_000)
        let progress = RatingProgressFixture()
        let result = try await RatingScanner.scan(source, read: { try await fixture.read($0) },
                                                  progress: { await progress.record($0) })
        let maximum = await fixture.maximumActive
        let count = await fixture.readCount
        let updates = await progress.values
        XCTAssertEqual(result.ratings.count, 40)
        XCTAssertTrue(result.failedPaths.isEmpty)
        XCTAssertLessThanOrEqual(maximum, 3)
        XCTAssertEqual(count, 40)
        XCTAssertEqual(updates, Array(1...40))
    }

    func testCancellationStopsPendingEntriesAndDoesNotBecomeAReadFailure() async throws {
        let source = (0..<800).map { entry("/\($0).jpg") }
        let fixture = RatingReadFixture(delay: 2_000_000_000)
        let task = Task { try await RatingScanner.scan(source, read: { try await fixture.read($0) }) }
        for _ in 0..<100 {
            if await fixture.readCount >= 3 { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let count = await fixture.readCount
        let active = await fixture.active
        XCTAssertLessThanOrEqual(count, 3)
        XCTAssertEqual(active, 0)
    }

    func testEachScanReadsFreshValues() async throws {
        let fixture = RatingReadFixture(delay: 0)
        let source = [entry("/same.jpg")]
        let first = try await RatingScanner.scan(source, read: { try await fixture.read($0) })
        await fixture.setRating(5)
        let second = try await RatingScanner.scan(source, read: { try await fixture.read($0) })
        let count = await fixture.readCount
        XCTAssertEqual(first.ratings["/same.jpg"], 0)
        XCTAssertEqual(second.ratings["/same.jpg"], 5)
        XCTAssertEqual(count, 2)
    }

    func testPartialResultsArriveBeforeRemainingReadsFinish() async throws {
        let fixture = StreamingRatingFixture()
        let source = [entry("/match.jpg"), entry("/denied.jpg"), entry("/slow.jpg")]
        let result = try await RatingScanner.scan(source, read: { try await fixture.read($0) },
            update: { path, rating, count in await fixture.record(path, rating: rating, count: count) })
        let events = await fixture.events
        XCTAssertEqual(events.map(\.count), [1, 2, 3])
        let match = try XCTUnwrap(events.first { $0.path == "/match.jpg" })
        XCTAssertEqual(match.rating, 4)
        XCTAssertFalse(match.slowFinished, "Matching photos must be available while other reads are pending")
        XCTAssertLessThan(match.count, source.count)
        let denied = try XCTUnwrap(events.first { $0.path == "/denied.jpg" })
        XCTAssertNil(denied.rating, "A failed read must never appear as zero stars")
        XCTAssertEqual(result.ratings, ["/match.jpg": 4, "/slow.jpg": 0])
        XCTAssertEqual(result.failedPaths, ["/denied.jpg"])
    }

    func testEmptyViewDoesNotReadAnyRatings() async throws {
        let fixture = RatingReadFixture(delay: 0)
        let result = try await RatingScanner.scan([], read: { try await fixture.read($0) })
        let count = await fixture.readCount
        XCTAssertTrue(result.ratings.isEmpty)
        XCTAssertTrue(result.failedPaths.isEmpty)
        XCTAssertEqual(count, 0)
    }
}

private actor RatingReadFixture {
    let delay: UInt64
    var rating = 0
    var active = 0
    var maximumActive = 0
    var readCount = 0
    init(delay: UInt64) { self.delay = delay }
    func read(_ entry: RemoteEntry) async throws -> Int {
        readCount += 1; active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        return rating
    }
    func setRating(_ value: Int) { rating = value }
}

private actor RatingProgressFixture {
    var values: [Int] = []
    func record(_ value: Int) { values.append(value) }
}

private actor StreamingRatingFixture {
    struct Event: Sendable {
        let path: String
        let rating: Int?
        let count: Int
        let slowFinished: Bool
    }
    var slowFinished = false
    var events: [Event] = []
    func read(_ entry: RemoteEntry) async throws -> Int {
        if entry.path == "/slow.jpg" {
            try await Task.sleep(nanoseconds: 200_000_000)
            slowFinished = true
            return 0
        }
        if entry.path == "/denied.jpg" { throw POSIXError(.EACCES) }
        return 4
    }
    func record(_ path: String, rating: Int?, count: Int) {
        events.append(Event(path: path, rating: rating, count: count, slowFinished: slowFinished))
    }
}
