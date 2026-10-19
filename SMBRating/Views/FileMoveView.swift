import SwiftUI

struct FileMoveView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let request: FileMoveRequest
    var onMoved: () -> Void = {}
    @State private var destination: String
    @State private var contents: [RemoteEntry] = []
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var loadError: String?
    @State private var moveError: String?
    @State private var retry = 0

    init(request: FileMoveRequest, onMoved: @escaping () -> Void = {}) {
        self.request = request
        self.onMoved = onMoved
        _destination = State(initialValue: request.sourceFolder)
    }

    private var folders: [RemoteEntry] {
        contents.filter { $0.isDirectory && !$0.isSymbolicLink }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var nameExists: Bool {
        contents.contains { $0.name.localizedCaseInsensitiveCompare(request.entry.name) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "Datei")) {
                    Label(request.entry.name, systemImage: "photo").font(.headline)
                    Text(String(localized: "Quelle: \(String(request.sourceFolder))")).font(.caption).foregroundStyle(.secondary)
                }
                Section(String(localized: "Zielordner")) {
                    Label(destination, systemImage: "folder.fill").textSelection(.enabled)
                    if destination != "/" {
                        Button { openFolder("/") } label: {
                            Label(library.isDemo ? String(localized: "Demobibliothek") : library.settings.share, systemImage: "externaldrive")
                        }
                        Button {
                            openFolder((destination as NSString).deletingLastPathComponent)
                        } label: { Label(String(localized: "Übergeordneter Ordner"), systemImage: "arrow.up") }
                    }
                }.disabled(isLoading || library.isBusy)
                Section(String(localized: "Unterordner")) {
                    if isLoading {
                        ProgressView(String(localized: "Ordner werden geladen …"))
                    } else if let loadError {
                        Text(loadError).foregroundStyle(.secondary)
                        Button(String(localized: "Erneut laden")) { retry += 1 }
                    } else if folders.isEmpty {
                        Text(String(localized: "Keine Unterordner")).foregroundStyle(.secondary)
                    } else {
                        ForEach(folders) { folder in
                            Button { openFolder(folder.path) } label: {
                                HStack {
                                    Label(folder.name, systemImage: "folder")
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }.disabled(library.isBusy)
                        }
                    }
                }
                if destination == request.sourceFolder {
                    Text(String(localized: "Wähle einen anderen Ordner als Ziel.")).font(.footnote).foregroundStyle(.secondary)
                } else if !isLoading && loadError == nil && nameExists {
                    Text(String(localized: "Hier gibt es bereits einen Eintrag mit diesem Namen. Wähle einen anderen Ordner."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "Datei verschieben"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Abbrechen")) { dismiss() }.disabled(isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if isSubmitting { ProgressView(String(localized: "Datei wird verschoben …")) }
                    Spacer()
                    Button(action: move) {
                        Label(String(localized: "Hierher verschieben"), systemImage: "folder")
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading || isSubmitting || loadError != nil || library.isBusy
                                  || destination == request.sourceFolder || nameExists)
                }
                .padding(16).background(.bar)
            }
            .task(id: "\(destination)-\(retry)") { await loadFolders() }
            .alert(String(localized: "Verschieben nicht bestätigt"), isPresented: Binding(
                get: { moveError != nil }, set: { if !$0 { moveError = nil } })) {
                    Button("OK") { moveError = nil }
                } message: { Text(moveError ?? "") }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private func openFolder(_ path: String) {
        isLoading = true; contents = []; loadError = nil
        destination = path
    }

    private func loadFolders() async {
        isLoading = true; loadError = nil; contents = []
        do {
            let result = try await library.moveDestinationContents(destination, for: request)
            try Task.checkCancellation()
            contents = result; isLoading = false
        } catch is CancellationError {} catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription; isLoading = false
        }
    }

    private func move() {
        guard !isSubmitting else { return }
        isSubmitting = true
        let target = destination
        Task {
            do {
                try await library.moveFile(request, to: target)
                dismiss()
                onMoved()
            } catch {
                isSubmitting = false
                moveError = error.localizedDescription
            }
        }
    }
}
