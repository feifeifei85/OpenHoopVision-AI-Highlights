import AVFoundation
import UIKit

actor VideoThumbnailStore {
    static let shared = VideoThumbnailStore()
    private let images = NSCache<NSString, UIImage>()

    init() {
        images.countLimit = 40
        images.totalCostLimit = 8 * 1024 * 1024
    }

    nonisolated static func cacheURL(for videoURL: URL, at seconds: TimeInterval = 0) -> URL {
        let suffix = seconds > 0 ? ".t\(Int64((seconds * 1000).rounded()))" : ""
        return videoURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Thumbnails", isDirectory: true)
            .appendingPathComponent(videoURL.lastPathComponent + suffix + ".jpg")
    }

    nonisolated static func removeCachedImages(for videoURL: URL) {
        let directory = cacheURL(for: videoURL).deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(videoURL.lastPathComponent + ".") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func cachedImage(for videoURL: URL, at seconds: TimeInterval = 0) -> UIImage? {
        let key = Self.cacheURL(for: videoURL, at: seconds)
        if let image = images.object(forKey: key.absoluteString as NSString) { return image }
        guard let data = try? Data(contentsOf: key), let image = UIImage(data: data) else { return nil }
        cache(image, key: key.absoluteString)
        return image
    }

    func cachedImage(for source: VideoSourceReference, at seconds: TimeInterval = 0) -> UIImage? {
        switch source {
        case .appFile(let videoURL): return cachedImage(for: videoURL, at: seconds)
        case .photoLibrary(let localIdentifier):
            return images.object(forKey: Self.photoCacheKey(localIdentifier, at: seconds) as NSString)
        }
    }

    func image(for videoURL: URL, at seconds: TimeInterval = 0) async throws -> UIImage {
        try await image(for: .appFile(videoURL), at: seconds)
    }

    func image(for source: VideoSourceReference, at seconds: TimeInterval = 0) async throws -> UIImage {
        if let image = cachedImage(for: source, at: seconds) { return image }
        try Task.checkCancellation()

        let asset: AVAsset
        let destination: URL?
        let cacheKey: String
        switch source {
        case .appFile(let videoURL):
            asset = AVURLAsset(url: videoURL)
            let url = Self.cacheURL(for: videoURL, at: seconds)
            destination = url
            cacheKey = url.absoluteString
        case .photoLibrary(let localIdentifier):
            asset = try await PhotoLibraryVideoService.asset(localIdentifier: localIdentifier, networkAccessAllowed: false)
            destination = nil
            cacheKey = Self.photoCacheKey(localIdentifier, at: seconds)
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 240)
        let result = try await withTaskCancellationHandler {
            try await generator.image(at: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
        try Task.checkCancellation()
        let image = UIImage(cgImage: result.image)

        if let destination, case .appFile(let videoURL) = source {
            // Deletion or cancellation may happen while AVFoundation is decoding.
            guard FileManager.default.fileExists(atPath: videoURL.path) else { throw CancellationError() }
            if let data = image.jpegData(compressionQuality: 0.85) {
                try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: destination, options: .atomic)
            }
        }
        cache(image, key: cacheKey)
        return image
    }

    private nonisolated static func photoCacheKey(_ localIdentifier: String, at seconds: TimeInterval) -> String {
        "photo-current:\(localIdentifier):t\(Int64((seconds * 1000).rounded()))"
    }

    private func cache(_ image: UIImage, key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        images.setObject(image, forKey: key as NSString, cost: cost)
    }
}
