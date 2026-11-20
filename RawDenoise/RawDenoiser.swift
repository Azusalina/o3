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
        case .cannotSave: "The TIFF could not be saved. Check available device storage."
        }
    }
}

actor RawDenoiser {
    private var model: MLModel?
    private let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)!
    private lazy var context = CIContext(options: [
        .workingColorSpace: colorSpace, .cacheIntermediates: false
    ])

    func denoise(source: URL, name: String, folder: URL,
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
        let tile = try MLMultiArray(shape: [1, 3, 256, 256], dataType: .float32)
        let xs = TileLayout.origins(length: width), ys = TileLayout.origins(length: height)
        let xNorm = TileLayout.normalization(length: width, origins: xs)
        let yNorm = TileLayout.normalization(length: height, origins: ys)
        let raster = try MappedRaster(width: width, height: height)
        var completed = 0
        for y in ys {
            for x in xs {
                try Task.checkCancellation()
                try autoreleasepool {
                    let validWidth = min(256, width - x), validHeight = min(256, height - y)
                    var rgba = [Float](repeating: 0, count: 256 * 256 * 4)
                    // CI coordinates run upwards. Reverse each rendered tile into top-first tensor rows.
                    rgba.withUnsafeMutableBytes { bytes in
                        context.render(image, toBitmap: bytes.baseAddress!, rowBytes: 256 * 16,
                                       bounds: CGRect(x: x, y: height - y - validHeight,
                                                      width: validWidth, height: validHeight),
                                       format: .RGBAf, colorSpace: colorSpace)
                    }
                    let input = tile.dataPointer.assumingMemoryBound(to: Float.self)
                    for row in 0..<256 {
                        let sourceRow = validHeight - 1 - min(row, validHeight - 1)
                        for column in 0..<256 {
                            let sourceColumn = min(column, validWidth - 1)
                            for channel in 0..<3 {
                                let value = rgba[(sourceRow * 256 + sourceColumn) * 4 + channel]
                                guard value.isFinite else { throw DenoiseError.invalidImage }
                                input[channel * 256 * 256 + row * 256 + column] = min(max(value, 0), 1)
                            }
                        }
                    }
                    let features = try MLDictionaryFeatureProvider(dictionary: [
                        "image": MLFeatureValue(multiArray: tile),
                        "conditioning": MLFeatureValue(multiArray: condition)
                    ])
                    let prediction = try model.prediction(from: features)
                    guard let output = prediction.featureValue(for: "denoised")?.multiArrayValue,
                          output.shape.map(\.intValue) == [1, 3, 256, 256], output.dataType == .float32 else {
                        throw DenoiseError.invalidPrediction
                    }
                    let values = output.dataPointer.assumingMemoryBound(to: Float.self)
                    let strides = output.strides.map(\.intValue)
                    for row in 0..<validHeight {
                        for column in 0..<validWidth {
                            let weight = TileLayout.weight(row) * TileLayout.weight(column)
                                / (yNorm[y + row] * xNorm[x + column])
                            for channel in 0..<3 {
                                let value = values[channel * strides[1] + row * strides[2] + column * strides[3]]
                                guard value.isFinite else { throw DenoiseError.invalidPrediction }
                                let index = ((y + row) * width + x + column) * 3 + channel
                                let contribution = min(max(value, 0), 1) * weight * 65535
                                raster.pixels[index] = UInt16(min(65535, Float(raster.pixels[index]) + contribution.rounded()))
                            }
                        }
                    }
                }
                completed += 1
                progress(Double(completed) / Double(xs.count * ys.count))
            }
        }
        try Task.checkCancellation()
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let output = uniqueOutput(base: base, folder: folder)
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tiff")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try raster.writeTIFF(to: temporary, colorSpace: CGColorSpace(name: CGColorSpace.linearITUR_2020)!)
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: output)
        return output
    }

    private func uniqueOutput(base: String, folder: URL) -> URL {
        var number = 0
        while true {
            let suffix = number == 0 ? "" : "-\(number)"
            let url = folder.appendingPathComponent("\(base)-denoised\(suffix).tiff")
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            number += 1
        }
    }
}
