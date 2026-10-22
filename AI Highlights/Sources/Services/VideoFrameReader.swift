import AVFoundation
import CoreImage
import Foundation

struct PreparedVideoFrame {
    let image: CGImage
    let timestamp: TimeInterval
    let duration: TimeInterval
    let sourcePixels: CVPixelBuffer?
    let transform: CGAffineTransform
    let backgroundSafe: Bool

    init(image: CGImage, timestamp: TimeInterval, duration: TimeInterval,
         sourcePixels: CVPixelBuffer? = nil, transform: CGAffineTransform = .identity, backgroundSafe: Bool = false) {
        self.image = image
        self.timestamp = timestamp
        self.duration = duration
        self.sourcePixels = sourcePixels
        self.transform = transform
        self.backgroundSafe = backgroundSafe
    }
}

/// One queued frame overlaps decode/render with inference. Frames stay in presentation order.
/// AVAssetReader and CIContext belong exclusively to the producer; shared state is locked.
final class VideoFrameReader: @unchecked Sendable {
    private let condition = NSCondition()
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let transform: CGAffineTransform
    private let sourceFrameRate: Double?
    private let softwareRendering: Bool
    private let execution: AnalysisExecutionPolicy?
    private let backgroundContext = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
    private var pending: PreparedVideoFrame?
    private var finished = false
    private var cancelled = false
    private var failure: Error?

    init(asset: AVAsset, track: AVAssetTrack, transform: CGAffineTransform, sourceFrameRate: Double? = nil, softwareRendering: Bool = false, execution: AnalysisExecutionPolicy? = nil, timeRange: CMTimeRange? = nil) throws {
        reader = try AVAssetReader(asset: asset)
        if let timeRange { reader.timeRange = timeRange }
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        self.transform = transform
        self.sourceFrameRate = sourceFrameRate
        self.softwareRendering = softwareRendering
        self.execution = execution
        guard reader.canAdd(output) else { throw VideoAnalysisError.unreadableVideo }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? VideoAnalysisError.unreadableVideo }
        DispatchQueue(label: "AIHighlights.frame-preparation", qos: .userInitiated).async { self.produce() }
    }

    func next() throws -> PreparedVideoFrame? {
        condition.lock()
        defer { condition.unlock() }
        while pending == nil && !finished && !cancelled {
            try Task.checkCancellation()
            // A bounded wait makes cancellation responsive without sharing Task state with GCD.
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.05))
        }
        try Task.checkCancellation()
        if cancelled { throw CancellationError() }
        if let frame = pending {
            pending = nil
            condition.signal()
            return frame
        }
        if let failure { throw failure }
        return nil
    }

    func cancel() {
        condition.lock()
        cancelled = true
        pending = nil
        condition.broadcast()
        condition.unlock()
    }

    func backgroundImage(for frame: PreparedVideoFrame) throws -> CGImage {
        guard !frame.backgroundSafe, let pixels = frame.sourcePixels else { return frame.image }
        let source = CIImage(cvPixelBuffer: pixels).transformed(by: frame.transform)
        guard let image = backgroundContext.createCGImage(source, from: source.extent) else { throw DetectorError.invalidImage }
        return image
    }

    private enum DecodedSample {
        case frame(PreparedVideoFrame), skipped, end
    }

    private func produce() {
        defer { reader.cancelReading() }
        let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: softwareRendering])
        do {
            var sourceIndex = 0
            while true {
                condition.lock()
                while pending != nil && !cancelled { condition.wait() }
                let shouldStop = cancelled
                condition.unlock()
                if shouldStop { return }
                let decoded: DecodedSample = try autoreleasepool {
                    guard let sample = output.copyNextSampleBuffer() else { return .end }
                    let selected = AnalysisSampling.includes(frameIndex: sourceIndex, sourceFrameRate: sourceFrameRate)
                    sourceIndex += 1
                    // Decode in presentation order, but render/preprocess/infer selected frames only.
                    guard selected else { return .skipped }
                    guard let pixels = CMSampleBufferGetImageBuffer(sample) else { throw VideoAnalysisError.unreadableVideo }
                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    guard timestamp.isFinite else { throw VideoAnalysisError.unreadableVideo }
                    let frame = CIImage(cvPixelBuffer: pixels).transformed(by: transform)
                    let image: CGImage?
                    var backgroundSafe = softwareRendering
                    if let execution {
                        image = execution.withFrameAccess { useBackground in
                            backgroundSafe = softwareRendering || useBackground
                            let selected = backgroundSafe ? backgroundContext : context
                            return selected.createCGImage(frame, from: frame.extent)
                        }
                    } else {
                        image = context.createCGImage(frame, from: frame.extent)
                    }
                    guard let image else { throw DetectorError.invalidImage }
                    return .frame(PreparedVideoFrame(image: image, timestamp: timestamp, duration: CMSampleBufferGetDuration(sample).seconds,
                        sourcePixels: execution == nil ? nil : pixels, transform: transform, backgroundSafe: backgroundSafe))
                }
                let next: PreparedVideoFrame
                switch decoded {
                case .skipped: continue
                case .frame(let frame): next = frame
                case .end:
                    if reader.status != .completed { throw reader.error ?? VideoAnalysisError.unreadableVideo }
                    condition.lock()
                    finished = true
                    condition.broadcast()
                    condition.unlock()
                    return
                }
                condition.lock()
                if !cancelled { pending = next }
                condition.broadcast()
                let shouldCancel = cancelled
                condition.unlock()
                if shouldCancel { return }
            }
        } catch {
            condition.lock()
            failure = error
            finished = true
            condition.broadcast()
            condition.unlock()
        }
    }
}
