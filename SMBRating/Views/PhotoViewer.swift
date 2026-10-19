import SwiftUI

struct PhotoViewer: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entries: [RemoteEntry]
    @State private var index: Int
    @State private var photo: LoadedPhoto?
    @State private var previewImage: UIImage?
    @State private var adjacentPreviews: [String: UIImage] = [:]
    @State private var movingForward = true
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
                Button(action: returnToOverview) { Label("Übersicht", systemImage: "square.grid.2x2") }
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
                ViewerImagePage(image: photo?.image ?? previewImage, name: entry.name,
                    path: entry.path, movingForward: movingForward, reduceMotion: reduceMotion,
                    error: loadError, isBusy: library.isBusy, onSwipe: navigate,
                    onDismiss: returnToOverview, onRetry: { retry += 1 })
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
            }.clipped()
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
        .task(id: entry.path) { await prepareAdjacentPreviews() }
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
        if original == nil {
            return loadError == nil ? "Bild und Bewertung werden geladen …" : "Bild konnte nicht geladen werden."
        }
        if photo?.metadata.canWrite == false { return "Dieses Bild kann nur angesehen werden." }
        if rating == -1 { return "Als abgelehnt markiert · Mit Sternen neu bewerten" }
        return "\(rating == 0 ? "Ohne Bewertung" : "\(rating) Sterne") · \(library.isDemo ? "Demo" : "Eingebettetes XMP") · Doppeltippen zum Zoomen"
    }

    private func returnToOverview() {
        guard !library.isBusy, deletionRequest == nil, moveRequest == nil else { return }
        dismiss()
    }

    private func navigate(_ delta: Int) {
        guard !library.isBusy, deletionRequest == nil, moveRequest == nil, entries.indices.contains(index + delta) else { return }
        movingForward = delta > 0
        previewImage = adjacentPreviews[entries[index + delta].path]
        photo = nil; original = nil; status = nil; loadError = nil; rating = 0
        index += delta
    }

    private func prepareAdjacentPreviews() async {
        guard let pipeline = library.pipeline else { return }
        let requestedPath = entry.path
        let neighbours = [index - 1, index + 1].filter { entries.indices.contains($0) }.map { entries[$0] }
        let paths = Set(neighbours.map(\.path))
        adjacentPreviews = adjacentPreviews.filter { paths.contains($0.key) }
        await withTaskGroup(of: (String, UIImage?).self) { group in
            for neighbour in neighbours {
                group.addTask { (neighbour.path, try? await pipeline.thumbnail(neighbour)) }
            }
            for await (path, image) in group {
                guard !Task.isCancelled, entry.path == requestedPath, let image else { continue }
                adjacentPreviews[path] = image
            }
        }
    }

    private func load() async {
        let requestedPath = entry.path
        photo = nil; original = nil; loadError = nil; status = nil; rating = 0
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
        previewImage = adjacentPreviews[remaining[min(index, remaining.count - 1)].path]
        photo = nil; original = nil; status = nil; loadError = nil; rating = 0
        index = min(index, remaining.count - 1)
        entries = remaining
    }
}

/// Keep the native viewport alive across page changes so it can retain and
/// animate the outgoing pixels even after the loading state has been cleared.
private struct ViewerImagePage: View {
    let image: UIImage?
    let name: String
    let path: String
    let movingForward: Bool
    let reduceMotion: Bool
    let error: String?
    let isBusy: Bool
    let onSwipe: (Int) -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            ZoomablePhoto(image: image, path: path, movingForward: movingForward,
                reduceMotion: reduceMotion, onSwipe: onSwipe, onDismiss: onDismiss)
                .accessibilityLabel(name)
                .allowsHitTesting(!isBusy)
            if let error {
                VStack(spacing: 18) {
                    Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                    Text(error).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Erneut laden", action: onRetry)
                }.padding(40).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if image == nil {
                ProgressView("Bild wird geladen …")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage?
    let path: String
    let movingForward: Bool
    let reduceMotion: Bool
    let onSwipe: (Int) -> Void
    let onDismiss: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PhotoPagerView {
        let pager = PhotoPagerView()
        let view = pager.scrollView
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
        let down = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swipeDown(_:)))
        down.direction = .down; down.delegate = context.coordinator; view.addGestureRecognizer(down)
        view.panGestureRecognizer.require(toFail: left)
        view.panGestureRecognizer.require(toFail: right)
        view.panGestureRecognizer.require(toFail: down)
        return pager
    }
    func updateUIView(_ view: PhotoPagerView, context: Context) {
        context.coordinator.onSwipe = onSwipe
        context.coordinator.onDismiss = onDismiss
        view.show(image: image, path: path, movingForward: movingForward, reduceMotion: reduceMotion)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var onSwipe: ((Int) -> Void)?
        var onDismiss: (() -> Void)?
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
        @objc func swipeDown(_ recognizer: UISwipeGestureRecognizer) { onDismiss?() }
    }
}

/// The outgoing snapshot is independent of the next page's thumbnail, loading
/// state, and zoom view. Both pages travel a full viewport width without fading.
final class PhotoPagerView: UIView {
    let scrollView = PhotoScrollView()
    private var displayedPath: String?
    private var outgoingView: UIView?
    private var animationID = UUID()
    private var previousSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != previousSize else { return }
        previousSize = bounds.size
        finishTransition()
        scrollView.frame = bounds
    }

    func show(image: UIImage?, path: String, movingForward: Bool, reduceMotion: Bool) {
        let changesPage = displayedPath != nil && displayedPath != path
        if changesPage { finishTransition() }
        let outgoing = changesPage && window != nil && bounds.width > 0
            ? captureOutgoingView() : nil
        displayedPath = path
        if changesPage { scrollView.setZoomScale(1, animated: false) }
        scrollView.imageView.image = image
        guard let outgoing else { return }

        let id = UUID()
        animationID = id
        outgoingView = outgoing
        outgoing.frame = bounds
        outgoing.isUserInteractionEnabled = false
        outgoing.accessibilityElementsHidden = true
        addSubview(outgoing)
        let distance = bounds.width * (movingForward ? 1 : -1)
        scrollView.transform = reduceMotion ? .identity : CGAffineTransform(translationX: distance, y: 0)
        scrollView.alpha = reduceMotion ? 0 : 1
        UIView.animate(withDuration: reduceMotion ? 0.15 : 0.34, delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction], animations: {
                self.scrollView.transform = .identity
                self.scrollView.alpha = 1
                if reduceMotion { outgoing.alpha = 0 }
                else { outgoing.transform = CGAffineTransform(translationX: -distance, y: 0) }
            }, completion: { [weak self] _ in
                guard let self, self.animationID == id else { return }
                self.finishTransition()
            })
    }

    private func captureOutgoingView() -> UIView? {
        guard let image = scrollView.imageView.image else { return nil }
        if let snapshot = scrollView.snapshotView(afterScreenUpdates: false) { return snapshot }
        // Retain the actual image even when UIKit cannot produce a snapshot.
        let fallback = UIImageView(image: image)
        fallback.contentMode = .scaleAspectFit
        return fallback
    }

    private func finishTransition() {
        // Invalidate completion handlers before removing animations, including
        // during rapid navigation or a rotation halfway through a transition.
        animationID = UUID()
        scrollView.layer.removeAllAnimations()
        scrollView.transform = .identity
        scrollView.alpha = 1
        outgoingView?.layer.removeAllAnimations()
        outgoingView?.removeFromSuperview()
        outgoingView = nil
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
