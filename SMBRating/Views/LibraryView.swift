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
    @State private var listing = BrowserListing()
    @State private var unfilteredListing = BrowserListing()
    @State private var ratingFilter: RatingFilter = .all
    @State private var filterRatings: [String: Int] = [:]
    @State private var liveFilterRatings: [String: Int] = [:]
    @State private var isReadingRatings = false
    @State private var ratingReadCount = 0
    @State private var ratingReadTotal = 0
    @State private var ratingReadFailures = 0
    @State private var ratingRefreshID = UUID()
    @State private var activeRatingScan = UUID()
    @State private var prefetch = PreviewPrefetchCoordinator()

    private struct RatingScanRequest: Equatable {
        let entries: [RemoteEntry]
        let revision: UUID
        let query: String
        let filter: RatingFilter
        let refresh: UUID
        let connected: Bool
        let loading: Bool
    }

    private var ratingScanRequest: RatingScanRequest {
        RatingScanRequest(entries: library.entries, revision: library.revision, query: query,
            filter: ratingFilter, refresh: ratingRefreshID, connected: library.connected, loading: library.isLoading)
    }

    private var photos: [RemoteEntry] { listing.photos }
    private var folders: [RemoteEntry] { listing.folders }

    private func rebuildListing() {
        unfilteredListing = BrowserListing(entries: library.entries, query: query, descending: sortDescending)
        applyRatingFilter()
    }

    private func applyRatingFilter() {
        listing = unfilteredListing.filtered(by: ratingFilter, ratings: filterRatings)
        updatePrefetch()
    }

    private func updatePrefetch() {
        prefetch.configure(photos: listing.photos, indices: listing.photoIndices, pipeline: library.pipeline,
            enabled: library.connected && !library.isLoading && !isReadingRatings && photosExpanded && selection == nil)
    }

    private func ratingWasRead(_ rating: Int, path: String) {
        guard ratingFilter != .all, unfilteredListing.photoIndices[path] != nil, filterRatings[path] != rating else { return }
        liveFilterRatings[path] = rating
        filterRatings[path] = rating
        applyRatingFilter()
    }

    private func readRatings(_ request: RatingScanRequest) async {
        guard !Task.isCancelled else { return }
        let scan = UUID()
        activeRatingScan = scan
        liveFilterRatings = [:]
        filterRatings = [:]; ratingReadCount = 0; ratingReadTotal = 0; ratingReadFailures = 0
        isReadingRatings = false
        applyRatingFilter()
        guard request.filter != .all, request.connected, !request.loading, let pipeline = library.pipeline else { return }
        let endActivity = ReadExecutionCoordinator.shared.beginActivity()
        defer { endActivity() }
        // Read in display order so new matches normally arrive below existing ones.
        let candidates = BrowserListing(entries: request.entries, query: request.query, descending: sortDescending).photos
        let total = candidates.count
        var backgroundScan: (update: (Int) -> Void, finish: (Bool) -> Void)?
        var scanSucceeded = false
        defer { backgroundScan?.finish(scanSucceeded) }
        ratingReadTotal = total
        isReadingRatings = total > 0
        let delivery = RatingScanDelivery(filter: request.filter, total: total) { partial, count in
            guard activeRatingScan == scan, !Task.isCancelled else { return }
            ratingReadCount = count
            backgroundScan?.update(count)
            filterRatings = partial.ratings.merging(liveFilterRatings) { _, fresh in fresh }
            ratingReadFailures = partial.failedPaths.filter { liveFilterRatings[$0] == nil }.count
            applyRatingFilter()
        }
        defer {
            delivery.cancel()
            if activeRatingScan == scan { isReadingRatings = false }
        }
        do {
            // Typing a filename must not start a full metadata read on every keystroke.
            if !request.query.isEmpty { try await Task.sleep(nanoseconds: 180_000_000) }
            try Task.checkCancellation()
            backgroundScan = ReadBackgroundRuntime.shared.beginRatingScan(total: total)
            let result = try await RatingScanner.scan(candidates, read: { try await pipeline.rating($0) }, update: { path, rating, count in
                await delivery.receive(path: path, rating: rating, completed: count)
            })
            try Task.checkCancellation()
            guard activeRatingScan == scan else { return }
            filterRatings = result.ratings.merging(liveFilterRatings) { _, fresh in fresh }
            ratingReadFailures = result.failedPaths.filter { liveFilterRatings[$0] == nil }.count
            applyRatingFilter()
            scanSucceeded = true
        } catch is CancellationError {} catch {
            guard activeRatingScan == scan else { return }
            ratingReadFailures = total
        }
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
            Label(sidebarIsVisible ? String(localized: "Seitenleiste einklappen") : String(localized: "Seitenleiste einblenden"), systemImage: "sidebar.left")
        }
        .labelStyle(.iconOnly)
        .help(sidebarIsVisible ? String(localized: "Seitenleiste einklappen") : String(localized: "Seitenleiste einblenden"))
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
                    Text(String(localized: "BIBLIOTHEK")).font(.caption2.bold()).tracking(2).foregroundStyle(Theme.muted)
                    Label(String(localized: "Alle Bilder"), systemImage: "square.grid.2x2.fill")
                        .foregroundStyle(Theme.accent).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14).background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                if library.connected {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(String(localized: "VERBINDUNG")).font(.caption2.bold()).tracking(2).foregroundStyle(Theme.muted)
                        Label(library.isDemo ? String(localized: "Demo · lokal") : library.settings.server, systemImage: library.isDemo ? "sparkles" : "server.rack")
                            .font(.subheadline).lineLimit(2)
                        HStack(spacing: 6) {
                            Circle().fill(Theme.accent).frame(width: 6, height: 6)
                            Text(library.isDemo ? String(localized: "Zum Ausprobieren") : String(localized: "Verbunden · \(String(library.settings.share))"))
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Button(String(localized: "Verbindung trennen"), role: .destructive) { Task { await library.disconnect() } }
                            .font(.caption)
                    }
                }
                if !library.savedConnections.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(String(localized: "GESPEICHERTE VERBINDUNGEN")).font(.caption2.bold()).tracking(1).foregroundStyle(Theme.muted)
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
                    Button { library.prepareConnection() } label: { Label(String(localized: "SMB verbinden"), systemImage: "plus.circle") }
                    Button { showInfo = true } label: { Label(String(localized: "Über Bewertungen"), systemImage: "info.circle") }
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
                .navigationTitle(library.connected ? library.locationName : String(localized: "Dein nächster Lichtblick"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { sidebarToggle }
                    if library.connected {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button { Task { await library.loadFolder(library.path, refreshPreviews: true) } } label: { Image(systemName: "arrow.clockwise") }
                                .disabled(library.isLoading).accessibilityLabel(String(localized: "Ordner neu laden"))
                            ratingFilterMenu
                            Menu {
                                Toggle(String(localized: "Unterordner einbeziehen"), isOn: Binding(
                                    get: { library.includeSubfolders },
                                    set: { enabled in Task { await library.loadFolder(library.path, includingSubfolders: enabled) } }))
                                    .disabled(library.isLoading || library.isBusy || library.isConnecting)
                                Divider()
                                Picker(String(localized: "Sortierung"), selection: $sortDescending) {
                                    Text(String(localized: "Dateiname aufsteigend")).tag(false)
                                    Text(String(localized: "Dateiname absteigend")).tag(true)
                                }
                                Divider()
                                Picker(String(localized: "Vorschaubilder"), selection: $showFullImage) {
                                    Text(String(localized: "Ausschnitt anzeigen")).tag(false)
                                    Text(String(localized: "Ganzes Bild anzeigen")).tag(true)
                                }
                                Divider()
                                Picker(String(localized: "Vorschaugröße"), selection: $tileSize) {
                                    Text(String(localized: "Kleine Vorschaubilder")).tag(150.0)
                                    Text(String(localized: "Mittlere Vorschaubilder")).tag(210.0)
                                    Text(String(localized: "Große Vorschaubilder")).tag(290.0)
                                }
                            } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel(String(localized: "Ansicht anpassen"))
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $library.showConnection) { ConnectionView().environmentObject(library) }
        .fullScreenCover(item: $selection) { PhotoViewer(entries: $0.entries, initialIndex: $0.index).environmentObject(library) }
        .alert(library.error != nil ? String(localized: "Hinweis") : String(localized: "Verbindung hergestellt"), isPresented: Binding(
            get: { !library.showConnection && (library.error != nil || library.credentialWarning != nil) },
            set: { if !$0 { library.error = nil; library.credentialWarning = nil } })) {
            Button("OK") { library.error = nil; library.credentialWarning = nil }
        } message: { Text(library.error ?? library.credentialWarning ?? "") }
        .sheet(isPresented: $showInfo) { metadataInfo }
        .sheet(item: $moveRequest) { FileMoveView(request: $0).environmentObject(library) }
        .fileDeletionConfirmation($deletionRequest) { request in
            Task {
                do { try await library.deleteFile(request) }
                catch { library.error = String(localized: "Das Löschen konnte nicht bestätigt werden: \(String(error.localizedDescription))\nBitte den Ordner neu laden, um den aktuellen Stand zu prüfen.") }
            }
        }
        .onChange(of: library.connected, initial: true) { _, connected in
            guard connected else { return }
            // Once a folder is ready, give the photos the full width. Manual
            // sidebar changes remain in effect while browsing this connection.
            columnVisibility = .detailOnly
            compactColumn = .detail
        }
        .onChange(of: library.path) { _, _ in query = "" }
        .onChange(of: library.entries, initial: true) { _, _ in rebuildListing() }
        .onChange(of: query) { _, _ in rebuildListing() }
        .onChange(of: sortDescending) { _, _ in rebuildListing() }
        .onChange(of: ratingFilter) { _, _ in
            filterRatings = [:]; ratingReadFailures = 0
            applyRatingFilter()
        }
        .onChange(of: library.ratings) { previous, ratings in
            guard ratingFilter != .all else { return }
            for (path, rating) in ratings where previous[path] != rating {
                ratingWasRead(rating, path: path)
            }
        }
        .onChange(of: library.revision) { _, _ in updatePrefetch() }
        .onChange(of: library.isLoading) { _, _ in updatePrefetch() }
        .onChange(of: isReadingRatings) { _, _ in updatePrefetch() }
        .onChange(of: photosExpanded) { _, _ in updatePrefetch() }
        .onChange(of: selection?.id) { _, _ in updatePrefetch() }
        .onAppear { updatePrefetch() }
        .onDisappear { prefetch.stop() }
        .task { await library.restoreLastSession() }
        .task(id: ratingScanRequest) { await readRatings(ratingScanRequest) }
    }

    private var ratingFilterMenu: some View {
        Menu {
            Picker(String(localized: "Bewertung"), selection: $ratingFilter) {
                ForEach(RatingFilter.allCases) { filter in Text(filter.title).tag(filter) }
            }
            if ratingFilter != .all {
                Divider()
                Button(String(localized: "Bewertungen erneut lesen")) { ratingRefreshID = UUID() }
                    .disabled(isReadingRatings)
            }
        } label: {
            Label(String(localized: "Bewertung filtern"), systemImage: ratingFilter == .all
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(String(localized: "Bewertung filtern: \(String(ratingFilter.title))"))
        .disabled(library.isLoading || library.isConnecting || library.isBusy)
    }

    private var ratingFilterStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(ratingFilter.title, systemImage: "star.fill").foregroundStyle(Theme.accent)
                Spacer()
                Button(isReadingRatings ? String(localized: "Abbrechen") : String(localized: "Filter entfernen")) { ratingFilter = .all }
            }
            if isReadingRatings { ratingReadProgress }
            if ratingReadFailures > 0 {
                HStack {
                    Text(ratingReadFailures == 1 ? String(localized: "Eine Bewertung konnte nicht gelesen werden.")
                         : String(localized: "\(String(ratingReadFailures)) Bewertungen konnten nicht gelesen werden."))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Button(String(localized: "Erneut prüfen")) { ratingRefreshID = UUID() }
                        .disabled(isReadingRatings)
                }
            }
        }.font(.caption).padding(.horizontal, 28).padding(.bottom, 12)
    }

    private var ratingReadProgress: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(String(localized: "\(String(ratingReadCount)) / \(String(ratingReadTotal)) Bewertungen geprüft · weitere Treffer erscheinen automatisch"))
                .foregroundStyle(Theme.muted)
        }.font(.caption)
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
                Text(String(localized: "Deine Bilder. Dein Blick.")).font(.system(size: 34, weight: .semibold, design: .serif))
                Text(String(localized: "Fotos auf deinem Server entdecken,\nin Ruhe durchsehen und mit Sternen bewerten."))
                    .multilineTextAlignment(.center).foregroundStyle(Theme.muted).lineSpacing(5)
            }
            if library.isRestoring {
                ProgressView(String(localized: "Letzte Verbindung wird wiederhergestellt …")).padding(.vertical, 10)
            }
            Button { library.prepareConnection() } label: {
                Label(String(localized: "Mit SMB-Server verbinden"), systemImage: "externaldrive.connected.to.line.below")
                    .font(.headline).padding(.horizontal, 18).padding(.vertical, 10)
            }.buttonStyle(.borderedProminent).foregroundStyle(Theme.background).padding(.top, 8)
            Button(String(localized: "Demobibliothek öffnen")) { Task { await library.openDemo() } }.font(.subheadline)
            Text(String(localized: "Direkte Verbindung · Eingebettete XMP-Sterne · Kein Cloud-Konto"))
                .font(.caption).foregroundStyle(Theme.muted).padding(.top, 16)
        }.padding(30)
    }

    private var browser: some View {
        VStack(spacing: 0) {
            HStack {
                if library.canGoUp {
                    Button { Task { await library.goUp() } } label: { Image(systemName: "arrow.up") }
                        .accessibilityLabel(String(localized: "Übergeordneter Ordner"))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button { Task { await library.loadFolder("/") } } label: {
                            Label(library.isDemo ? String(localized: "Demobibliothek") : library.settings.share, systemImage: "externaldrive")
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
                if library.isDeleting { ProgressView(String(localized: "Datei wird gelöscht …")).font(.caption) }
                else if library.isMoving { ProgressView(String(localized: "Datei wird verschoben …")).font(.caption) }
                else { Text(photos.count == 1 ? String(localized: "1 Bild") : String(localized: "\(String(photos.count)) Bilder")).font(.caption).foregroundStyle(Theme.muted) }
            }.padding(.horizontal, 28).padding(.vertical, 18)
            if ratingFilter != .all { ratingFilterStatus }
            if library.isDemo {
                HStack {
                    Image(systemName: "sparkles")
                    Text(String(localized: "Demo mit illustrativen Beispielbildern. Bewertungen gelten nur bis zum Schließen der Demo."))
                }.font(.caption).foregroundStyle(Theme.accent).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 16)
            }
            if library.includeSubfolders && !library.isLoading {
                Label(String(localized: "Bilder aus diesem Ordner und allen Unterordnern"), systemImage: "folder.badge.plus")
                    .font(.caption).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 12)
            }
            if library.isLoading {
                Spacer()
                VStack(spacing: 18) {
                    ProgressView(String(localized: "Bilder werden gesucht …"))
                    Button(String(localized: "Abbrechen")) { library.cancelLoading() }
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        if !folders.isEmpty {
                            DisclosureGroup(isExpanded: $library.foldersExpanded) {
                                folderGrid.padding(.top, 12)
                            } label: {
                                browserSectionLabel(String(localized: "Ordner"), systemImage: "folder", count: folders.count)
                            }
                        }
                        if !photos.isEmpty {
                            DisclosureGroup(isExpanded: $photosExpanded) {
                                photoGrid.padding(.top, 12)
                            } label: {
                                browserSectionLabel(String(localized: "Bilder"), systemImage: "photo.on.rectangle", count: photos.count)
                            }
                        }
                    }.tint(Theme.accent).padding(28)
                    if !isReadingRatings && photos.isEmpty && (folders.isEmpty || ratingFilter != .all) {
                        ContentUnavailableView(ratingFilter != .all ? String(localized: "Keine Bilder mit dieser Bewertung")
                            : (query.isEmpty ? String(localized: "Keine Bilder in diesem Ordner") : String(localized: "Keine Treffer")),
                            systemImage: ratingFilter != .all ? "star.slash" : (query.isEmpty ? "photo.on.rectangle" : "magnifyingglass"),
                            description: Text(ratingFilter != .all ? String(localized: "Wähle eine andere Bewertung oder entferne den Filter.")
                                : (query.isEmpty ? String(localized: "Öffne einen anderen Ordner oder lade die Ansicht neu.") : String(localized: "Versuche einen anderen Dateinamen."))))
                            .padding(.top, 70)
                    }
                }.id("\(library.revision)-\(query)-\(sortDescending)-\(ratingFilter.rawValue)")
            }
        }
        .searchable(text: $query, prompt: String(localized: "Dateinamen suchen"))
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
                    .accessibilityLabel(String(localized: "Ordner \(String(folder.name)) öffnen"))
            }
        }
    }

    private var photoGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileSize), spacing: 18, alignment: .top)], spacing: 24) {
            ForEach(photos) { entry in
                Button {
                    selection = ViewerSelection(entries: photos, index: listing.photoIndices[entry.path] ?? 0)
                } label: {
                    PhotoTile(entry: entry, showFullImage: showFullImage, onMove: {
                        moveRequest = library.moveRequest(for: entry)
                    }, onDelete: {
                        deletionRequest = library.deletionRequest(for: entry)
                    }, onRatingLoaded: { ratingWasRead($0, path: entry.path) })
                }.buttonStyle(.plain).disabled(library.isBusy)
                    .onAppear { prefetch.appear(entry.path) }
                    .onDisappear { prefetch.disappear(entry.path) }
            }
        }
    }

    private var metadataInfo: some View {
        NavigationStack {
            List {
                Section(String(localized: "Sterne direkt im Bild")) {
                    Text(String(localized: "Lichtblick liest und schreibt xmp:Rating (0–5) im eingebetteten XMP-Paket. Vorhandene IPTC-StarRating-Werte werden als Fallback gelesen. XMP hat Vorrang. Eine vorhandene Ablehnungsmarkierung (−1) wird angezeigt und bleibt bis zur nächsten Bewertung erhalten."))
                    Text(String(localized: "JPEG, HEIC, PNG und einseitige TIFFs werden nur geändert, wenn Image I/O verlustfreies Kopieren mit Metadaten unterstützt. Andere Formate bleiben zum Ansehen verfügbar, soweit iPadOS sie decodieren kann. Es werden keine XMP-Sidecars angelegt."))
                }
                Section(String(localized: "Speichern auf SMB")) {
                    Text(String(localized: "Die gesamte Datei wird geladen. Beim Speichern wird eine temporäre Datei hochgeladen und zurückgelesen. Erst nach erfolgreicher Prüfung wird das Original über eine Sicherungsdatei ersetzt. Bitte nicht gleichzeitig in anderen Programmen bearbeiten: SMB bietet hier keinen atomaren Vergleich mit anschließendem Ersetzen."))
                    Text(String(localized: "Dateien über 128 MB werden nicht geladen. Vorschaubilder entstehen lokal; das erste Öffnen großer Ordner kann deshalb dauern. Bei einem Verbindungsabbruch während des Ersetzens kann eine .smbrating-…backup-Datei eine manuelle Wiederherstellung erfordern."))
                }
                Section("Open Source") {
                    Link("AMSMB2 · LGPL 2.1", destination: URL(string: "https://github.com/amosavian/AMSMB2")!)
                    Link("libsmb2 · LGPL 2.1", destination: URL(string: "https://github.com/sahlberg/libsmb2")!)
                    NavigationLink(String(localized: "Lizenztexte anzeigen")) {
                        ScrollView {
                            Text(licenseText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(24)
                        }.navigationTitle(String(localized: "Open-Source-Lizenzen"))
                    }
                }
            }.navigationTitle(String(localized: "Über Bewertungen")).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Fertig")) { showInfo = false } }
            }
        }
    }

    private var licenseText: String {
        guard let url = Bundle.main.url(forResource: "OpenSourceLicenses", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return String(localized: "Die Lizenztexte sind im Quellprojekt unter Resources verfügbar.") }
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
    let onRatingLoaded: (Int) -> Void
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
                        Text(String(localized: "Vorschau nicht verfügbar")).font(.caption)
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
                    Text(failure == nil ? String(localized: "Bewertung wird geladen …") : String(localized: "Bewertung nicht verfügbar"))
                        .font(.caption2).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer()
                Text(rating == -1 ? String(localized: "Abgelehnt") : (entry.name as NSString).pathExtension.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.muted)
            }.font(.system(size: 10)).frame(height: 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(library.includeSubfolders ? entry.relativeFolder(to: library.path) + ", " : "")\((library.ratings[entry.path] ?? photo?.metadata.rating).flatMap { RatingFilter(rawValue: $0)?.title } ?? (failure == nil ? String(localized: "Bewertung wird geladen") : String(localized: "Bewertung nicht verfügbar")))")
        .contextMenu {
            if let failure {
                Text(failure)
                Button(String(localized: "Vorschau erneut laden")) { attempt += 1 }
                Divider()
            }
            Button(action: onMove) { Label(String(localized: "Datei verschieben"), systemImage: "folder") }
                .disabled(library.isBusy || library.isLoading || library.isConnecting || entry.isSymbolicLink)
            Button(role: .destructive, action: onDelete) { Label(String(localized: "Datei löschen"), systemImage: "trash") }
                .disabled(library.isBusy || library.isLoading || library.isConnecting)
        }
        .accessibilityAction(named: String(localized: "Datei löschen"), onDelete)
        .accessibilityAction(named: String(localized: "Datei verschieben"), onMove)
        .task(id: "\(library.revision)-\(attempt)") {
            guard let pipeline = library.pipeline else { return }
            photo = nil; failure = nil
            library.clearRatingOverride(for: entry.path)
            do {
                let loaded = try await pipeline.load(entry) { image in
                    guard !Task.isCancelled else { return }
                    previewImage = image
                }
                try Task.checkCancellation()
                photo = loaded; failure = nil
                library.clearRatingOverride(for: entry.path)
                onRatingLoaded(loaded.metadata.rating)
            } catch is CancellationError {} catch { failure = error.localizedDescription }
        }
    }
}

/// Collects streaming reads without publishing a SwiftUI update for every file.
@MainActor
private final class RatingScanDelivery {
    private let filter: RatingFilter
    private let total: Int
    private let publish: (RatingScanResult, Int) -> Void
    private var ratings: [String: Int] = [:]
    private var failures: [String] = []
    private var completed = 0
    private var hasPublishedMatch = false
    private var lastPublished = Date.distantPast
    private var pending: Task<Void, Never>?

    init(filter: RatingFilter, total: Int, publish: @escaping (RatingScanResult, Int) -> Void) {
        self.filter = filter
        self.total = total
        self.publish = publish
    }

    func receive(path: String, rating: Int?, completed: Int) {
        guard !Task.isCancelled else { return }
        if let rating { ratings[path] = rating } else { failures.append(path) }
        self.completed = completed
        let firstMatch = !hasPublishedMatch && filter.matches(rating)
        if firstMatch { hasPublishedMatch = true }
        if firstMatch || completed == total || Date().timeIntervalSince(lastPublished) >= 0.08 {
            flush()
        } else if pending == nil {
            pending = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 80_000_000) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                self.pending = nil
                self.flush()
            }
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    private func flush() {
        cancel()
        lastPublished = Date()
        publish(RatingScanResult(ratings: ratings, failedPaths: failures), completed)
    }

    deinit { pending?.cancel() }
}
