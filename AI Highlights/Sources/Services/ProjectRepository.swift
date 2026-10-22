import Foundation

struct RepositoryLoad<Value> {
    let value: Value
    let errorMessage: String?
}

struct ProjectRepository: Sendable {
    private let rootURL: URL

    init(rootURL: URL? = nil) {
        let base = rootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AI Highlights", isDirectory: true)
        self.rootURL = base
    }

    var videoDirectory: URL { rootURL.appendingPathComponent("Videos", isDirectory: true) }
    var exportDirectory: URL { rootURL.appendingPathComponent("Exports", isDirectory: true) }
    private var projectsURL: URL { rootURL.appendingPathComponent("projects.json") }
    private var videosURL: URL { rootURL.appendingPathComponent("videos.json") }
    private var analysesURL: URL { rootURL.appendingPathComponent("analyses.json") }
    private var analysisCheckpointDirectory: URL { rootURL.appendingPathComponent("Analysis Checkpoints", isDirectory: true) }

    func loadAnalyses() -> RepositoryLoad<[String: VideoAnalysisJob]> {
        let jobs: [String: VideoAnalysisJob]
        do {
            jobs = try readStore([String: VideoAnalysisJob].self, at: analysesURL) ?? [:]
        } catch {
            return RepositoryLoad(value: [:], errorMessage: error.localizedDescription)
        }
        return RepositoryLoad(value: jobs.mapValues { job in
            var restored = job
            if restored.modelVersion != BasketballModel.version || restored.inputSize != .fixed1280x736 {
                removeAnalysisCheckpoint(fileName: restored.checkpointFileName)
                restored.inputSize = .fixed1280x736
                restored.modelVersion = BasketballModel.version
                restored.result = nil
                restored.performance = nil
                restored.fraction = 0
                restored.forceRescan = true
                restored.checkpointFileName = nil
                restored.errorMessage = nil
                restored.status = .interrupted
                restored.message = String(localized: "The detection model changed. Run analysis again.", bundle: AppLanguage.current.bundle)
            }
            if restored.status.isActive {
                restored.status = .interrupted
                restored.message = String(localized: "Analysis interrupted", bundle: AppLanguage.current.bundle)
            }
            return restored
        }, errorMessage: nil)
    }

    func saveAnalyses(_ jobs: [String: VideoAnalysisJob]) throws {
        try createDirectories()
        try writeStore(jobs, to: analysesURL)
    }

    func appendAnalysisCheckpoint(_ hits: [AnalysisHit], fileName: String) throws {
        guard !hits.isEmpty else { return }
        try FileManager.default.createDirectory(at: analysisCheckpointDirectory, withIntermediateDirectories: true)
        let url = analysisCheckpointDirectory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        var data = try JSONEncoder().encode(hits)
        data.append(0x0A)
        let file = try FileHandle(forUpdating: url)
        defer { try? file.close() }
        let end = try file.seekToEnd()
        if end > 0 {
            try file.seek(toOffset: end - 1)
            let lastByte = try file.read(upToCount: 1)?.first
            if lastByte != 0x0A {
                try file.seekToEnd()
                try file.write(contentsOf: Data([0x0A]))
            }
        }
        try file.seekToEnd()
        try file.write(contentsOf: data)
        try file.synchronize()
    }

    func loadAnalysisCheckpoint(fileName: String) throws -> [AnalysisHit] {
        let url = analysisCheckpointDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        return try Data(contentsOf: url).split(separator: 0x0A).flatMap { line in
            // Ignore a trailing partial batch if the app was terminated during a write.
            (try? decoder.decode([AnalysisHit].self, from: Data(line))) ?? []
        }
    }

    func removeAnalysisCheckpoint(fileName: String?) {
        guard let fileName else { return }
        let url = analysisCheckpointDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    func loadVideos() -> RepositoryLoad<[LibraryVideo]> {
        // Enumerating the directory also recovers videos imported before the library existed.
        let recorded: [LibraryVideo]
        let errorMessage: String?
        do {
            recorded = try readStore([LibraryVideo].self, at: videosURL) ?? []
            errorMessage = nil
        } catch {
            recorded = []
            errorMessage = error.localizedDescription
        }
        let records = Dictionary(recorded.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first })
        let projects = (try? storedProjects()) ?? []
        let files = (try? FileManager.default.contentsOfDirectory(
            at: videoDirectory, includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        )) ?? []
        let recovered = files.compactMap { url -> LibraryVideo? in
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { return nil }
            if let record = records[url.lastPathComponent] { return record }
            let project = projects.first { $0.sourceFileName == url.lastPathComponent }
            return LibraryVideo(
                fileName: url.lastPathComponent,
                displayName: project?.sourceDisplayName ?? String(localized: "Game video", bundle: AppLanguage.current.bundle),
                duration: project?.duration,
                importedAt: values.creationDate ?? .distantPast
            )
        }
        // Photos-backed records have no file in our Videos directory by design.
        let photoReferences = recorded.filter { $0.photoAssetIdentifier != nil }
        let recoveredFileNames = Set(recovered.map(\.fileName))
        let persistedFiles = recorded.filter {
            $0.photoAssetIdentifier == nil && recoveredFileNames.contains($0.fileName)
        }
        let videos = (photoReferences + persistedFiles + recovered.filter { records[$0.fileName] == nil })
            .sorted { $0.importedAt > $1.importedAt }
        return RepositoryLoad(value: videos, errorMessage: errorMessage)
    }

    func saveVideos(_ videos: [LibraryVideo]) throws {
        try createDirectories()
        try writeStore(videos, to: videosURL, formatting: [.prettyPrinted, .sortedKeys])
    }

    func videoURL(for video: LibraryVideo) -> URL {
        videoDirectory.appendingPathComponent(video.fileName)
    }

    func loadProjects() -> RepositoryLoad<[HighlightProject]> {
        do {
            var errorMessage: String?
            let projects = try storedProjects().filter { project in
                guard let url = exportURL(for: project) else { return false }
                do {
                    return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                    return false
                } catch {
                    errorMessage = error.localizedDescription
                    return true
                }
            }
            return RepositoryLoad(value: projects, errorMessage: errorMessage)
        } catch {
            return RepositoryLoad(value: [], errorMessage: error.localizedDescription)
        }
    }

    private func storedProjects() throws -> [HighlightProject] {
        try createDirectories()
        return (try readStore([HighlightProject].self, at: projectsURL) ?? [])
            .sorted { $0.createdAt > $1.createdAt }
    }

    func saveProjects(_ projects: [HighlightProject]) throws {
        try createDirectories()
        guard projects.allSatisfy({ project in
            guard let url = exportURL(for: project) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }) else { throw RepositoryError.unfinishedHighlight }
        try writeStore(projects, to: projectsURL, formatting: [.prettyPrinted, .sortedKeys])
    }

    func importVideo(from sourceURL: URL) throws -> (fileURL: URL, displayName: String) {
        try createDirectories()
        let displayName = sourceURL.lastPathComponent.isEmpty ? String(localized: "Game video", bundle: AppLanguage.current.bundle) : sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension.lowercased()
        let destination = videoDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return (destination, displayName)
    }

    func videoURL(for project: HighlightProject) -> URL {
        videoDirectory.appendingPathComponent(project.sourceFileName)
    }

    func exportURL(for project: HighlightProject) -> URL? {
        guard let outputFileName = project.outputFileName else { return nil }
        return exportDirectory.appendingPathComponent(outputFileName)
    }

    func createExportURL() throws -> URL {
        _ = try readStore([HighlightProject].self, at: projectsURL)
        try createDirectories()
        return exportDirectory.appendingPathComponent("AI Highlights-\(UUID().uuidString).mp4")
    }

    func deleteVideo(_ video: LibraryVideo, remainingVideos: [LibraryVideo]) throws {
        let url = video.photoAssetIdentifier == nil ? videoURL(for: video) : nil
        try removeFile(at: url) { try saveVideos(remainingVideos) }
        if let url { VideoThumbnailStore.removeCachedImages(for: url) }
    }

    func deleteProject(_ project: HighlightProject, remainingProjects: [HighlightProject]) throws {
        let url = exportURL(for: project)
        try removeFile(at: url) { try saveProjects(remainingProjects) }
        if let url { VideoThumbnailStore.removeCachedImages(for: url) }
    }

    private func removeFile(at url: URL?, commit: () throws -> Void) throws {
        try createDirectories()
        let stagingURL = rootURL.appendingPathComponent(".delete-\(UUID().uuidString)")
        let hasFile = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if hasFile, let url { try FileManager.default.moveItem(at: url, to: stagingURL) }
        do {
            try commit()
        } catch {
            if hasFile, let url { try? FileManager.default.moveItem(at: stagingURL, to: url) }
            throw error
        }
        if hasFile { try? FileManager.default.removeItem(at: stagingURL) }
    }

    private func createDirectories() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
    }

    private func readStore<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value? {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw RepositoryError.unreadableStore(url.lastPathComponent, error.localizedDescription)
        }
    }

    private func writeStore<Value: Codable>(
        _ value: Value,
        to url: URL,
        formatting: JSONEncoder.OutputFormatting = []
    ) throws {
        _ = try readStore(Value.self, at: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = formatting
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

enum RepositoryError: LocalizedError {
    case unfinishedHighlight
    case unreadableStore(String, String)

    var errorDescription: String? {
        switch self {
        case .unfinishedHighlight:
            return String(localized: "Highlights must finish exporting before they can be saved to your library.", bundle: AppLanguage.current.bundle)
        case .unreadableStore(let fileName, let reason):
            let guidance = String(localized: "Saved library data could not be read. The original file was kept. Restore or remove the damaged file to continue.", bundle: AppLanguage.current.bundle)
            return "\(guidance)\n\(fileName): \(reason)"
        }
    }
}
