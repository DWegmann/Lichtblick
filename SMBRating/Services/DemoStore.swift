import UIKit

actor DemoStore: PhotoStore {
    private var files: [String: Data]
    init(files: [String: Data]) { self.files = files }
    func list(_ path: String) async throws -> [RemoteEntry] {
        let prefix = path == "/" ? "/" : path + "/"
        var entries: [String: RemoteEntry] = [:]
        for (file, data) in files where file.hasPrefix(prefix) && !file.contains(".smbrating-") {
            let relative = String(file.dropFirst(prefix.count))
            guard let name = relative.split(separator: "/").first.map(String.init) else { continue }
            let directory = relative.contains("/")
            let entryPath = prefix + name
            entries[entryPath] = RemoteEntry(path: entryPath, name: name, isDirectory: directory,
                size: directory ? 0 : Int64(data.count))
        }
        return Array(entries.values)
    }
    func read(_ path: String) async throws -> Data {
        guard let data = files[path] else { throw POSIXError(.ENOENT) }
        return data
    }
    func write(_ data: Data, to path: String) async throws { files[path] = data }
    func move(_ source: String, to destination: String) async throws {
        guard files[destination] == nil else { throw POSIXError(.EEXIST) }
        guard let data = files.removeValue(forKey: source) else { throw POSIXError(.ENOENT) }
        files[destination] = data
    }
    func remove(_ path: String) async throws {
        guard files.removeValue(forKey: path) != nil else { throw POSIXError(.ENOENT) }
    }
    func disconnect() async {}

    @MainActor static func make() -> DemoStore {
        let names = ["Morgenlicht", "Blaue Stunde", "Dünen", "Abendrot", "Nordküste", "Stille", "Alpenglühen", "Weite", "Goldener Herbst"]
        let palettes: [(UIColor, UIColor)] = [
            (.init(red: 0.83, green: 0.72, blue: 0.57, alpha: 1), .init(red: 0.16, green: 0.32, blue: 0.34, alpha: 1)),
            (.init(red: 0.34, green: 0.48, blue: 0.68, alpha: 1), .init(red: 0.10, green: 0.20, blue: 0.33, alpha: 1)),
            (.init(red: 0.91, green: 0.79, blue: 0.61, alpha: 1), .init(red: 0.55, green: 0.36, blue: 0.23, alpha: 1))
        ]
        var files: [String: Data] = [:]
        for (index, name) in names.enumerated() {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1100), format: format).image { renderer in
                let ctx = renderer.cgContext
                let palette = palettes[index % palettes.count]
                ctx.setFillColor(palette.0.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 1100))
                ctx.setFillColor(UIColor.white.withAlphaComponent(0.65).cgColor)
                ctx.fillEllipse(in: CGRect(x: 1050 - index * 45, y: 150 + index * 10, width: 140, height: 140))
                for layer in 0..<4 {
                    ctx.setFillColor(palette.1.withAlphaComponent(0.3 + Double(layer) * 0.2).cgColor)
                    ctx.move(to: CGPoint(x: 0, y: 550 + layer * 125))
                    for step in 0...12 {
                        let x = CGFloat(step) * 160
                        let y = CGFloat(520 + layer * 140) + sin(Double(step + index + layer) * 0.9) * CGFloat(130 - layer * 20)
                        ctx.addLine(to: CGPoint(x: x, y: y))
                    }
                    ctx.addLine(to: CGPoint(x: 1600, y: 1100)); ctx.addLine(to: CGPoint(x: 0, y: 1100))
                    ctx.closePath(); ctx.fillPath()
                }
            }
            if let data = image.jpegData(compressionQuality: 0.92) {
                let directory = index < 3 ? "/" : (index < 6 ? "/Landschaften/" : "/Landschaften/Auswahl/")
                files["\(directory)\(String(format: "%02d", index + 1))_\(name).jpg"] = (try? PhotoMetadata.settingRating(index % 6, in: data)) ?? data
            }
        }
        return DemoStore(files: files)
    }
}
