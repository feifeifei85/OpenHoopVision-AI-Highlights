import AVKit
import SwiftUI

struct HighlightPlayerView: View {
    let projectID: UUID
    @Environment(AppModel.self) private var model
    @State private var player: AVPlayer?
    @State private var isSaving = false
    @State private var alertMessage: String?

    private var project: HighlightProject? { model.projects.first { $0.id == projectID } }
    private var outputURL: URL? { project.flatMap { model.outputURL(for: $0) } }

    var body: some View {
        VStack(spacing: 20) {
            if let project, let outputURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text(project.title).font(.system(size: 21, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "Highlights: \(project.selectedCandidateCount) · \(project.generatedDuration.highlightDuration)", bundle: AppLanguage.current.bundle))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Color.hoopMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
                VideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("highlight.player")
                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    ShareLink(item: outputURL) {
                        Label(String(localized: "Share", bundle: AppLanguage.current.bundle), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("highlight.share")
                    Button {
                        Task { await saveToPhotos() }
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving { ProgressView().tint(.white) }
                            else { Image(systemName: "square.and.arrow.down") }
                            Text(isSaving ? String(localized: "Saving…", bundle: AppLanguage.current.bundle) : String(localized: "Save to Photos", bundle: AppLanguage.current.bundle))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("highlight.save")
                }
                .buttonStyle(HoopPrimaryButtonStyle())
            } else {
                ContentUnavailableView(String(localized: "Highlights not found", bundle: AppLanguage.current.bundle), systemImage: "video.slash")
            }
        }
        .padding(20)
        .hoopScreen()
        .navigationTitle(String(localized: "Shot Highlights", bundle: AppLanguage.current.bundle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: projectID) {
            guard let outputURL else { return }
            let nextPlayer = AVPlayer(url: outputURL)
            do { try PlaybackAudioSession.prepare(nextPlayer) }
            catch { alertMessage = error.localizedDescription; return }
            player = nextPlayer
            nextPlayer.play()
        }
        .onDisappear { player?.pause(); player = nil }
        .alert(String(localized: "Highlights", bundle: AppLanguage.current.bundle), isPresented: Binding(
            get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } }
        )) {
            Button(String(localized: "OK", bundle: AppLanguage.current.bundle), role: .cancel) { alertMessage = nil }
        } message: { Text(alertMessage ?? "") }
    }

    @MainActor
    private func saveToPhotos() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await model.saveToPhotos(projectID: projectID)
            alertMessage = String(localized: "Saved to your photo library.", bundle: AppLanguage.current.bundle)
        } catch { alertMessage = error.localizedDescription }
    }
}
