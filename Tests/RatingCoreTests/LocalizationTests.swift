import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SMBRating/Resources")
    }

    private func bundle(_ language: String) throws -> Bundle {
        try XCTUnwrap(Bundle(url: resources.appendingPathComponent("\(language).lproj")))
    }

    private func strings(_ language: String, table: String = "Localizable") throws -> [String: String] {
        let data = try Data(contentsOf: resources.appendingPathComponent("\(language).lproj/\(table).strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    func testBothLanguagesHaveCompleteTranslationsAndMatchingArguments() throws {
        let german = try strings("de")
        let english = try strings("en")
        XCTAssertGreaterThan(english.count, 150)
        XCTAssertEqual(Set(german.keys), Set(english.keys))
        for (key, translation) in english {
            XCTAssertFalse(translation.isEmpty, key)
            XCTAssertEqual(key.components(separatedBy: "%@").count,
                           translation.components(separatedBy: "%@").count, key)
        }
    }

    func testEnglishAndGermanLabelsAndInterpolatedProgress() throws {
        let en = try bundle("en")
        let de = try bundle("de")
        XCTAssertEqual(String(localized: "Demobibliothek", bundle: en), "Demo library")
        XCTAssertEqual(String(localized: "Demobibliothek", bundle: de), "Demobibliothek")
        let current = "2", total = "9"
        XCTAssertEqual(String(localized: "\(current) von \(total)", bundle: en), "2 of 9")
        XCTAssertEqual(String(localized: "\(current) von \(total)", bundle: de), "2 von 9")
        XCTAssertEqual(String(localized: "\(current) / \(total) Bewertungen geprüft", bundle: en),
                       "2 / 9 ratings checked")
        XCTAssertEqual(String(localized: "1 Stern", bundle: en), "1 star")
        XCTAssertEqual(String(localized: "\(current) Sterne", bundle: en), "2 stars")
    }

    func testDeletionWarningKeepsFilenameServerAndPath() throws {
        let name = "Photo.jpg", server = "nas.local/Photos", path = "/Holiday/Photo.jpg"
        let text = String(localized: "„\(name)“ wird dauerhaft von \(server) gelöscht.\n\nPfad: \(path)\n\nDies kann in der App nicht rückgängig gemacht werden.", bundle: try bundle("en"))
        XCTAssertEqual(text, "“Photo.jpg” will be permanently deleted from nas.local/Photos.\n\nPath: /Holiday/Photo.jpg\n\nThis cannot be undone in the app.")
    }

    func testLocalNetworkPermissionExplainsAccessInBothLanguages() throws {
        XCTAssertEqual(try strings("en", table: "InfoPlist")["NSLocalNetworkUsageDescription"],
                       "Lichtblick connects to your SMB server to read and save photos and ratings.")
        XCTAssertEqual(try strings("de", table: "InfoPlist")["NSLocalNetworkUsageDescription"],
                       "Lichtblick verbindet sich mit deinem SMB-Server, um Bilder und Bewertungen zu lesen und zu speichern.")
    }
}
