import Foundation
import CoreImage
import CoreML

@main
enum TileGeometryCheck {
    static func main() throws {
        let space = CGColorSpace(name: CGColorSpace.linearITUR_2020)!
        for (width, height) in [(603, 417), (97, 83), (257, 449)] {
            var pixels = [UInt16](repeating: 0, count: width * height * 3)
            for y in 0..<height {
                for x in 0..<width {
                    pixels[(y * width + x) * 3] = UInt16((y * 133 + x * 17) % 60000)
                    pixels[(y * width + x) * 3 + 1] = UInt16(((x / 7 + y / 11) % 2) * 40000 + 1000)
                    pixels[(y * width + x) * 3 + 2] = UInt16((x * 83 + y * 19) % 60000)
                }
            }
            let data = pixels.withUnsafeBytes { Data($0) }
            let provider = CGDataProvider(data: data as CFData)!
            let cg = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 48,
                bytesPerRow: width * 6, space: space, bitmapInfo: .byteOrder16Little,
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            let raster = try TileProcessor.process(image: CIImage(cgImage: cg), width: width,
                height: height, context: CIContext(options: [.workingColorSpace: space]),
                colorSpace: space, progress: { _ in }, predict: { $0 })
            var maxError = 0
            for index in pixels.indices { maxError = max(maxError, abs(Int(pixels[index]) - Int(raster.pixels[index]))) }
            print("Identity tile reconstruction \(width)×\(height): maximum RGB16 error \(maxError)")
            guard maxError <= 6 else {
                throw NSError(domain: "TileGeometry", code: maxError,
                    userInfo: [NSLocalizedDescriptionKey: "Tile packing/stitching changes geometry without denoising"])
            }
        }
    }
}
