import SwiftUI

@main
struct SMBRatingApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var library = LibraryModel()
    var body: some Scene {
        WindowGroup {
            LibraryView().environmentObject(library)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { ReadExecutionCoordinator.shared.setActive(true) }
                    else if phase == .background { ReadExecutionCoordinator.shared.setActive(false) }
                }
        }
    }
}

extension ReadExecutionCoordinator {
    static let shared = ReadExecutionCoordinator { expiration in
        ReadBackgroundRuntime.shared.begin(expiration: expiration)
    }
}

enum Theme {
    static let background = Color(red: 0.055, green: 0.075, blue: 0.09)
    static let surface = Color(red: 0.09, green: 0.115, blue: 0.13)
    static let accent = Color(red: 0.52, green: 0.84, blue: 0.71)
    static let muted = Color(red: 0.57, green: 0.63, blue: 0.66)
}
