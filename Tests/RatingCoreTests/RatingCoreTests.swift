import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import RatingCore

final class RatingCoreTests: XCTestCase {
    func testRatingRoundTripPreservesPixelsAndExistingMetadata() throws {
        let original = try fixture()
        let rated = try PhotoMetadata.settingRating(5, in: original)
        XCTAssertEqual(try PhotoMetadata.read(rated).rating, 5)
        XCTAssertEqual(try pixels(original), try pixels(rated))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(rated as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let iptc = try XCTUnwrap(properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any])
        // Image I/O canonicalizes TIFF Artist to IPTC Byline when making a JPEG.
        XCTAssertEqual(iptc[kCGImagePropertyIPTCByline as String] as? [String], ["Lichtblick Test"])
        XCTAssertEqual(iptc[kCGImagePropertyIPTCKeywords as String] as? [String], ["Berge", "Test"])
        let cleared = try PhotoMetadata.settingRating(0, in: rated)
        XCTAssertEqual(try PhotoMetadata.read(cleared).rating, 0)
        XCTAssertEqual(try pixels(original), try pixels(cleared))
    }

    func testAllStarsAndRepeatedUpdates() throws {
        var data = try fixture()
        for value in [1, 2, 3, 4, 5, 0, 2] {
            data = try PhotoMetadata.settingRating(value, in: data)
            XCTAssertEqual(try PhotoMetadata.read(data).rating, value)
        }
    }

    func testInvalidInputsAreRejected() throws {
        XCTAssertThrowsError(try PhotoMetadata.read(Data("invalid".utf8)))
        XCTAssertThrowsError(try PhotoMetadata.settingRating(6, in: fixture()))
        XCTAssertThrowsError(try PhotoMetadata.settingRating(-1, in: fixture()))
    }

    func testLosslessRoundTripForSupportedFormats() throws {
        for type in [UTType.jpeg, .png, .tiff, .heic] {
            let data = try fixture(type: type)
            let rated = try PhotoMetadata.settingRating(3, in: data)
            XCTAssertEqual(try PhotoMetadata.read(rated).rating, 3, type.identifier)
            XCTAssertEqual(try pixels(data), try pixels(rated), type.identifier)
        }
    }

    func testSuccessfulRemoteSaveCleansTemporaryFiles() async throws {
        let data = try fixture()
        let store = MemoryStore(files: ["/image.jpg": data])
        let result = try await SafeRatingWriter(store: store).save(rating: 4, path: "/image.jpg", expected: data)
        XCTAssertEqual(try PhotoMetadata.read(result.data).rating, 4)
        let files = await store.snapshot()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files["/image.jpg"], result.data)
        XCTAssertNil(result.retainedBackup)
    }

    func testConflictDoesNotOverwriteOriginal() async throws {
        let original = try fixture()
        let changed = try PhotoMetadata.settingRating(2, in: original)
        let store = MemoryStore(files: ["/image.jpg": changed])
        do {
            _ = try await SafeRatingWriter(store: store).save(rating: 5, path: "/image.jpg", expected: original)
            XCTFail("Expected conflict")
        } catch RatingError.conflict {} catch { XCTFail("Unexpected: \(error)") }
        let files = await store.snapshot()
        XCTAssertEqual(files, ["/image.jpg": changed])
    }

    func testFailedUploadNeverTouchesOriginal() async throws {
        let data = try fixture()
        let store = MemoryStore(files: ["/image.jpg": data], failure: .upload)
        do {
            _ = try await SafeRatingWriter(store: store).save(rating: 5, path: "/image.jpg", expected: data)
            XCTFail("Expected failure")
        } catch {}
        let files = await store.snapshot()
        XCTAssertEqual(files, ["/image.jpg": data])
    }

    func testCorruptUploadNeverTouchesOriginal() async throws {
        let data = try fixture()
        let store = MemoryStore(files: ["/image.jpg": data], failure: .corrupt)
        do {
            _ = try await SafeRatingWriter(store: store).save(rating: 5, path: "/image.jpg", expected: data)
            XCTFail("Expected failure")
        } catch RatingError.verification {} catch { XCTFail("Unexpected: \(error)") }
        let files = await store.snapshot()
        XCTAssertEqual(files, ["/image.jpg": data])
    }

    func testFailedReplacementRestoresOriginal() async throws {
        let data = try fixture()
        let store = MemoryStore(files: ["/image.jpg": data], failure: .replace)
        do {
            _ = try await SafeRatingWriter(store: store).save(rating: 5, path: "/image.jpg", expected: data)
            XCTFail("Expected failure")
        } catch {}
        let files = await store.snapshot()
        XCTAssertEqual(files, ["/image.jpg": data])
    }

    func testFailedCleanupReportsRetainedBackup() async throws {
        let data = try fixture()
        let store = MemoryStore(files: ["/image.jpg": data], failure: .cleanup)
        let result = try await SafeRatingWriter(store: store).save(rating: 5, path: "/image.jpg", expected: data)
        XCTAssertNotNil(result.retainedBackup)
        let files = await store.snapshot()
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[result.retainedBackup!], data)
        XCTAssertEqual(try PhotoMetadata.read(try XCTUnwrap(files["/image.jpg"])).rating, 5)
    }

    func testDeniedBackupRenameCleansUpload() async throws {
        let data = try fixture()
        let store = MemoryStore(files: ["/image.jpg": data], failure: .backup)
        do {
            _ = try await SafeRatingWriter(store: store).save(rating: 5, path: "/image.jpg", expected: data)
            XCTFail("Expected failure")
        } catch {}
        let files = await store.snapshot()
        XCTAssertEqual(files, ["/image.jpg": data])
    }

    func testChangeDuringUploadIsNotOverwritten() async throws {
        let data = try fixture()
        let store = MemoryStore(files: ["/image.jpg": data], failure: .concurrentEdit)
        do {
            _ = try await SafeRatingWriter(store: store).save(rating: 5, path: "/image.jpg", expected: data)
            XCTFail("Expected conflict")
        } catch RatingError.conflict {} catch { XCTFail("Unexpected: \(error)") }
        let files = await store.snapshot()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try PhotoMetadata.read(try XCTUnwrap(files["/image.jpg"])).rating, 2)
    }

    func testLostBackupRenameResponseKeepsRecoverableOriginal() async throws {
        let data = try fixture()
        let store = MemoryStore(files: ["/image.jpg": data], failure: .ambiguousBackup)
        do {
            _ = try await SafeRatingWriter(store: store).save(rating: 5, path: "/image.jpg", expected: data)
            XCTFail("Expected recovery warning")
        } catch RatingError.recovery(let path) {
            let files = await store.snapshot()
            XCTAssertEqual(files[path], data)
        } catch { XCTFail("Unexpected: \(error)") }
    }

    func testLostReplacementResponseKeepsBothVersions() async throws {
        let data = try fixture()
        let store = MemoryStore(files: ["/image.jpg": data], failure: .ambiguousReplace)
        do {
            _ = try await SafeRatingWriter(store: store).save(rating: 5, path: "/image.jpg", expected: data)
            XCTFail("Expected recovery warning")
        } catch RatingError.recovery(let path) {
            let files = await store.snapshot()
            XCTAssertEqual(files[path], data)
            XCTAssertEqual(try PhotoMetadata.read(try XCTUnwrap(files["/image.jpg"])).rating, 5)
        } catch { XCTFail("Unexpected: \(error)") }
    }

    private func fixture(type: UTType = .jpeg) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8,
            bytesPerRow: 96, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: "Lichtblick Test"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCKeywords: ["Berge", "Test"]]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func pixels(_ data: Data) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try XCTUnwrap(image.dataProvider?.data) as Data
    }
}

private actor MemoryStore: RemoteFileStore {
    enum Failure { case upload, corrupt, replace, cleanup, backup, concurrentEdit, ambiguousBackup, ambiguousReplace }
    var files: [String: Data]
    let failure: Failure?
    init(files: [String: Data], failure: Failure? = nil) { self.files = files; self.failure = failure }
    func snapshot() -> [String: Data] { files }
    func read(_ path: String) async throws -> Data {
        guard let data = files[path] else { throw POSIXError(.ENOENT) }; return data
    }
    func write(_ data: Data, to path: String) async throws {
        files[path] = failure == .corrupt ? Data("corrupt".utf8) : data
        if failure == .upload { throw POSIXError(.EIO) }
        if failure == .concurrentEdit, let old = files["/image.jpg"] {
            files["/image.jpg"] = try PhotoMetadata.settingRating(2, in: old)
        }
    }
    func move(_ source: String, to destination: String) async throws {
        if failure == .replace && source.hasSuffix(".tmp") { throw POSIXError(.EACCES) }
        if failure == .backup && destination.hasSuffix(".backup") { throw POSIXError(.EACCES) }
        guard files[destination] == nil else { throw POSIXError(.EEXIST) }
        guard let value = files.removeValue(forKey: source) else { throw POSIXError(.ENOENT) }
        files[destination] = value
        if failure == .ambiguousBackup && destination.hasSuffix(".backup") { throw POSIXError(.EIO) }
        if failure == .ambiguousReplace && source.hasSuffix(".tmp") { throw POSIXError(.EIO) }
    }
    func remove(_ path: String) async throws {
        if failure == .cleanup && path.hasSuffix(".backup") { throw POSIXError(.EACCES) }
        files.removeValue(forKey: path)
    }
}
