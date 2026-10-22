import AVFoundation
import Foundation
import Photos

struct PhotoVideoSnapshot: Sendable {
    let localIdentifier: String
    let displayName: String
    let duration: TimeInterval
    let width: Int
    let height: Int
    let modificationDate: Date?
}

enum VideoSourceError: LocalizedError {
    case photoAccessDenied
    case photoReferenceUnavailable
    case photoAssetUnavailable
    case photoVideoUnavailable

    var errorDescription: String? {
        switch self {
        case .photoAccessDenied:
            String(localized: "Allow photo library access to use this video without copying it.", bundle: AppLanguage.current.bundle)
        case .photoReferenceUnavailable:
            String(localized: "Couldn't create a direct reference to this video. Select it from Photos again.", bundle: AppLanguage.current.bundle)
        case .photoAssetUnavailable:
            String(localized: "Photos can't access the selected video. Allow access to it or select it again.", bundle: AppLanguage.current.bundle)
        case .photoVideoUnavailable:
            String(localized: "Photos could not open this video. Check its download status and try again.", bundle: AppLanguage.current.bundle)
        }
    }
}

/// Bridges Swift task cancellation to the request IDs returned by PhotoKit.
/// A request can finish before PhotoKit returns its ID, so completion and
/// cancellation are synchronized with ID installation.
private final class PhotoRequestCancellation: @unchecked Sendable {
    private let manager: PHImageManager
    private let lock = NSLock()
    private var requestID: PHImageRequestID?
    private var isCancelled = false
    private var isCompleted = false

    init(manager: PHImageManager = .default()) {
        self.manager = manager
    }

    func requestAVAsset(
        for asset: PHAsset,
        options: PHVideoRequestOptions,
        resultHandler: @escaping (AVAsset?, AVAudioMix?, [AnyHashable: Any]?) -> Void
    ) {
        let requestID = manager.requestAVAsset(forVideo: asset, options: options, resultHandler: resultHandler)
        install(requestID)
    }

    func requestPlayerItem(
        for asset: PHAsset,
        options: PHVideoRequestOptions,
        resultHandler: @escaping (AVPlayerItem?, [AnyHashable: Any]?) -> Void
    ) {
        let requestID = manager.requestPlayerItem(forVideo: asset, options: options, resultHandler: resultHandler)
        install(requestID)
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let requestID = isCompleted ? nil : self.requestID
        self.requestID = nil
        lock.unlock()

        if let requestID {
            manager.cancelImageRequest(requestID)
        }
    }

    /// Returns whether the owning Swift task had already been cancelled.
    func complete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        isCompleted = true
        requestID = nil
        return isCancelled
    }

    private func install(_ requestID: PHImageRequestID) {
        lock.lock()
        let shouldCancel = isCancelled && !isCompleted
        if !isCancelled && !isCompleted {
            self.requestID = requestID
        }
        lock.unlock()

        if shouldCancel {
            manager.cancelImageRequest(requestID)
        }
    }
}

/// Resolves Photos assets on demand. Only the Photos local identifier is persisted by the app.
enum PhotoLibraryVideoService {
    /// Persisted analysis results are tied to the Photos representation they scanned.
    static let currentVersionIdentifier = "photos-current-v1"

    static func snapshot(localIdentifier: String) async throws -> PhotoVideoSnapshot {
        let asset = try await fetchVideo(localIdentifier: localIdentifier)
        let originalName = PHAssetResource.assetResources(for: asset).first?.originalFilename
        let displayName = originalName.flatMap { $0.isEmpty ? nil : $0 }
            ?? String(localized: "Game video", bundle: AppLanguage.current.bundle)
        let duration = asset.duration
        guard duration.isFinite, duration > 0 else { throw VideoAnalysisError.unreadableVideo }
        return PhotoVideoSnapshot(
            localIdentifier: localIdentifier,
            displayName: displayName,
            duration: duration,
            width: asset.pixelWidth,
            height: asset.pixelHeight,
            modificationDate: asset.modificationDate
        )
    }

    static func asset(localIdentifier: String, networkAccessAllowed: Bool = true) async throws -> AVAsset {
        try Task.checkCancellation()
        let photo = try await fetchVideo(localIdentifier: localIdentifier)
        try Task.checkCancellation()
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = networkAccessAllowed
        let request = PhotoRequestCancellation()
        let asset = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAsset, Error>) in
                request.requestAVAsset(for: photo, options: options) { asset, _, info in
                    let wasCancelled = request.complete()
                    if wasCancelled || info?[PHImageCancelledKey] as? Bool == true {
                        continuation.resume(throwing: CancellationError())
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                    } else if let asset {
                        continuation.resume(returning: asset)
                    } else {
                        continuation.resume(throwing: VideoSourceError.photoVideoUnavailable)
                    }
                }
            }
        } onCancel: {
            request.cancel()
        }
        try Task.checkCancellation()
        return asset
    }

    static func playerItem(localIdentifier: String) async throws -> AVPlayerItem {
        try Task.checkCancellation()
        let photo = try await fetchVideo(localIdentifier: localIdentifier)
        try Task.checkCancellation()
        let options = PHVideoRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let request = PhotoRequestCancellation()
        let item = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVPlayerItem, Error>) in
                request.requestPlayerItem(for: photo, options: options) { item, info in
                    let wasCancelled = request.complete()
                    if wasCancelled || info?[PHImageCancelledKey] as? Bool == true {
                        continuation.resume(throwing: CancellationError())
                    } else if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                    } else if let item {
                        continuation.resume(returning: item)
                    } else {
                        continuation.resume(throwing: VideoSourceError.photoVideoUnavailable)
                    }
                }
            }
        } onCancel: {
            request.cancel()
        }
        try Task.checkCancellation()
        return item
    }

    private static func fetchVideo(localIdentifier: String) async throws -> PHAsset {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let resolvedStatus: PHAuthorizationStatus
        if status == .notDetermined {
            resolvedStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            resolvedStatus = status
        }
        try Task.checkCancellation()
        guard resolvedStatus == .authorized || resolvedStatus == .limited else {
            throw VideoSourceError.photoAccessDenied
        }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = result.firstObject, asset.mediaType == .video else {
            throw VideoSourceError.photoAssetUnavailable
        }
        return asset
    }
}

extension VideoSourceReference {
    func avAsset(networkAccessAllowed: Bool = true) async throws -> AVAsset {
        switch self {
        case .appFile(let url): return AVURLAsset(url: url)
        case .photoLibrary(let localIdentifier):
            return try await PhotoLibraryVideoService.asset(localIdentifier: localIdentifier, networkAccessAllowed: networkAccessAllowed)
        }
    }

    func playerItem() async throws -> AVPlayerItem {
        switch self {
        case .appFile(let url): return AVPlayerItem(url: url)
        case .photoLibrary(let localIdentifier):
            return try await PhotoLibraryVideoService.playerItem(localIdentifier: localIdentifier)
        }
    }
}
