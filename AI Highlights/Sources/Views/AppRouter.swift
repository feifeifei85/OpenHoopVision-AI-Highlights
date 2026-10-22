import Combine
import Foundation

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var pendingDestination: IntentDestination?

    private init() {}
}

enum IntentDestination: Equatable {
    case createHighlight
    case latestHighlight
}

enum AppRoute: Hashable {
    case review(UUID)
    case complete(UUID)
}

extension Array where Element == AppRoute {
    mutating func finishGeneration(projectID: UUID) {
        guard last == .review(projectID) else { return }
        self[count - 1] = .complete(projectID)
    }
}
