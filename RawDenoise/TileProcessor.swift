import Foundation
import CoreImage
import CoreML

enum TileProcessor {
    static func process(image: CIImage, width: Int, height: Int, context: CIContext, colorSpace: CGColorSpace, progress: (Double) -> Void, predict: (MLMultiArray) throws -> MLMultiArray) throws -> MappedRaster {
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
                    // Bounds use CI's bottom-left coordinates, but render(toBitmap:)
                    // returns top-first scanlines. Reversing those scanlines would
                    // flip each tile separately and blur/scramble overlap regions.
                    rgba.withUnsafeMutableBytes { bytes in
                        context.render(image, toBitmap: bytes.baseAddress!, rowBytes: 256 * 16,
                                       bounds: CGRect(x: x, y: height - y - validHeight,
                                                      width: validWidth, height: validHeight),
                                       format: .RGBAf, colorSpace: colorSpace)
                    }
                    let input = tile.dataPointer.assumingMemoryBound(to: Float.self)
                    for row in 0..<256 {
                        let sourceRow = min(row, validHeight - 1)
                        for column in 0..<256 {
                            let sourceColumn = min(column, validWidth - 1)
                            for channel in 0..<3 {
                                let value = rgba[(sourceRow * 256 + sourceColumn) * 4 + channel]
                                guard value.isFinite else { throw DenoiseError.invalidImage }
                                input[channel * 256 * 256 + row * 256 + column] = min(max(value, 0), 1)
                            }
                        }
                    }
                    let output = try predict(tile)
                    guard output.shape.map(\.intValue) == [1, 3, 256, 256], output.dataType == .float32 else { throw DenoiseError.invalidPrediction }
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
        return raster
    }
}
