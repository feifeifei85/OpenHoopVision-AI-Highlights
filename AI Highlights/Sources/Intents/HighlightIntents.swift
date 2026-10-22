import AppIntents
import Foundation

struct CreateHighlightIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Shot Highlights"
    static let description = IntentDescription("Choose a basketball video to detect shots and create your personal highlights.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pendingDestination = .createHighlight
        return .result()
    }
}

struct OpenLatestHighlightIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Latest Shot Highlights"
    static let description = IntentDescription("Open your most recently created highlights in AI Highlights.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pendingDestination = .latestHighlight
        return .result()
    }
}

struct AIHighlightsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateHighlightIntent(),
            phrases: ["Create highlights with \(.applicationName)"],
            shortTitle: "Create Highlights",
            systemImageName: "basketball.fill"
        )
        AppShortcut(
            intent: OpenLatestHighlightIntent(),
            phrases: ["Open latest highlights in \(.applicationName)"],
            shortTitle: "Latest Highlights",
            systemImageName: "play.rectangle.fill"
        )
    }
}
