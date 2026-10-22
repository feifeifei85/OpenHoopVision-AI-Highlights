import AVFoundation
import CoreImage
import Foundation

typealias AnalysisProgressHandler = @MainActor @Sendable (
    _ fraction: Double, _ message: String, _ performance: AnalysisPerformance?
) -> Void

actor VideoAnalysisService {
    private let hitMergeGap: TimeInterval = 0.9
    private var cachedScan: CompletedScan?

    func analyze(videoURL: URL, confidenceThreshold: Double = AnalysisSettings.defaultThreshold, execution: AnalysisExecutionPolicy? = nil, reuseCachedScan: Bool = true, progress: @escaping AnalysisProgressHandler) async throws -> VideoAnalysisResult {
        try await analyze(source: .appFile(videoURL), confidenceThreshold: confidenceThreshold,
                          execution: execution, reuseCachedScan: reuseCachedScan, progress: progress)
    }

    func analyze(source: VideoSourceReference, confidenceThreshold: Double = AnalysisSettings.defaultThreshold, execution: AnalysisExecutionPolicy? = nil, reuseCachedScan: Bool = true, progress: @escaping AnalysisProgressHandler) async throws -> VideoAnalysisResult {
        let threshold = AnalysisSettings.normalizedThreshold(confidenceThreshold)
        let identity = try VideoIdentity(source: source)
        if reuseCachedScan, let scan = cachedScan, scan.identity == identity {
            try Task.checkCancellation()
            let result = makeResult(scan: scan, threshold: threshold)
            let performance = AnalysisPerformance(
                processedFrames: scan.scores.count, elapsedSeconds: scan.performance.elapsedSeconds,
                videoFraction: 1, totalFrames: scan.scores.count, detectedGoals: result.candidates.count,
                processedVideoTime: scan.duration, totalVideoDuration: scan.duration
            )
            await progress(1, String(localized: "\(scan.scores.count) frames reused · Shot candidates: \(result.candidates.count)", bundle: AppLanguage.current.bundle), performance)
            return result
        }
        await progress(0.02, String(localized: "Opening selected video", bundle: AppLanguage.current.bundle), nil)
        let asset = try await source.avAsset()
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw VideoAnalysisError.unreadableVideo }

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoAnalysisError.unreadableVideo
        }
        let transform = try await track.load(.preferredTransform)
        let naturalSize = try await track.load(.naturalSize)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let sourceFrameRate = nominalFrameRate.isFinite && nominalFrameRate > 0 ? Double(nominalFrameRate) : nil
        let metadata = VideoMetadata.from(naturalSize: naturalSize, preferredTransform: transform,
                                          frameRate: sourceFrameRate)
        await progress(0.03, String(localized: "Loading the basketball Core ML model", bundle: AppLanguage.current.bundle), nil)
        var detector = execution?.isBackground == true ? nil : try CoreMLBasketballDetector(useGpu: true)
        let backgroundDetector: CoreMLBasketballDetector?
        if execution == nil { backgroundDetector = nil }
        // The current signing profile has no Background GPU or Background Inference entitlement.
        // Keep the fast all-units model for foreground use and pre-load a CPU-only model for background use.
        else { backgroundDetector = try CoreMLBasketballDetector(useGpu: false) }
        let frames = try VideoFrameReader(asset: asset, track: track, transform: transform,
                                          sourceFrameRate: sourceFrameRate, execution: execution)
        defer { frames.cancel() }
        var scores: [AnalysisHit] = []
        var processedFrames = 0
        var backgroundFrames = 0
        var highestConfidence = 0.0
        var detectedGoals = 0
        var lastHitTime: TimeInterval?
        let processingStart = ProcessInfo.processInfo.systemUptime
        var lastProgressUpdate = processingStart
        var fpsSamples: [(uptime: TimeInterval, frames: Int)] = [(processingStart, 0)]

        func recentFPS(at uptime: TimeInterval, processedFrames: Int) -> Double? {
            fpsSamples.append((uptime, processedFrames))
            let cutoff = uptime - 1
            while fpsSamples.count > 2, fpsSamples[1].uptime <= cutoff {
                fpsSamples.removeFirst()
            }
            guard let first = fpsSamples.first else { return nil }
            let interval = uptime - first.uptime
            guard interval >= 0.5 else { return nil }
            let rate = Double(processedFrames - first.frames) / interval
            return rate.isFinite && rate > 0 ? rate : nil
        }

        await progress(0.04, String(localized: "Goals detected: 0", bundle: AppLanguage.current.bundle), AnalysisPerformance(
            processedFrames: 0, elapsedSeconds: 0, videoFraction: 0,
            processedVideoTime: 0, totalVideoDuration: duration
        ))
        while true {
            guard let frame = try frames.next() else { break }
            try Task.checkCancellation()
            let timestamp = frame.timestamp
            guard timestamp.isFinite else { throw VideoAnalysisError.unreadableVideo }
            if detector == nil, execution?.isBackground != true {
                detector = try CoreMLBasketballDetector(useGpu: true)
            }
            var usedBackground = false
            let confidence = try autoreleasepool {
                func detect(background: Bool) throws -> Double {
                    if background, let backgroundDetector {
                        usedBackground = true
                        return try backgroundDetector.ballInBasketConfidence(in: frames.backgroundImage(for: frame))
                    }
                    guard let detector else { throw DetectorError.missingModel }
                    do { return try detector.ballInBasketConfidence(in: frame.image) }
                    catch {
                        guard let backgroundDetector else { throw error }
                        usedBackground = true
                        return try backgroundDetector.ballInBasketConfidence(in: frames.backgroundImage(for: frame))
                    }
                }
                if let execution { return try execution.withFrameAccess { try detect(background: $0) } }
                return try detect(background: false)
            }
            processedFrames += 1
            if usedBackground { backgroundFrames += 1 }
            highestConfidence = max(highestConfidence, confidence)
            scores.append(AnalysisHit(time: timestamp, confidence: confidence))
            if confidence >= threshold {
                if lastHitTime.map({ timestamp - $0 > hitMergeGap }) ?? true { detectedGoals += 1 }
                lastHitTime = timestamp
            }
            let now = ProcessInfo.processInfo.systemUptime
            if processedFrames == 1 || now - lastProgressUpdate >= 0.5 {
                lastProgressUpdate = now
                let rollingFPS = recentFPS(at: now, processedFrames: processedFrames)
                let frameDuration = frame.duration
                let frameEnd = timestamp + (frameDuration.isFinite && frameDuration > 0 ? frameDuration : 0)
                let videoFraction = min(1, max(0, frameEnd / duration))
                let performance = AnalysisPerformance(
                    processedFrames: processedFrames,
                    elapsedSeconds: now - processingStart,
                    videoFraction: videoFraction,
                    detectedGoals: detectedGoals,
                    backgroundFrames: backgroundFrames,
                    processedVideoTime: min(duration, max(0, frameEnd)), totalVideoDuration: duration,
                    recentFramesPerSecond: rollingFPS
                )
                await progress(
                    0.04 + 0.92 * videoFraction,
                    String(localized: "Goals detected: \(detectedGoals)", bundle: AppLanguage.current.bundle),
                    performance
                )
            }
        }
        try Task.checkCancellation()
        guard processedFrames > 0 else { throw VideoAnalysisError.unreadableVideo }

        let finishedAt = ProcessInfo.processInfo.systemUptime
        let rollingFPS = recentFPS(at: finishedAt, processedFrames: processedFrames)
        let performance = AnalysisPerformance(
            processedFrames: processedFrames,
            elapsedSeconds: finishedAt - processingStart,
            videoFraction: 1, totalFrames: processedFrames, detectedGoals: detectedGoals, backgroundFrames: backgroundFrames,
            processedVideoTime: duration, totalVideoDuration: duration, recentFramesPerSecond: rollingFPS
        )
        let scan = CompletedScan(identity: identity, duration: duration,
            scores: scores, highestConfidence: highestConfidence, performance: performance, metadata: metadata)
        cachedScan = scan
        let result = makeResult(scan: scan, threshold: threshold)
        await progress(1, String(localized: "\(processedFrames) frames analyzed · Shot candidates: \(result.candidates.count)", bundle: AppLanguage.current.bundle), performance)
        return result
    }

    private func makeResult(scan: CompletedScan, threshold: Double) -> VideoAnalysisResult {
        VideoAnalysisResult(
            duration: scan.duration,
            candidates: mergeHits(scan.scores.filter { $0.confidence >= threshold }, duration: scan.duration),
            processedFrames: scan.scores.count, highestConfidence: scan.highestConfidence,
            confidenceThreshold: threshold, metadata: scan.metadata
        )
    }

    private func mergeHits(_ hits: [AnalysisHit], duration: TimeInterval) -> [ShotCandidate] {
        let ordered = hits.sorted { $0.time < $1.time }
        guard !ordered.isEmpty else { return [] }
        var groups: [[AnalysisHit]] = []
        for hit in ordered {
            if let lastGroup = groups.last, let last = lastGroup.last, hit.time - last.time <= hitMergeGap {
                groups[groups.count - 1].append(hit)
            } else {
                groups.append([hit])
            }
        }
        return groups.compactMap { group in
            guard let best = group.max(by: { $0.confidence < $1.confidence }) else { return nil }
            let time = min(max(0, best.time), duration)
            return ShotCandidate(eventTime: time, confidence: best.confidence)
        }
    }
}

private struct VideoIdentity: Equatable {
    let sourceKey: String
    let size: Int?
    let modifiedAt: Date?

    init(source: VideoSourceReference) throws {
        switch source {
        case .appFile(let url):
            var freshURL = url.standardizedFileURL
            freshURL.removeAllCachedResourceValues()
            let values = try freshURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            sourceKey = source.cacheIdentity
            size = values.fileSize
            modifiedAt = values.contentModificationDate
        case .photoLibrary:
            sourceKey = source.cacheIdentity
            size = nil
            modifiedAt = nil
        }
    }
}

private struct CompletedScan {
    let identity: VideoIdentity
    let duration: TimeInterval
    let scores: [AnalysisHit]
    let highestConfidence: Double
    let performance: AnalysisPerformance
    let metadata: VideoMetadata?
}
