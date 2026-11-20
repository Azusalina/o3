import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Darwin

/// Disk-backed RGB16 accumulation avoids keeping a full float photograph on the heap.
final class MappedRaster {
    let width: Int
    let height: Int
    let pixels: UnsafeMutablePointer<UInt16>
    private let byteCount: Int
    private let descriptor: Int32
    private let url: URL

    init(width: Int, height: Int) throws {
        self.width = width
        self.height = height
        byteCount = width * height * 3 * MemoryLayout<UInt16>.size
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".rgb16")
        descriptor = open(url.path, O_RDWR | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw DenoiseError.cannotSave }
        // Allocate real disk blocks before mmap. A sparse ftruncate can SIGBUS later
        // if storage runs out while writing mapped pixels.
        let fd = descriptor
        let total = byteCount
        let zeroes = [UInt8](repeating: 0, count: 1_048_576)
        let allocated = zeroes.withUnsafeBytes { buffer -> Bool in
            var remaining = total
            while remaining > 0 {
                let written = Darwin.write(fd, buffer.baseAddress, min(remaining, buffer.count))
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { return false }
                remaining -= written
            }
            return true
        }
        guard allocated else {
            close(descriptor)
            try? FileManager.default.removeItem(at: url)
            throw DenoiseError.cannotSave
        }
        guard let mapping = mmap(nil, byteCount, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0),
              mapping != MAP_FAILED else {
            close(descriptor)
            try? FileManager.default.removeItem(at: url)
            throw DenoiseError.cannotSave
        }
        pixels = mapping.bindMemory(to: UInt16.self, capacity: width * height * 3)
    }

    deinit {
        munmap(pixels, byteCount)
        close(descriptor)
        try? FileManager.default.removeItem(at: url)
    }

    func writeTIFF(to url: URL, colorSpace: CGColorSpace) throws {
        guard let provider = CGDataProvider(dataInfo: nil, data: pixels, size: byteCount,
                                             releaseData: { _, _, _ in }),
              let image = CGImage(width: width, height: height, bitsPerComponent: 16,
                                  bitsPerPixel: 48, bytesPerRow: width * 6, space: colorSpace,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
                                    .union(.byteOrder16Little),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil)
        else { throw DenoiseError.cannotSave }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw DenoiseError.cannotSave }
        withExtendedLifetime(self) {}
    }
}
