import Foundation
import CoreImage
import CoreML
import ImageIO
import UniformTypeIdentifiers

enum DenoiseError: LocalizedError {
    case unsupportedRAW, missingModel, invalidImage, invalidPrediction, cannotSave
    var errorDescription: String? {
        switch self {
        case .unsupportedRAW: "This RAW format or camera is not supported by the iOS RAW decoder."
        case .missingModel: "The bundled RawForge Core ML model is missing."
        case .invalidImage: "The RAW image could not be decoded, or its dimensions are too large."
        case .invalidPrediction: "RawForge returned an invalid tile."
        case .cannotSave: "The image could not be saved. Check available device storage."
        }
    }
}

actor RawDenoiser {
    private var model: MLModel?
    private let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    private lazy var context = CIContext(options: [
        .workingColorSpace: colorSpace, .cacheIntermediates: false
    ])

    func denoise(source: URL, name: String, folder: URL, format: ExportFormat = .dng,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        if model == nil {
            guard let url = Bundle.main.url(forResource: "RawForgeSuperLight", withExtension: "mlmodelc") else {
                throw DenoiseError.missingModel
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            model = try MLModel(contentsOf: url, configuration: configuration)
        }
        guard let model, let raw = CIRAWFilter(imageURL: source) else { throw DenoiseError.unsupportedRAW }
        defer { context.clearCaches() }

        raw.scaleFactor = 1
        raw.isDraftModeEnabled = false
        raw.exposure = 0
        raw.baselineExposure = 0
        raw.boostAmount = 0
        raw.boostShadowAmount = 0
        raw.shadowBias = 0
        raw.isGamutMappingEnabled = false
        if raw.isLocalToneMapSupported { raw.localToneMapAmount = 0 }
        if raw.isLuminanceNoiseReductionSupported { raw.luminanceNoiseReductionAmount = 0 }
        if raw.isColorNoiseReductionSupported { raw.colorNoiseReductionAmount = 0 }
        if raw.isSharpnessSupported { raw.sharpnessAmount = 0 }
        if raw.isDetailSupported { raw.detailAmount = 0 }
        if raw.isContrastSupported { raw.contrastAmount = 0 }
        if raw.isMoireReductionSupported { raw.moireReductionAmount = 0 }

        guard let decoded = raw.outputImage else { throw DenoiseError.invalidImage }
        let extent = decoded.extent.integral
        guard !extent.isInfinite, !extent.isEmpty,
              extent.width <= 30000, extent.height <= 30000,
              extent.width * extent.height <= 150_000_000 else { throw DenoiseError.invalidImage }
        let width = Int(extent.width), height = Int(extent.height)
        let image = decoded.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let exif = raw.properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let isoValues = exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber]
        let iso = isoValues?.first?.floatValue ?? 100
        let condition = try MLMultiArray(shape: [1, 1], dataType: .float32)
        condition[0] = NSNumber(value: min(max(iso, 1), 65535) / 6400)
        let raster = try TileProcessor.process(image: image, width: width, height: height,
            context: context, colorSpace: colorSpace, progress: progress) { tile in
            let features = try MLDictionaryFeatureProvider(dictionary: [
                "image": MLFeatureValue(multiArray: tile),
                "conditioning": MLFeatureValue(multiArray: condition)
            ])
            let prediction = try model.prediction(from: features)
            guard let output = prediction.featureValue(for: "denoised")?.multiArrayValue else {
                throw DenoiseError.invalidPrediction
            }
            return output
        }
        try Task.checkCancellation()
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let output = uniqueOutput(base: base, folder: folder, format: format)
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).\(format.rawValue)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        switch format {
        case .dng:
            try withExtendedLifetime(raster) {
                try LinearDNGWriter.write(to: temporary, width: width, height: height,
                                          pixels: UnsafePointer(raster.pixels), originalName: name)
            }
        case .tiff:
            try raster.writeTIFF(to: temporary, colorSpace: CGColorSpace(name: CGColorSpace.linearITUR_2020)!)
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: output)
        return output
    }

    private func uniqueOutput(base: String, folder: URL, format: ExportFormat) -> URL {
        var number = 0
        while true {
            let suffix = number == 0 ? "" : "-\(number)"
            let url = folder.appendingPathComponent("\(base)-denoised\(suffix).\(format.rawValue)")
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            number += 1
        }
    }
}
