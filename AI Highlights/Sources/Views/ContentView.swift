import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var model = AppModel()
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.system.rawValue
    @State private var path: [AppRoute] = []
    @State private var selectedTab: AppTab = .highlights
    @State private var importSource: VideoImportSource?
    @State private var librarySection: LibrarySection = .videos

    var body: some View {
        NavigationStack(path: $path) {
            TabView(selection: $selectedTab) {
                HomeView(
                    onChoosePhotos: { importSource = .photos },
                    onChooseFiles: { importSource = .files }
                )
                    .tabItem { Label(String(localized: "Highlights", bundle: AppLanguage.current.bundle), systemImage: "basketball.fill") }
                    .tag(AppTab.highlights)
                LibraryView(
                    onChoosePhotos: { importSource = .photos },
                    onChooseFiles: { importSource = .files },
                    onOpenVideo: openVideo,
                    onOpenProject: openRecent,
                    section: $librarySection
                )
                .tabItem { Label(String(localized: "Library", bundle: AppLanguage.current.bundle), systemImage: "rectangle.stack.fill") }
                .tag(AppTab.library)
                SettingsView()
                    .tabItem { Label(String(localized: "Settings", bundle: AppLanguage.current.bundle), systemImage: "gearshape.fill") }
                    .tag(AppTab.settings)
            }
            .toolbarBackground(Color.hoopInk, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .review(let projectID):
                    if let project = model.project(withID: projectID) {
                        ReviewView(projectID: project.id, onGenerated: { path.finishGeneration(projectID: project.id) }, onRetry: {
                            path.removeAll()
                            selectedTab = .library
                            librarySection = .videos
                            model.restartAnalysis(videoID: project.sourceFileName)
                        })
                    } else {
                        MissingProjectView(onClose: pop)
                    }
                case .complete(let projectID):
                    if let project = model.project(withID: projectID) {
                        HighlightPlayerView(projectID: project.id)
                    } else {
                        MissingProjectView(onClose: { path.removeAll() })
                    }
                }
            }
        }
        .modifier(VideoImportPresenter(source: $importSource, onImported: { imported in
            path.removeAll()
            selectedTab = .library
            librarySection = .videos
            if let video = model.videos.first(where: { $0.fileName == imported.sourceKey }) {
                model.startAnalysis(for: video)
            }
        }))
        // Refresh view-local strings while retaining the app model, jobs, tab and navigation state.
        .id(language)
        .environment(\.locale, AppLanguage.current.locale)
        .environment(model)
        .tint(.hoopOrange)
        .preferredColorScheme(.dark)
        .onChange(of: router.pendingDestination) { _, destination in
            handle(destination)
        }
        .onAppear { handle(router.pendingDestination) }
        .onChange(of: path) { _, routes in
            if let draft = model.draft, !routes.contains(.review(draft.id)) { model.discardDraft() }
        }
    }

    private func handle(_ destination: IntentDestination?) {
        guard let destination else { return }
        router.pendingDestination = nil
        guard !model.isExporting else { return }
        selectedTab = .highlights
        switch destination {
        case .createHighlight:
            path.removeAll()
            importSource = .photos
        case .latestHighlight:
            guard let project = model.mostRecentProject else { return }
            path = [.complete(project.id)]
        }
    }

    private func openRecent(_ project: HighlightProject) {
        path = [.complete(project.id)]
    }

    private func openVideo(_ video: LibraryVideo) {
        if let project = model.reviewAnalysis(videoID: video.id) {
            path = [.review(project.id)]
        } else if model.analysisJobs[video.id]?.status.isActive != true {
            model.startAnalysis(for: video)
        }
    }

    private func pop() {
        if !path.isEmpty { path.removeLast() }
    }
}

private enum AppTab: Hashable {
    case highlights, library, settings
}

private struct MissingProjectView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.hoopOrange)
            Text(String(localized: "Project not found", bundle: AppLanguage.current.bundle))
                .font(.title3.bold())
            Text(String(localized: "The original video may have been removed. Please import it again.", bundle: AppLanguage.current.bundle))
                .font(.subheadline)
                .foregroundStyle(Color.hoopMuted)
            Button(String(localized: "Back to Home", bundle: AppLanguage.current.bundle), action: onClose)
                .buttonStyle(HoopPrimaryButtonStyle())
                .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .hoopScreen()
        .navigationBarBackButtonHidden()
    }
}
