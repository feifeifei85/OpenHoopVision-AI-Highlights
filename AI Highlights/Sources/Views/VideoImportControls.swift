import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum VideoImportSource: Equatable {
    case photos, files
}

/// The two import sources share one compact row on the home screen and in an empty library.
struct VideoImportControls: View {
    let onChoosePhotos: () -> Void
    let onChooseFiles: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onChoosePhotos) {
                Label(String(localized: "Photos", bundle: AppLanguage.current.bundle), systemImage: "photo.on.rectangle.angled")
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .buttonStyle(HoopPrimaryButtonStyle())
            .accessibilityIdentifier("import.photos")
            Button(action: onChooseFiles) {
                Label(String(localized: "Browse Files", bundle: AppLanguage.current.bundle), systemImage: "folder")
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            .buttonStyle(FileImportButtonStyle())
            .accessibilityIdentifier("import.files")
        }
    }
}

private struct FileImportButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Color.hoopOrange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.hoopElevated, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(Color.hoopStroke, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Present native pickers at the app root so importing never adds a navigation page.
struct VideoImportPresenter: ViewModifier {
    @Binding var source: VideoImportSource?
    let onImported: (ImportedVideo) -> Void

    @Environment(AppModel.self) private var model
    @State private var photoItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: isPresenting(.photos), selection: $photoItem, matching: .videos, photoLibrary: .shared())
            .fileImporter(
                isPresented: isPresenting(.files),
                allowedContentTypes: [.movie, .mpeg4Movie],
                allowsMultipleSelection: false,
                onCompletion: handleFileSelection
            )
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await loadPhotoVideo(item) }
            }
            .alert(
                model.analysisPersistenceErrorMessage == nil && model.repositoryLoadErrorMessage == nil
                    ? String(localized: "Unable to Import Video", bundle: AppLanguage.current.bundle)
                    : String(localized: "Action incomplete", bundle: AppLanguage.current.bundle),
                isPresented: Binding(
                    get: { errorMessage != nil || model.analysisPersistenceErrorMessage != nil || model.repositoryLoadErrorMessage != nil },
                    set: { if !$0 { dismissCurrentError() } }
                )
            ) {
                Button(String(localized: "OK", bundle: AppLanguage.current.bundle), role: .cancel) {
                    dismissCurrentError()
                }
            } message: {
                Text(model.analysisPersistenceErrorMessage ?? model.repositoryLoadErrorMessage ?? errorMessage ?? String(localized: "Please try again.", bundle: AppLanguage.current.bundle))
            }
            .overlay {
                if isImporting {
                    ZStack {
                        Color.black.opacity(0.62).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().tint(Color.hoopOrange).scaleEffect(1.2)
                            Text(String(localized: "Importing video…", bundle: AppLanguage.current.bundle)).font(.system(size: 14, weight: .semibold))
                        }
                        .padding(26)
                        .background(Color.hoopPanel, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .accessibilityIdentifier("import.loading")
                }
            }
    }

    private func isPresenting(_ choice: VideoImportSource) -> Binding<Bool> {
        Binding(get: { source == choice }, set: { if !$0, source == choice { source = nil } })
    }

    private func dismissCurrentError() {
        if model.analysisPersistenceErrorMessage != nil {
            model.dismissAnalysisPersistenceError()
        } else if model.repositoryLoadErrorMessage != nil {
            model.dismissRepositoryLoadError()
        } else {
            errorMessage = nil
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importVideo(from: url) }
        case .failure(let error):
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSUserCancelledError { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadPhotoVideo(_ item: PhotosPickerItem) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false; photoItem = nil }
        do {
            guard let localIdentifier = item.itemIdentifier else { throw VideoSourceError.photoReferenceUnavailable }
            try await model.importPhotoVideo(localIdentifier: localIdentifier)
            try Task.checkCancellation()
            guard let video = model.activeVideo else { throw VideoAnalysisError.unreadableVideo }
            source = nil
            onImported(video)
        } catch is CancellationError {
            return
        } catch { errorMessage = error.localizedDescription }
    }

    private func importVideo(from url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            try await finishImport(from: url)
        } catch is CancellationError {
            return
        } catch { errorMessage = error.localizedDescription }
    }

    private func finishImport(from url: URL) async throws {
        try await model.importVideo(from: url)
        try Task.checkCancellation()
        guard let video = model.activeVideo else { throw VideoAnalysisError.unreadableVideo }
        source = nil
        onImported(video)
    }
}
