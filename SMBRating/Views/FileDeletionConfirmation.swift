import SwiftUI

private struct FileDeletionConfirmation: ViewModifier {
    @Binding var request: FileDeletionRequest?
    let onConfirm: (FileDeletionRequest) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Datei löschen?", isPresented: Binding(
            get: { request != nil }, set: { if !$0 { request = nil } }),
            titleVisibility: .visible, presenting: request) { confirmed in
                Button("Endgültig löschen", role: .destructive) {
                    request = nil
                    onConfirm(confirmed)
                }
                Button("Abbrechen", role: .cancel) { request = nil }
            } message: { confirmed in
                Text(confirmed.message)
            }
    }
}

extension View {
    func fileDeletionConfirmation(_ request: Binding<FileDeletionRequest?>,
                                  onConfirm: @escaping (FileDeletionRequest) -> Void) -> some View {
        modifier(FileDeletionConfirmation(request: request, onConfirm: onConfirm))
    }
}
