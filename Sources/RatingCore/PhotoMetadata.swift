import Foundation
import ImageIO

public struct PhotoMetadata: Sendable, Equatable {
    public let rating: Int
    public let origin: String
    public let width: Int
    public let height: Int
    public let canWrite: Bool

    public static func read(_ data: Data) throws -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { throw RatingError.invalidImage }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        let xmp = metadata.flatMap {
            CGImageMetadataCopyStringValueWithPath($0, nil, "xmp:Rating" as CFString) as String?
        }.flatMap(Int.init)
        let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
        let legacy = (iptc?[kCGImagePropertyIPTCStarRating as String] as? NSNumber)?.intValue
            ?? (iptc?[kCGImagePropertyIPTCStarRating as String] as? String).flatMap(Int.init)
        let rating = [xmp, legacy].compactMap { $0 }.first(where: { (-1...5).contains($0) })
        return PhotoMetadata(
            rating: rating ?? 0,
            origin: xmp != nil ? "XMP" : (legacy != nil ? "IPTC" : String(localized: "Ohne Bewertung")),
            width: properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0,
            height: properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0,
            canWrite: writableTypes.contains(type as String) && CGImageSourceGetCount(source) == 1
        )
    }

    // RAW, animations, and multi-page images remain view-only.
    private static let writableTypes: Set<String> = ["public.jpeg", "public.tiff", "public.png", "public.heic", "public.heif"]

    public static func settingRating(_ rating: Int, in data: Data) throws -> Data {
        guard (0...5).contains(rating) else { throw RatingError.invalidRating }
        guard try read(data).canWrite,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { throw RatingError.unsupportedWrite }
        let metadata = CGImageMetadataCreateMutable()
        var namespaceError: Unmanaged<CFError>?
        guard CGImageMetadataRegisterNamespaceForPrefix(metadata,
            "http://ns.adobe.com/xap/1.0/" as CFString, "xmp" as CFString, &namespaceError),
              CGImageMetadataSetValueWithPath(metadata, nil, "xmp:Rating" as CFString, String(rating) as CFString)
        else { throw RatingError.metadataWrite }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, CGImageSourceGetCount(source), nil)
        else { throw RatingError.unsupportedWrite }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: metadata,
            kCGImageDestinationMergeMetadata: true
        ]
        var error: Unmanaged<CFError>?
        // This copies compressed image data. Never fall back to re-encoding pixels.
        guard CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) else {
            if let error { throw error.takeRetainedValue() as Error }
            throw RatingError.unsupportedWrite
        }
        let result = output as Data
        guard try read(result).rating == rating else { throw RatingError.verification }
        return result
    }
}

public enum RatingError: LocalizedError {
    case invalidImage, invalidRating, unsupportedWrite, metadataWrite, verification, conflict, busy, tooLarge
    case recovery(String)

    public var errorDescription: String? {
        switch self {
        case .invalidImage: return String(localized: "Die Bilddatei kann nicht gelesen werden.")
        case .invalidRating: return String(localized: "Eine Bewertung muss zwischen 0 und 5 Sternen liegen.")
        case .unsupportedWrite: return String(localized: "Dieses Format unterstützt hier keine verlustfreie Metadatenänderung. Es kann nur angesehen werden.")
        case .metadataWrite: return String(localized: "Die XMP-Bewertung konnte nicht erstellt werden.")
        case .verification: return String(localized: "Die gespeicherten Daten haben die Prüfung nicht bestanden.")
        case .conflict: return String(localized: "Die Datei wurde auf dem Server geändert. Bitte das Bild neu laden und erneut bewerten.")
        case .busy: return String(localized: "Ein Speichervorgang läuft bereits.")
        case .tooLarge: return String(localized: "Dieses Bild ist größer als 128 MB und kann auf dem iPad nicht geladen werden.")
        case .recovery(let path): return String(localized: "Der Speichervorgang wurde unterbrochen. Bitte die Originaldatei und die mögliche Sicherungsdatei \(String(path)) auf dem Server prüfen, bevor du erneut speicherst.")
        }
    }
}
