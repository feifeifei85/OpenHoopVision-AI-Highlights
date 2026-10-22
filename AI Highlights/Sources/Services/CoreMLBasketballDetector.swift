import CoreML
import Foundation
import ImageIO
import Vision

struct BasketDetection: Sendable {
    let confidence: Double
}

enum DetectorError: LocalizedError {
    case missingModel
    case unsupportedInput
    case unsupportedOutput
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return String(localized: "BasketballDetector is missing from the app.", bundle: AppLanguage.current.bundle)
        case .unsupportedInput:
            return String(localized: "BasketballDetector requires a fixed 1280 × 736 RGB image input.", bundle: AppLanguage.current.bundle)
        case .unsupportedOutput:
            return String(localized: "BasketballDetector must return an NMS-free [1, 300, 6] detection output.", bundle: AppLanguage.current.bundle)
        case .invalidImage:
            return String(localized: "Unable to read this video frame.", bundle: AppLanguage.current.bundle)
        }
    }
}

/// Runs the bundled YOLO26 Core ML image model through Vision and reads its NMS-free detections.
/// Vision performs aspect-fit preprocessing; Core ML can use all available compute units and
/// chooses the available hardware per device and OS.
final class CoreMLBasketballDetector {
    private static let detectionCount = 300
    private static let valuesPerDetection = 6
    private static let targetClassID: Float = 2

    private let visionModel: VNCoreMLModel
    private let request: VNCoreMLRequest

    /// Let Core ML choose the best available hardware on each device and OS version.
    /// `useGpu` follows Ultralytics' public option name; for Core ML, `true` allows
    /// every compute unit rather than forcing GPU execution.
    private static func computeUnits(useGpu: Bool) -> MLComputeUnits { useGpu ? .all : .cpuOnly }

    init(
        bundle: Bundle = .main,
        modelURL: URL? = nil,
        useGpu: Bool = true
    ) throws {
        guard let modelURL = modelURL ?? bundle.url(forResource: BasketballModel.resourceName, withExtension: "mlmodelc") else {
            throw DetectorError.missingModel
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = Self.computeUnits(useGpu: useGpu)
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)

        guard let imageInput = model.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .image })?.imageConstraint,
              imageInput.pixelsWide == BasketballModel.inputWidth,
              imageInput.pixelsHigh == BasketballModel.inputHeight else {
            throw DetectorError.unsupportedInput
        }
        let hasExpectedOutput = model.modelDescription.outputDescriptionsByName.values.contains { description in
            guard description.type == .multiArray,
                  let constraint = description.multiArrayConstraint else { return false }
            return constraint.shape.map(\.intValue) == [1, Self.detectionCount, Self.valuesPerDetection]
        }
        guard hasExpectedOutput else { throw DetectorError.unsupportedOutput }

        let visionModel = try VNCoreMLModel(for: model)
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFit

        self.visionModel = visionModel
        self.request = request
    }

    func detectBallInBasket(in image: CGImage, threshold: Double = AnalysisSettings.defaultThreshold) throws -> BasketDetection? {
        let confidence = try ballInBasketConfidence(in: image)
        guard confidence >= AnalysisSettings.normalizedThreshold(threshold) else { return nil }
        return BasketDetection(confidence: confidence)
    }

    func ballInBasketConfidence(in image: CGImage) throws -> Double {
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            throw DetectorError.invalidImage
        }
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
              let output = observations.lazy.compactMap({ $0.featureValue.multiArrayValue }).first else {
            throw DetectorError.unsupportedOutput
        }
        return try Self.maximumTargetConfidence(in: output)
    }

    var inputDimensions: [Int] { [1, 3, BasketballModel.inputHeight, BasketballModel.inputWidth] }

    private static func maximumTargetConfidence(in output: MLMultiArray) throws -> Double {
        let shape = output.shape.map(\.intValue)
        let strides = output.strides.map(\.intValue)
        guard shape == [1, detectionCount, valuesPerDetection], strides.count == 3 else {
            throw DetectorError.unsupportedOutput
        }

        var maximum: Float = 0
        for row in 0..<detectionCount {
            let classID = scalar(output, batch: 0, row: row, field: 5, strides: strides)
            guard classID.isFinite, abs(classID.rounded() - classID) < 0.01, classID == targetClassID else { continue }
            let confidence = scalar(output, batch: 0, row: row, field: 4, strides: strides)
            if confidence.isFinite, confidence >= 0, confidence <= 1 {
                maximum = max(maximum, confidence)
            }
        }
        return Double(maximum)
    }

    private static func scalar(_ array: MLMultiArray, batch: Int, row: Int, field: Int, strides: [Int]) -> Float {
        let offset = batch * strides[0] + row * strides[1] + field * strides[2]
        switch array.dataType {
        case .float32:
            return array.dataPointer.assumingMemoryBound(to: Float.self)[offset]
        case .float16:
            let pointer = array.dataPointer.advanced(by: offset * MemoryLayout<Float16>.stride)
                .assumingMemoryBound(to: Float16.self)
            return Float(pointer.pointee)
        case .double:
            return Float(array.dataPointer.assumingMemoryBound(to: Double.self)[offset])
        default:
            return array[[NSNumber(value: batch), NSNumber(value: row), NSNumber(value: field)]].floatValue
        }
    }
}
