import SwiftUI

@main
struct AIHighlightsApp: App {
    @StateObject private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .preferredColorScheme(.dark)
        }
    }
}
