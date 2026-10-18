import XCTest
import ImageIO
import CoreGraphics
@testable import RatingCore

final class PreviewCacheTests: XCTestCase {
    private func entry(_ path: String = "/photo.jpg", size: Int64 = 100, date: Date? = Date(timeIntervalSince1970: 100)) -> RemoteEntry {
        RemoteEntry(path: path, name: (path as NSString).lastPathComponent, isDirectory: false,
                    size: size, modificationDate: date)
    }

    private func thumbnail() -> Data {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testSurvivesNewCacheInstanceAndStoresOnlyImageBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = PreviewDiskCache(directory: directory)
        await first.store(thumbnail(), scope: "server/share/user", entry: entry())
        let second = PreviewDiskCache(directory: directory)
        let loaded = await second.load(scope: "server/share/user", entry: entry())
        XCTAssertEqual(loaded, thumbnail())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: file), thumbnail())
        let metadata = try PhotoMetadata.read(try XCTUnwrap(loaded))
        XCTAssertEqual(metadata.rating, 0)
        XCTAssertEqual(metadata.origin, "Ohne Bewertung")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.joined().contains("photo"))
    }


    func testRemovesLegacyCacheContainingMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("PhotoPreviews-v1")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old cached rating".utf8).write(to: legacy.appendingPathComponent("old.preview"))
        let cache = PreviewDiskCache(directory: root.appendingPathComponent("PhotoPreviews-v2"), legacyDirectory: legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        await cache.store(thumbnail(), scope: "a", entry: entry())
        let image = await cache.load(scope: "a", entry: entry())
        XCTAssertEqual(image, thumbnail())
    }

    func testSeparatesConnectionsPathsAndFileVersions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PreviewDiskCache(directory: directory)
        await cache.store(thumbnail(), scope: "server-a", entry: entry())
        let otherServer = await cache.load(scope: "server-b", entry: entry())
        let otherPath = await cache.load(scope: "server-a", entry: entry("/sub/photo.jpg"))
        let otherSize = await cache.load(scope: "server-a", entry: entry(size: 101))
        let otherDate = await cache.load(scope: "server-a", entry: entry(date: Date(timeIntervalSince1970: 101)))
        XCTAssertNil(otherServer)
        XCTAssertNil(otherPath)
        XCTAssertNil(otherSize)
        XCTAssertNil(otherDate)
    }

    func testInvalidationRemovesAllVersionsForOnlyThisPathAndConnection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PreviewDiskCache(directory: directory)
        await cache.store(thumbnail(), scope: "a", entry: entry())
        await cache.store(thumbnail(), scope: "a", entry: entry(size: 101))
        await cache.store(thumbnail(), scope: "b", entry: entry())
        await cache.store(thumbnail(), scope: "a", entry: entry("/other.jpg"))
        await cache.remove(scope: "a", paths: ["/photo.jpg"])
        let original = await cache.load(scope: "a", entry: entry())
        let version = await cache.load(scope: "a", entry: entry(size: 101))
        let otherScope = await cache.load(scope: "b", entry: entry())
        let otherPath = await cache.load(scope: "a", entry: entry("/other.jpg"))
        XCTAssertNil(original)
        XCTAssertNil(version)
        XCTAssertNotNil(otherScope)
        XCTAssertNotNil(otherPath)
    }

    func testMissingTimestampAndCorruptCacheFallBackToSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PreviewDiskCache(directory: directory)
        await cache.store(thumbnail(), scope: "a", entry: entry(date: nil))
        let unknownVersion = await cache.load(scope: "a", entry: entry(date: nil))
        XCTAssertNil(unknownVersion)
        await cache.store(thumbnail(), scope: "a", entry: entry())
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        try Data("broken".utf8).write(to: file)
        let corrupted = await cache.load(scope: "a", entry: entry())
        XCTAssertNil(corrupted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testEvictsLeastRecentlyUsedFilesToRespectGlobalLimit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = thumbnail().count
        let cache = PreviewDiskCache(directory: directory, maximumBytes: bytes * 2)
        await cache.store(thumbnail(), scope: "a", entry: entry("/one.jpg"))
        await cache.store(thumbnail(), scope: "b", entry: entry("/two.jpg"))
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for url in urls { try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: url.path) }
        _ = await cache.load(scope: "a", entry: entry("/one.jpg"))
        await cache.store(thumbnail(), scope: "c", entry: entry("/three.jpg"))
        let one = await cache.load(scope: "a", entry: entry("/one.jpg"))
        let two = await cache.load(scope: "b", entry: entry("/two.jpg"))
        let three = await cache.load(scope: "c", entry: entry("/three.jpg"))
        XCTAssertNotNil(one)
        XCTAssertNil(two)
        XCTAssertNotNil(three)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }

    func testPrefetchFollowsDisplayedOrderAndStaysBoundedAtBothEnds() {
        let photos = (0..<100).map { entry("/\($0).jpg") }
        let window = PreviewPrefetchWindow.entries(in: photos, visible: ["/40.jpg", "/41.jpg"])
        XCTAssertEqual(window.count, 24)
        XCTAssertEqual(Array(window.prefix(4)).map(\.path), ["/42.jpg", "/39.jpg", "/43.jpg", "/38.jpg"])
        XCTAssertFalse(window.contains { ["/40.jpg", "/41.jpg"].contains($0.path) })
        XCTAssertEqual(PreviewPrefetchWindow.entries(in: photos, visible: ["/0.jpg"]).count, 12)
        XCTAssertEqual(PreviewPrefetchWindow.entries(in: photos, visible: ["/99.jpg"]).count, 12)
        XCTAssertTrue(PreviewPrefetchWindow.entries(in: photos, visible: []).isEmpty)
        let reversed = PreviewPrefetchWindow.entries(in: photos.reversed(), visible: ["/40.jpg"])
        XCTAssertEqual(reversed.first?.path, "/39.jpg")
    }
}
