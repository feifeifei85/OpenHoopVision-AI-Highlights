import AVFoundation
import Foundation
import Photos

actor VideoCompositionService {
    func createHighlight(from project: HighlightProject, source: VideoSourceReference, outputURL: URL) async throws {
        try await createVideo(ranges: project.mergedClipRanges, source: source, outputURL: outputURL)
    }

    func createClip(from project: HighlightProject, candidate: ShotCandidate, source: VideoSourceReference, outputURL: URL) async throws {
        try await createVideo(ranges: [project.clipRange(for: candidate)], source: source, outputURL: outputURL)
    }

    private func createVideo(ranges: [ClipRange], source: VideoSourceReference, outputURL: URL) async throws {
        guard !ranges.isEmpty else { throw CompositionError.noClips }
        try? FileManager.default.removeItem(at: outputURL)

        let asset = try await source.avAsset()
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else { throw CompositionError.noVideoTrack }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let sourceAudioTrack = audioTracks.first
        let sourceAudioRange = try await sourceAudioTrack?.load(.timeRange)

        let composition = AVMutableComposition()
        guard let destinationVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw CompositionError.couldNotCreateComposition }
        destinationVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        let destinationAudioTrack = sourceAudioTrack == nil ? nil : composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var cursor = CMTime.zero
        for range in ranges {
            guard range.duration > 0 else { continue }
            let timeRange = CMTimeRange(
                start: CMTime(seconds: range.start, preferredTimescale: 600),
                end: CMTime(seconds: range.end, preferredTimescale: 600)
            )
            try destinationVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: cursor)
            if let sourceAudioTrack, let destinationAudioTrack, let sourceAudioRange {
                let audioRange = CMTimeRangeGetIntersection(timeRange, otherRange: sourceAudioRange)
                if audioRange.isValid, !audioRange.isEmpty {
                    let offset = CMTimeSubtract(audioRange.start, timeRange.start)
                    try destinationAudioTrack.insertTimeRange(
                        audioRange,
                        of: sourceAudioTrack,
                        at: CMTimeAdd(cursor, offset)
                    )
                }
            }
            cursor = CMTimeAdd(cursor, timeRange.duration)
        }
        guard cursor.seconds > 0 else { throw CompositionError.noClips }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw CompositionError.couldNotCreateExporter
        }
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: outputURL, as: .mp4)
    }

    func saveToPhotos(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CompositionError.photoAccessDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

enum CompositionError: LocalizedError {
    case noClips
    case noVideoTrack
    case couldNotCreateComposition
    case couldNotCreateExporter
    case photoAccessDenied
    case exportFailed
    case exportInProgress
    case missingDraft

    var errorDescription: String? {
        switch self {
        case .noClips: return String(localized: "Select at least one shot clip to create highlights.", bundle: AppLanguage.current.bundle)
        case .noVideoTrack: return String(localized: "The selected video has no usable video track.", bundle: AppLanguage.current.bundle)
        case .couldNotCreateComposition: return String(localized: "Unable to create the highlight timeline.", bundle: AppLanguage.current.bundle)
        case .couldNotCreateExporter: return String(localized: "Unable to create a video export task.", bundle: AppLanguage.current.bundle)
        case .photoAccessDenied: return String(localized: "Allow AI Highlights to add videos to your photo library.", bundle: AppLanguage.current.bundle)
        case .exportFailed: return String(localized: "Video export failed. Please try again.", bundle: AppLanguage.current.bundle)
        case .exportInProgress: return String(localized: "Highlights are being created. Please wait until they finish.", bundle: AppLanguage.current.bundle)
        case .missingDraft: return String(localized: "Clips not found. Please analyze the video again.", bundle: AppLanguage.current.bundle)
        }
    }
}
