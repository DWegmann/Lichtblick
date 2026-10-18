import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var query = ""
    @AppStorage("library.tileSize") private var tileSize: Double = 210
    @AppStorage("library.sortDescending") private var sortDescending = false
    @AppStorage("library.showFullImage") private var showFullImage = false
    @AppStorage("library.photosExpanded") private var photosExpanded = true
    @State private var selection: ViewerSelection?
    @State private var showInfo = false
    @State private var deletionRequest: FileDeletionRequest?
    @State private var moveRequest: FileMoveRequest?
    @State private var visiblePhotos = Set<String>()

    private struct PrefetchRequest: Equatable {
        let revision: UUID
        let entries: [RemoteEntry]
    }

    private var prefetchRequest: PrefetchRequest {
        PrefetchRequest(revision: library.revision, entries: selection == nil && photosExpanded
            ? PreviewPrefetchWindow.entries(in: photos, visible: visiblePhotos) : [])
    }

    private var photos: [RemoteEntry] {
        let sorted = library.photos.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted {
                let order = $0.name.localizedStandardCompare($1.name)
                return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
            }
        return sortDescending ? Array(sorted.reversed()) : sorted
    }

    private var folders: [RemoteEntry] {
        let filtered = library.folders.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        return sortDescending ? Array(filtered.reversed()) : filtered
    }

    private var sidebarIsVisible: Bool {
        horizontalSizeClass == .compact ? compactColumn == .sidebar : columnVisibility != .detailOnly
    }

    private var sidebarToggle: some View {
        Button {
            let showSidebar = !sidebarIsVisible
            withAnimation {
                columnVisibility = showSidebar ? .all : .detailOnly
                compactColumn = showSidebar ? .sidebar : .detail
            }
        } label: {
            Label(sidebarIsVisible ? "Seitenleiste einklappen" : "Seitenleiste einblenden", systemImage: "sidebar.left")
        }
        .labelStyle(.iconOnly)
        .help(sidebarIsVisible ? "Seitenleiste einklappen" : "Seitenleiste einblenden")
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 12) {
                    Image(systemName: "viewfinder").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Lichtblick").font(.title2.bold())
                        Text("SMB PHOTO RATING").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Theme.muted)
                    }
                    if horizontalSizeClass == .compact {
                        Spacer(minLength: 0)
                        sidebarToggle
                    }
                }.padding(.top, 28)
                VStack(alignment: .leading, spacing: 14) {
                    Text("BIBLIOTHEK").font(.caption2.bold()).tracking(2).foregroundStyle(Theme.muted)
                    Label("Alle Bilder", systemImage: "square.grid.2x2.fill")
                        .foregroundStyle(Theme.accent).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                if library.connected {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("VERBINDUNG").font(.caption2.bold()).tracking(2).foregroundStyle(Theme.muted)
                        Label(library.isDemo ? "Demo · lokal" : library.settings.server, systemImage: library.isDemo ? "sparkles" : "server.rack")
                            .font(.subheadline).lineLimit(2)
                        HStack(spacing: 6) {
                            Circle().fill(Theme.accent).frame(width: 6, height: 6)
                            Text(library.isDemo ? "Zum Ausprobieren" : "Verbunden · \(library.settings.share)")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Button("Verbindung trennen", role: .destructive) { Task { await library.disconnect() } }
                            .font(.caption)
                    }
                }
                if !library.savedConnections.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("GESPEICHERTE VERBINDUNGEN").font(.caption2.bold()).tracking(1).foregroundStyle(Theme.muted)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(library.savedConnections) { profile in
                                    Button { Task { await library.reconnect(profile) } } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: library.activeConnectionID == profile.id ? "externaldrive.fill" : "externaldrive")
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(profile.settings.share).font(.subheadline.weight(.medium))
                                                Text(profile.settings.server).font(.caption).foregroundStyle(Theme.muted)
                                                Text(profile.lastPath).font(.caption2).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).disabled(library.isConnecting || library.isBusy)
                                }
                            }
                        }
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Button { library.prepareConnection() } label: { Label("SMB verbinden", systemImage: "plus.circle") }
                    Button { showInfo = true } label: { Label("Über Bewertungen", systemImage: "info.circle") }
                        .foregroundStyle(Theme.muted)
                }.font(.subheadline).padding(.bottom, 24)
            }
            .padding(.horizontal, 24).background(Theme.surface)
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 310)
            .toolbar(removing: .sidebarToggle)
            .toolbar(.hidden, for: .navigationBar)
        } detail: {
            NavigationStack {
                Group {
                    if library.connected { browser }
                    else { welcome }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
                .navigationTitle(library.connected ? library.locationName : "Dein nächster Lichtblick")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { sidebarToggle }
                    if library.connected {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button { Task { await library.loadFolder(library.path, refreshPreviews: true) } } label: { Image(systemName: "arrow.clockwise") }
                                .disabled(library.isLoading).accessibilityLabel("Ordner neu laden")
                            Menu {
                                Toggle("Unterordner einbeziehen", isOn: Binding(
                                    get: { library.includeSubfolders },
                                    set: { enabled in Task { await library.loadFolder(library.path, includingSubfolders: enabled) } }))
                                    .disabled(library.isLoading || library.isBusy || library.isConnecting)
                                Divider()
                                Picker("Sortierung", selection: $sortDescending) {
                                    Text("Dateiname aufsteigend").tag(false)
                                    Text("Dateiname absteigend").tag(true)
                                }
                                Divider()
                                Picker("Vorschaubilder", selection: $showFullImage) {
                                    Text("Ausschnitt anzeigen").tag(false)
                                    Text("Ganzes Bild anzeigen").tag(true)
                                }
                                Divider()
                                Picker("Vorschaugröße", selection: $tileSize) {
                                    Text("Kleine Vorschaubilder").tag(150.0)
                                    Text("Mittlere Vorschaubilder").tag(210.0)
                                    Text("Große Vorschaubilder").tag(290.0)
                                }
                            } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Ansicht anpassen")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $library.showConnection) { ConnectionView().environmentObject(library) }
        .fullScreenCover(item: $selection) { PhotoViewer(entries: $0.entries, initialIndex: $0.index).environmentObject(library) }
        .alert(library.error != nil ? "Hinweis" : "Verbindung hergestellt", isPresented: Binding(
            get: { !library.showConnection && (library.error != nil || library.credentialWarning != nil) },
            set: { if !$0 { library.error = nil; library.credentialWarning = nil } })) {
            Button("OK") { library.error = nil; library.credentialWarning = nil }
        } message: { Text(library.error ?? library.credentialWarning ?? "") }
        .sheet(isPresented: $showInfo) { metadataInfo }
        .sheet(item: $moveRequest) { FileMoveView(request: $0).environmentObject(library) }
        .fileDeletionConfirmation($deletionRequest) { request in
            Task {
                do { try await library.deleteFile(request) }
                catch { library.error = "Das Löschen konnte nicht bestätigt werden: \(error.localizedDescription)\nBitte den Ordner neu laden, um den aktuellen Stand zu prüfen." }
            }
        }
        .onChange(of: library.path) { _, _ in query = "" }
        .onChange(of: library.revision) { _, _ in visiblePhotos = [] }
        .task(id: prefetchRequest) {
            guard let pipeline = library.pipeline else { return }
            await pipeline.prefetch(prefetchRequest.entries)
        }
        .task { await library.restoreLastSession() }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.05)).frame(width: 190, height: 190)
                RoundedRectangle(cornerRadius: 28).stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                    .frame(width: 110, height: 130).rotationEffect(.degrees(-12))
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 62, weight: .ultraLight)).foregroundStyle(Theme.accent)
            }
            VStack(spacing: 12) {
                Text("Deine Bilder. Dein Blick.").font(.system(size: 34, weight: .semibold, design: .serif))
                Text("Fotos auf deinem Server entdecken,\nin Ruhe durchsehen und mit Sternen bewerten.")
                    .multilineTextAlignment(.center).foregroundStyle(Theme.muted).lineSpacing(5)
            }
            if library.isRestoring {
                ProgressView("Letzte Verbindung wird wiederhergestellt …").padding(.vertical, 10)
            }
            Button { library.prepareConnection() } label: {
                Label("Mit SMB-Server verbinden", systemImage: "externaldrive.connected.to.line.below")
                    .font(.headline).padding(.horizontal, 18).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent).foregroundStyle(Theme.background).padding(.top, 8)
            Button("Demobibliothek öffnen") { Task { await library.openDemo() } }.font(.subheadline)
            Text("Direkte Verbindung · Eingebettete XMP-Sterne · Kein Cloud-Konto")
                .font(.caption).foregroundStyle(Theme.muted).padding(.top, 16)
        }.padding(30)
    }

    private var browser: some View {
        VStack(spacing: 0) {
            HStack {
                if library.canGoUp {
                    Button { Task { await library.goUp() } } label: { Image(systemName: "arrow.up") }
                        .accessibilityLabel("Übergeordneter Ordner")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button { Task { await library.loadFolder("/") } } label: {
                            Label(library.isDemo ? "Demobibliothek" : library.settings.share, systemImage: "externaldrive")
                        }.disabled(library.isLoading || library.path == "/")
                        ForEach(Array(library.path.split(separator: "/").enumerated()), id: \.offset) { offset, component in
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                            Button(String(component)) {
                                let destination = "/" + library.path.split(separator: "/").prefix(offset + 1).joined(separator: "/")
                                Task { await library.loadFolder(destination) }
                            }.disabled(library.isLoading || offset == library.path.split(separator: "/").count - 1)
                        }
                    }.font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
                Spacer()
                if library.isDeleting { ProgressView("Datei wird gelöscht …").font(.caption) }
                else if library.isMoving { ProgressView("Datei wird verschoben …").font(.caption) }
                else { Text("\(photos.count) Bilder").font(.caption).foregroundStyle(Theme.muted) }
            }.padding(.horizontal, 28).padding(.vertical, 18)
            if library.isDemo {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Demo mit illustrativen Beispielbildern. Bewertungen gelten nur bis zum Schließen der Demo.")
                }.font(.caption).foregroundStyle(Theme.accent).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 16)
            }
            if library.includeSubfolders && !library.isLoading {
                Label("Bilder aus diesem Ordner und allen Unterordnern", systemImage: "folder.badge.plus")
                    .font(.caption).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 12)
            }
            if library.isLoading {
                Spacer()
                VStack(spacing: 18) {
                    ProgressView("Bilder werden gesucht …")
                    Button("Abbrechen") { library.cancelLoading() }
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        if !folders.isEmpty {
                            DisclosureGroup(isExpanded: $library.foldersExpanded) {
                                folderGrid.padding(.top, 12)
                            } label: {
                                browserSectionLabel("Ordner", systemImage: "folder", count: folders.count)
                            }
                        }
                        if !photos.isEmpty {
                            DisclosureGroup(isExpanded: $photosExpanded) {
                                photoGrid.padding(.top, 12)
                            } label: {
                                browserSectionLabel("Bilder", systemImage: "photo.on.rectangle", count: photos.count)
                            }
                        }
                    }.tint(Theme.accent).padding(28)
                    if photos.isEmpty && folders.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "Keine Bilder in diesem Ordner" : "Keine Treffer",
                            systemImage: query.isEmpty ? "photo.on.rectangle" : "magnifyingglass",
                            description: Text(query.isEmpty ? "Öffne einen anderen Ordner oder lade die Ansicht neu." : "Versuche einen anderen Dateinamen."))
                            .padding(.top, 70)
                    }
                }.id(library.revision)
            }
        }
        .searchable(text: $query, prompt: "Dateinamen suchen")
    }

    private func browserSectionLabel(_ title: String, systemImage: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: systemImage).font(.headline)
            Spacer()
            Text(count, format: .number).font(.subheadline).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(.primary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var folderGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize), spacing: 18, alignment: .top)], spacing: 24) {
            ForEach(folders) { folder in
                Button { Task { await library.loadFolder(folder.path) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill").font(.title2).foregroundStyle(Theme.accent)
                        Text(folder.name).lineLimit(2).font(.subheadline)
                        Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                    }.padding(20).frame(maxWidth: .infinity, minHeight: 82).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                    .accessibilityLabel("Ordner \(folder.name) öffnen")
            }
        }
    }

    private var photoGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize), spacing: 18, alignment: .top)], spacing: 24) {
            ForEach(photos) { entry in
                Button {
                    selection = ViewerSelection(entries: photos, index: photos.firstIndex(of: entry) ?? 0)
                } label: {
                    PhotoTile(entry: entry, showFullImage: showFullImage, onMove: {
                        moveRequest = library.moveRequest(for: entry)
                    }, onDelete: {
                        deletionRequest = library.deletionRequest(for: entry)
                    })
                }.buttonStyle(.plain).disabled(library.isBusy)
                    .onAppear { visiblePhotos.insert(entry.path) }
                    .onDisappear { visiblePhotos.remove(entry.path) }
            }
        }
    }

    private var metadataInfo: some View {
        NavigationStack {
            List {
                Section("Sterne direkt im Bild") {
                    Text("Lichtblick liest und schreibt xmp:Rating (0–5) im eingebetteten XMP-Paket. Vorhandene IPTC-StarRating-Werte werden als Fallback gelesen. XMP hat Vorrang. Eine vorhandene Ablehnungsmarkierung (−1) wird angezeigt und bleibt bis zur nächsten Bewertung erhalten.")
                    Text("JPEG, HEIC, PNG und einseitige TIFFs werden nur geändert, wenn Image I/O verlustfreies Kopieren mit Metadaten unterstützt. Andere Formate bleiben zum Ansehen verfügbar, soweit iPadOS sie decodieren kann. Es werden keine XMP-Sidecars angelegt.")
                }
                Section("Speichern auf SMB") {
                    Text("Die gesamte Datei wird geladen. Beim Speichern wird eine temporäre Datei hochgeladen und zurückgelesen. Erst nach erfolgreicher Prüfung wird das Original über eine Sicherungsdatei ersetzt. Bitte nicht gleichzeitig in anderen Programmen bearbeiten: SMB bietet hier keinen atomaren Vergleich mit anschließendem Ersetzen.")
                    Text("Dateien über 128 MB werden nicht geladen. Vorschaubilder entstehen lokal; das erste Öffnen großer Ordner kann deshalb dauern. Bei einem Verbindungsabbruch während des Ersetzens kann eine .smbrating-…backup-Datei eine manuelle Wiederherstellung erfordern.")
                }
                Section("Open Source") {
                    Link("AMSMB2 · LGPL 2.1", destination: URL(string: "https://github.com/amosavian/AMSMB2")!)
                    Link("libsmb2 · LGPL 2.1", destination: URL(string: "https://github.com/sahlberg/libsmb2")!)
                    NavigationLink("Lizenztexte anzeigen") {
                        ScrollView {
                            Text(licenseText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(24)
                        }.navigationTitle("Open-Source-Lizenzen")
                    }
                }
            }.navigationTitle("Über Bewertungen").toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showInfo = false } }
            }
        }
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "OpenSourceLicenses", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Die Lizenztexte sind im Quellprojekt unter Resources verfügbar." }
        return text
    }
}

struct ViewerSelection: Identifiable {
    let id = UUID()
    let entries: [RemoteEntry]
    let index: Int
}

struct PhotoTile: View {
    @EnvironmentObject private var library: LibraryModel
    let entry: RemoteEntry
    let showFullImage: Bool
    let onMove: () -> Void
    let onDelete: () -> Void
    @State private var photo: LoadedPhoto?
    @State private var previewImage: UIImage?
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Theme.surface)
                if let image = previewImage ?? photo?.image {
                    GeometryReader { geometry in
                        Image(uiImage: image).resizable()
                            .aspectRatio(contentMode: showFullImage ? .fit : .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }.clipShape(RoundedRectangle(cornerRadius: 12))
                } else if failure != nil {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.title2)
                        Text("Vorschau nicht verfügbar").font(.caption)
                    }.foregroundStyle(Theme.muted)
                } else { ProgressView() }
                if let photo, !photo.metadata.canWrite {
                    VStack { HStack { Spacer(); Image(systemName: "lock.fill").padding(8).background(.black.opacity(0.5), in: Circle()) }; Spacer() }.padding(8)
                }
            }.aspectRatio(1.25, contentMode: .fit)
            Text(entry.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
            if library.includeSubfolders {
                Text(entry.relativeFolder(to: library.path)).font(.caption2).foregroundStyle(Theme.muted)
                    .lineLimit(1).truncationMode(.middle)
            }
            HStack(spacing: 3) {
                let rating = library.ratings[entry.path] ?? photo?.metadata.rating
                if let rating {
                    ForEach(1...5, id: \.self) { value in
                        Image(systemName: value <= rating ? "star.fill" : "star")
                            .foregroundStyle(value <= rating ? Theme.accent : Theme.muted.opacity(0.4))
                    }
                } else {
                    Text(failure == nil ? "Bewertung wird geladen …" : "Bewertung nicht verfügbar")
                        .font(.caption2).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(rating == -1 ? "Abgelehnt" : (entry.name as NSString).pathExtension.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.muted)
            }.font(.system(size: 10))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(library.includeSubfolders ? entry.relativeFolder(to: library.path) + ", " : "")\((library.ratings[entry.path] ?? photo?.metadata.rating).map { "\($0) Sterne" } ?? (failure == nil ? "Bewertung wird geladen" : "Bewertung nicht verfügbar"))")
        .contextMenu {
            if let failure {
                Text(failure)
                Button("Vorschau erneut laden") { attempt += 1 }
                Divider()
            }
            Button(action: onMove) { Label("Datei verschieben", systemImage: "folder") }
                .disabled(library.isBusy || library.isLoading || library.isConnecting || entry.isSymbolicLink)
            Button(role: .destructive, action: onDelete) { Label("Datei löschen", systemImage: "trash") }
                .disabled(library.isBusy || library.isLoading || library.isConnecting)
        }
        .accessibilityAction(named: "Datei löschen", onDelete)
        .accessibilityAction(named: "Datei verschieben", onMove)
        .task(id: "\(library.revision)-\(attempt)") {
            guard let pipeline = library.pipeline else { return }
            photo = nil; failure = nil
            library.ratings.removeValue(forKey: entry.path)
            do {
                let loaded = try await pipeline.load(entry) { image in
                    guard !Task.isCancelled else { return }
                    previewImage = image
                }
                try Task.checkCancellation()
                photo = loaded; failure = nil
                library.ratings.removeValue(forKey: entry.path)
            } catch is CancellationError {} catch { failure = error.localizedDescription }
        }
    }
}
