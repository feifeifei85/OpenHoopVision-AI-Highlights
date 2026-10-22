import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    let onChoosePhotos: () -> Void
    let onChooseFiles: () -> Void
    let onOpenVideo: (LibraryVideo) -> Void
    let onOpenProject: (HighlightProject) -> Void
    @Binding var section: LibrarySection
    @State private var errorMessage: String?
    @State private var revealedRow: String?

    var body: some View {
        ZStack {
        Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        List {
            Group {
                header.listRowInsets(EdgeInsets(top: 18, leading: 21, bottom: 12, trailing: 21))
                sectionSelector
                .listRowInsets(EdgeInsets(top: 0, leading: 21, bottom: 15, trailing: 21))

                if section == .videos {
                    if model.videos.isEmpty {
                        emptyState(title: String(localized: "No game videos yet", bundle: AppLanguage.current.bundle)).listRowInsets(rowInsets)
                    } else {
                        ForEach(model.videos) { video in
                            SwipeToDeleteRow(id: video.id, revealedRow: $revealedRow, onRetry: {
                                revealedRow = nil
                                model.restartAnalysis(videoID: video.id)
                            }, onDelete: { revealedRow = nil; deleteVideo(video) }) {
                                LibraryVideoCard(video: video,
                                    onOpen: { open { onOpenVideo(video) } })
                            }
                            .listRowInsets(rowInsets)
                        }
                    }
                } else if model.projects.isEmpty {
                    emptyState(title: String(localized: "No highlights yet", bundle: AppLanguage.current.bundle)).listRowInsets(rowInsets)
                } else {
                    ForEach(model.projects) { project in
                        SwipeToDeleteRow(id: project.id.uuidString, revealedRow: $revealedRow, onDelete: { revealedRow = nil; deleteHighlight(project) }) {
                            Button { open { onOpenProject(project) } } label: {
                                LibraryRowHeader(title: project.title,
                                    subtitle: String(localized: "Highlights: \(project.selectedCandidateCount) · \(project.generatedDuration.highlightDuration)", bundle: AppLanguage.current.bundle),
                                    thumbnailSource: model.outputURL(for: project).map { .appFile($0) },
                                    showsChevron: true, allowsGeneration: !model.hasActiveAnalyses)
                                    .padding(13).cardSurface()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library.highlight.\(project.id)")
                        }
                        .listRowInsets(rowInsets)
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .simultaneousGesture(
            TapGesture().onEnded {
                guard let rowID = revealedRow else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    guard revealedRow == rowID else { return }
                    closeRevealedRow()
                }
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onChanged { value in
                guard revealedRow != nil,
                      abs(value.translation.height) > 10,
                      abs(value.translation.height) > abs(value.translation.width) * 1.2 else { return }
                closeRevealedRow()
            }
        )
        }
        .contentShape(Rectangle())
        .hoopScreen()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.hasActiveAnalyses) {
            await model.loadMissingVideoMetadata()
        }
        .onChange(of: section) { _, _ in revealedRow = nil }
        .alert(String(localized: "Action incomplete", bundle: AppLanguage.current.bundle), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(String(localized: "OK", bundle: AppLanguage.current.bundle), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? String(localized: "Please try again.", bundle: AppLanguage.current.bundle)) }
    }

    private func open(_ action: () -> Void) {
        if revealedRow != nil { revealedRow = nil }
        else { action() }
    }

    private func closeRevealedRow() {
        guard revealedRow != nil else { return }
        withAnimation(.snappy) {
            revealedRow = nil
        }
    }

    private var sectionSelector: some View {
        HStack(spacing: 3) {
            sectionButton(.videos, title: String(localized: "Game Videos (\(model.videos.count))", bundle: AppLanguage.current.bundle))
            sectionButton(.highlights, title: String(localized: "My Highlights (\(model.projects.count))", bundle: AppLanguage.current.bundle))
        }
        .padding(4)
        .background(Color.hoopPanel, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private func sectionButton(_ value: LibrarySection, title: String) -> some View {
        Button {
            guard section != value else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                section = value
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(section == value ? Color.white : Color.white.opacity(0.78))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(section == value ? Color.hoopElevated : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(section == value ? [.isSelected] : [])
        .accessibilityIdentifier(value == .videos ? "library.section.videos" : "library.section.highlights")
    }

    private var rowInsets: EdgeInsets { EdgeInsets(top: 6, leading: 21, bottom: 6, trailing: 21) }

    private var header: some View {
        HStack {
            Text(String(localized: "Library", bundle: AppLanguage.current.bundle)).font(.system(size: 30, weight: .black, design: .rounded))
            Spacer()
            Menu {
                Button(String(localized: "Photos", bundle: AppLanguage.current.bundle), systemImage: "photo.on.rectangle.angled", action: onChoosePhotos)
                Button(String(localized: "Browse Files", bundle: AppLanguage.current.bundle), systemImage: "folder", action: onChooseFiles)
            } label: {
                Image(systemName: "plus").font(.system(size: 19, weight: .bold))
                    .padding(13).background(Color.hoopPanel, in: Circle())
            }
            .accessibilityLabel(String(localized: "Import game video", bundle: AppLanguage.current.bundle))
        }
    }

    private func emptyState(title: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 40)).foregroundStyle(Color.hoopOrange)
            Text(title).font(.system(size: 18, weight: .bold))
            VideoImportControls(onChoosePhotos: onChoosePhotos, onChooseFiles: onChooseFiles)
        }
        .padding(24).padding(.vertical, 25).frame(maxWidth: .infinity).cardSurface()
    }

    private func deleteVideo(_ video: LibraryVideo) {
        do { try model.deleteVideo(video) }
        catch { errorMessage = error.localizedDescription }
    }

    private func deleteHighlight(_ project: HighlightProject) {
        do { try model.deleteHighlight(project) }
        catch { errorMessage = error.localizedDescription }
    }
}

// Each active video owns its own observable progress so updates stay in this row.
private struct LibraryVideoCard: View {
    @Environment(AppModel.self) private var model
    let video: LibraryVideo
    let onOpen: () -> Void
    @State private var thresholdValue = 25.0
    @State private var isShowingThresholdPrompt = false

    var body: some View {
        let job = model.analysisJobs[video.id]
        let progress = model.analysisProgress[video.id]?.snapshot
        let allowsThumbnailGeneration = !model.hasActiveAnalyses || job?.status.isActive == true
        return VStack(alignment: .leading, spacing: 13) {
            Button(action: onOpen) {
                LibraryRowHeader(title: video.displayName, subtitle: videoSubtitle(video), thumbnailSource: model.videoSource(for: video),
                          showsChevron: job?.result != nil || job == nil, allowsGeneration: allowsThumbnailGeneration)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library.video.\(video.id)")
            if let job {
                Divider().overlay(Color.hoopStroke)
                if job.status.isActive {
                    HStack(spacing: 8) {
                        if job.status == .queued { ProgressView().controlSize(.small).tint(.hoopOrange) }
                        Text(job.status == .running ? (progress?.performance.map { String(localized: "Goals detected: \($0.detectedGoals)", bundle: AppLanguage.current.bundle) } ?? progress?.message ?? job.message) : String(localized: "Waiting for analysis", bundle: AppLanguage.current.bundle))
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                        if job.status == .running { Text(verbatim: (progress?.fraction ?? job.fraction).formatted(.percent.precision(.fractionLength(0)).locale(AppLanguage.current.locale))).monospacedDigit() }
                        Button { model.cancelAnalysis(videoID: video.id) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 21)).foregroundStyle(Color.hoopMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Cancel Analysis", bundle: AppLanguage.current.bundle))
                        .accessibilityIdentifier("analysis.cancel.\(video.id)")
                    }
                    .font(.system(size: 11))
                    ProgressView(value: progress?.fraction ?? job.fraction).tint(.hoopOrange)
                    if let performance = progress?.performance ?? job.performance {
                        HStack(spacing: 4) {
                            Text("\(mediaTime(performance.processedVideoTime))/\(mediaTime(performance.totalVideoDuration))")
                            Spacer(minLength: 2)
                            Text(fps(performance.framesPerSecond))
                            Text(String(localized: "ETA \(eta(performance.estimatedRemainingSeconds))", bundle: AppLanguage.current.bundle))
                        }
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.hoopMuted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    }
                } else {
                    HStack(spacing: 9) {
                        Text(statusText(job)).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(job.status == .ready ? Color.hoopMint : Color.hoopMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if job.status == .ready {
                            Button(String(localized: "Select Clips", bundle: AppLanguage.current.bundle)) { onOpen() }
                        } else if job.status == .empty {
                            Button(String(localized: "Adjust Threshold", bundle: AppLanguage.current.bundle)) {
                                thresholdValue = (job.threshold * 100).rounded()
                                isShowingThresholdPrompt = true
                            }
                        } else {
                            Button(String(localized: "Analyze Again", bundle: AppLanguage.current.bundle)) { model.restartAnalysis(videoID: video.id) }
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.plain).foregroundStyle(Color.hoopOrange)
                    if job.status == .empty, let result = job.result {
                        Text(String(localized: "Peak \(result.highestConfidence.formatted(.percent.precision(.fractionLength(1)))) · Threshold \(result.confidenceThreshold.formatted(.percent))", bundle: AppLanguage.current.bundle))
                            .font(.system(size: 10)).foregroundStyle(Color.hoopMuted)
                    }
                }
            }
        }
        .padding(13).cardSurface()
        .contextMenu {
            if job?.status.isActive == true { Button(String(localized: "Cancel Analysis", bundle: AppLanguage.current.bundle), systemImage: "xmark.circle") { model.cancelAnalysis(videoID: video.id) } }
            else { Button(String(localized: "Analyze Again", bundle: AppLanguage.current.bundle), systemImage: "arrow.clockwise") { model.restartAnalysis(videoID: video.id) } }
        }
        .sheet(isPresented: $isShowingThresholdPrompt) {
            ThresholdEditorSheet(value: $thresholdValue, onApply: applyThreshold)
        }
    }

    private func statusText(_ job: VideoAnalysisJob) -> String {
        switch job.status {
        case .ready: return String(localized: "Highlights found: \(job.candidateCount)", bundle: AppLanguage.current.bundle)
        case .empty: return String(localized: "Analysis complete. No shots found.", bundle: AppLanguage.current.bundle)
        case .failed: return job.errorMessage ?? String(localized: "Analysis failed", bundle: AppLanguage.current.bundle)
        case .cancelled: return String(localized: "Analysis cancelled", bundle: AppLanguage.current.bundle)
        case .interrupted: return String(localized: "Analysis interrupted", bundle: AppLanguage.current.bundle)
        case .queued: return String(localized: "Waiting for analysis", bundle: AppLanguage.current.bundle)
        case .running: return job.message
        }
    }

    private func mediaTime(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite else { return "00:00:00" }
        let value = Int(min(max(0, seconds.rounded(.down)), 359_999))
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }

    private func eta(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite else { return "--:--:--" }
        return mediaTime(seconds)
    }

    private func fps(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "— FPS" }
        return String(format: "%.1f FPS", value)
    }

    private func applyThreshold() {
        let fallback = model.analysisJobs[video.id]?.threshold ?? model.confidenceThreshold
        let entered = thresholdValue.isFinite ? thresholdValue : fallback * 100
        isShowingThresholdPrompt = false
        model.startAnalysis(for: video, threshold: entered / 100)
    }

    private func videoSubtitle(_ video: LibraryVideo) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: video.importedAt)
        let date = String(format: "%02d-%02d %02d:%02d", parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
        let yearPrefix = parts.year != calendar.component(.year, from: .now) ? "\(parts.year ?? 0)-" : ""
        let time = video.duration.map { "\($0.highlightDuration) · \(yearPrefix)\(date)" } ?? "\(yearPrefix)\(date)"
        return [time, video.metadata?.label].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

}

private struct LibraryRowHeader: View {
    let title: String
    let subtitle: String
    let thumbnailSource: VideoSourceReference?
    let showsChevron: Bool
    let allowsGeneration: Bool

    var body: some View {
        HStack(spacing: 13) {
            VideoThumbnailView(videoSource: thumbnailSource,
                allowsGeneration: allowsGeneration)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(2).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Color.hoopMuted)
                    .lineLimit(1).minimumScaleFactor(0.8).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.hoopMuted) }
        }
        .contentShape(Rectangle())
    }

}

private extension View {
    func cardSurface() -> some View {
        background(Color.hoopPanel, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.hoopStroke, lineWidth: 1) }
    }
}

enum LibrarySection: Hashable { case videos, highlights }
