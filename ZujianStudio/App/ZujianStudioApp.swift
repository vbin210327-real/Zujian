import SwiftUI

@main
struct ZujianStudioApp: App {
    @StateObject private var library = RecordingLibrary()

    var body: some Scene {
        WindowGroup {
            StudioRootView()
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}
