import SwiftUI

struct PhotoViewer: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [RemoteEntry]
    @State private var index: Int
    @State private var photo: LoadedPhoto?
    @State private var original: Data?
    @State private var rating = 0
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var status: String?
    @State private var retry = 0
    @State private var showInfo = false
    @State private var deletionRequest: FileDeletionRequest?
    @State private var moveRequest: FileMoveRequest?
    @State private var movedPath: String?
    @State private var errorTitle = "Bewertung nicht gespeichert"

    init(entries: [RemoteEntry], initialIndex: Int) {
        _entries = State(initialValue: entries)
        _index = State(initialValue: initialIndex)
    }
    private var entry: RemoteEntry { entries[min(index, entries.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Button { dismiss() } label: { Label("Übersicht", systemImage: "square.grid.2x2") }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                VStack(spacing: 4) {
                    Text(entry.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text("\(index + 1) von \(entries.count)").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("Bildinformationen")
                Button { moveRequest = library.moveRequest(for: entry) } label: {
                    Image(systemName: "folder").frame(width: 44, height: 44)
                }.accessibilityLabel("Datei verschieben")
                    .disabled(entry.isSymbolicLink)
                Button(role: .destructive) { deletionRequest = library.deletionRequest(for: entry) } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }.accessibilityLabel("Datei löschen")
            }.padding(.horizontal, 24).padding(.vertical, 18).disabled(library.isBusy)
            ZStack {
                Color.black
                if let photo {
                    ZoomablePhoto(image: photo.image, onSwipe: navigate)
                        .id(entry.path)
                        .accessibilityLabel(entry.name)
                        .allowsHitTesting(!library.isBusy)
                } else if let loadError {
                    VStack(spacing: 18) {
                        Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                        Text(loadError).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Erneut laden") { retry += 1 }
                    }.padding(40)
                } else { ProgressView("Bild wird geladen …") }
                if showInfo, let photo {
                    VStack {
                        HStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 10) {
                                Text(entry.name).font(.headline)
                                Text("\(photo.metadata.width) × \(photo.metadata.height) Pixel")
                                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                                Text("Bewertung: \(photo.metadata.origin)")
                                Text(photo.metadata.canWrite ? "Speichern: eingebettetes XMP" : "Nur ansehen")
                            }.font(.caption).padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        Spacer()
                    }.padding(24).allowsHitTesting(false)
                }
            }
            HStack(spacing: 20) {
                Button { navigate(-1) } label: { Image(systemName: "chevron.left").font(.title3).frame(width: 44, height: 44) }
                    .disabled(index == 0 || library.isBusy).keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityLabel("Vorheriges Bild")
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { value in
                            Button { save(value) } label: {
                                Image(systemName: value <= rating ? "star.fill" : "star")
                                    .font(.system(size: 27, weight: .light)).foregroundStyle(Theme.accent)
                                    .frame(width: 44, height: 44)
                            }
                            .keyboardShortcut(KeyEquivalent(Character(String(value))), modifiers: [])
                            .accessibilityLabel("\(value) Sterne vergeben")
                            .disabled(original == nil || library.isBusy || photo?.metadata.canWrite != true)
                        }
                        Button { save(0) } label: { Image(systemName: "xmark.circle").frame(width: 44, height: 44) }
                            .foregroundStyle(Theme.muted).keyboardShortcut("0", modifiers: [])
                            .accessibilityLabel("Bewertung entfernen")
                            .disabled(original == nil || library.isBusy || photo?.metadata.canWrite != true)
                    }
                    HStack(spacing: 8) {
                        if library.isBusy { ProgressView().controlSize(.small) }
                        Text(footer).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Button { navigate(1) } label: { Image(systemName: "chevron.right").font(.title3).frame(width: 44, height: 44) }
                    .disabled(index == entries.count - 1 || library.isBusy).keyboardShortcut(.rightArrow, modifiers: [])
                    .accessibilityLabel("Nächstes Bild")
            }.padding(.horizontal, 20).padding(.vertical, 18)
        }
        .background(Theme.background).foregroundStyle(.white)
        .interactiveDismissDisabled(library.isBusy)
        .task(id: "\(entry.path)-\(retry)") { await load() }
        .alert(errorTitle, isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
            Button("Bild neu laden") { retry += 1 }
        } message: { Text(saveError ?? "") }
        .fileDeletionConfirmation($deletionRequest, onConfirm: delete)
        .sheet(item: $moveRequest, onDismiss: {
            if let movedPath {
                self.movedPath = nil
                removeFromViewer(movedPath)
            }
        }) { request in
            FileMoveView(request: request) { movedPath = request.entry.path }.environmentObject(library)
        }
    }

    private var footer: String {
        if library.isDeleting { return "Datei wird gelöscht …" }
        if library.isMoving { return "Datei wird verschoben …" }
        if library.isSaving { return "Bewertung wird gespeichert und geprüft …" }
        if let status { return status }
        if photo?.metadata.canWrite == false { return "Dieses Bild kann nur angesehen werden." }
        if rating == -1 { return "Als abgelehnt markiert · Mit Sternen neu bewerten" }
        return "\(rating == 0 ? "Ohne Bewertung" : "\(rating) Sterne") · \(library.isDemo ? "Demo" : "Eingebettetes XMP") · Doppeltippen zum Zoomen"
    }

    private func navigate(_ delta: Int) {
        guard !library.isBusy, deletionRequest == nil, moveRequest == nil, entries.indices.contains(index + delta) else { return }
        photo = nil; original = nil; status = nil; loadError = nil
        index += delta
    }

    private func load() async {
        let requestedPath = entry.path
        photo = nil; original = nil; loadError = nil; status = nil
        guard let pipeline = library.pipeline else { return }
        do {
            let (loaded, data) = try await pipeline.detail(entry)
            try Task.checkCancellation()
            guard entry.path == requestedPath else { return }
            photo = loaded; original = data; rating = loaded.metadata.rating
            library.ratings[requestedPath] = rating
        } catch is CancellationError {} catch {
            guard entry.path == requestedPath else { return }
            loadError = error.localizedDescription
        }
    }

    private func save(_ value: Int) {
        guard let original, !library.isBusy, deletionRequest == nil, moveRequest == nil else { return }
        errorTitle = "Bewertung nicht gespeichert"
        let currentEntry = entry
        Task {
            do {
                let result = try await library.save(rating: value, entry: currentEntry, expected: original)
                self.original = result.data
                rating = value
                if let photo {
                    self.photo = LoadedPhoto(image: photo.image, metadata: try PhotoMetadata.read(result.data))
                }
                status = result.retainedBackup.map { "Gespeichert. Sicherung nicht gelöscht: \($0)" }
                    ?? (library.isDemo ? "In der Demobibliothek gespeichert" : "Auf dem SMB-Server gespeichert und geprüft")
            } catch { saveError = error.localizedDescription }
        }
    }

    private func delete(_ request: FileDeletionRequest) {
        Task {
            do {
                try await library.deleteFile(request)
                removeFromViewer(request.entry.path)
            } catch {
                errorTitle = "Löschen nicht bestätigt"
                saveError = "\(error.localizedDescription)\nBitte die Übersicht neu laden, um den aktuellen Stand zu prüfen."
            }
        }
    }

    private func removeFromViewer(_ path: String) {
        let remaining = entries.filter { $0.path != path }
        guard !remaining.isEmpty else { dismiss(); return }
        photo = nil; original = nil; status = nil; loadError = nil
        index = min(index, remaining.count - 1)
        entries = remaining
    }
}

struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    let onSwipe: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PhotoScrollView {
        let view = PhotoScrollView()
        view.delegate = context.coordinator
        view.minimumZoomScale = 1; view.maximumZoomScale = 5
        view.showsHorizontalScrollIndicator = false; view.showsVerticalScrollIndicator = false
        view.imageView.contentMode = .scaleAspectFit
        view.addSubview(view.imageView)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2; view.addGestureRecognizer(tap)
        let left = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipe(_:)))
        left.direction = .left; left.delegate = context.coordinator; view.addGestureRecognizer(left)
        let right = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipe(_:)))
        right.direction = .right; right.delegate = context.coordinator; view.addGestureRecognizer(right)
        view.panGestureRecognizer.require(toFail: left)
        view.panGestureRecognizer.require(toFail: right)
        return view
    }
    func updateUIView(_ view: PhotoScrollView, context: Context) {
        view.imageView.image = image
        context.coordinator.onSwipe = onSwipe
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var onSwipe: ((Int) -> Void)?
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            ((gestureRecognizer.view as? UIScrollView)?.zoomScale ?? 1) <= 1.01
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { (scrollView as? PhotoScrollView)?.imageView }
        @objc func doubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scroll = recognizer.view as? PhotoScrollView else { return }
            if scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: true) }
            else {
                let point = recognizer.location(in: scroll.imageView)
                let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
        @objc func swipe(_ recognizer: UISwipeGestureRecognizer) { onSwipe?(recognizer.direction == .left ? 1 : -1) }
    }
}

final class PhotoScrollView: UIScrollView {
    let imageView = UIImageView()
    private var previousSize: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != previousSize {
            previousSize = bounds.size
            zoomScale = 1
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }
}
