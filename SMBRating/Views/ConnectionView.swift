import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var remember = false
    @State private var error: String?
    @State private var settings = ConnectionSettings()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Deine Fotos bleiben auf deinem Server.", systemImage: "externaldrive.connected.to.line.below")
                        .font(.headline).padding(.vertical, 10)
                    Text("Verbinde dich im lokalen Netzwerk oder über dein VPN mit einer SMB-Freigabe.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Server · z. B. nas.local", text: $settings.server)
                        .textContentType(.URL).keyboardType(.URL)
                    TextField("Freigabe · z. B. Fotos", text: $settings.share)
                    TextField("Startordner · optional", text: $settings.directory)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Host und Freigabe werden auf diesem Gerät für die nächste Verbindung gespeichert.")
                }
                Section("Anmeldung") {
                    TextField("Benutzername · leer für Gast", text: $settings.username).textContentType(.username)
                    SecureField("Passwort", text: $password).textContentType(.password)
                    TextField("Domäne · optional", text: $settings.domain)
                    Toggle("Passwort im Schlüsselbund merken", isOn: $remember)
                    Toggle("SMB-3-Verschlüsselung verlangen", isOn: $settings.encrypted)
                }
                Section {
                    Text("Sterne werden als eingebettetes XMP direkt in der Bilddatei gespeichert. Dafür benötigt dein Benutzer Schreib- und Umbenennrechte im Ordner. Vorhandene IPTC-Sternbewertungen werden ebenfalls gelesen.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button {
                        Task {
                            error = nil
                            if await library.connect(settings: settings, password: password, remember: remember) { dismiss() }
                            else { error = library.error; library.error = nil }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if library.isConnecting { ProgressView().padding(.trailing, 8) }
                            Text(library.isConnecting ? "Verbindung wird hergestellt …" : "Verbinden").bold()
                            Spacer()
                        }.padding(.vertical, 6)
                    }
                    .disabled(library.isConnecting || settings.server.isEmpty || settings.share.isEmpty)
                }
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .navigationTitle("SMB-Verbindung")
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Schließen") { dismiss() }.disabled(library.isConnecting)
            } }
            .disabled(library.isConnecting)
        }
        .interactiveDismissDisabled(library.isConnecting)
        .onAppear {
            settings = library.connectionFormSettings ?? library.savedConnectionSettings
            password = library.storedPassword(for: settings) ?? ""
            remember = library.savedConnection(for: settings)?.rememberPassword ?? false
            error = library.connectionFormMessage
        }
        .onChange(of: settings) { previous, draft in
            library.rememberConnectionSettings(draft)
            if !previous.matches(draft) {
                password = library.storedPassword(for: draft) ?? ""
                remember = library.savedConnection(for: draft)?.rememberPassword ?? false
            }
        }
    }
}
