import Foundation
import CoreImage
import ImageIO

@main
enum AppleDNGCheck {
    static func main() throws {
        let width = 512, height = 513
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let pixels = [UInt16](repeating: 12000, count: width * height * 3)
        try pixels.withUnsafeBufferPointer { buffer in
            try LinearDNGWriter.write(to: url, width: width, height: height,
                                     pixels: buffer.baseAddress!, originalName: "apple-check.dng")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rendered = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "DNGValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apple ImageIO could not decode DNG"])
        }
        // ImageIO may expose the developed main image at index zero rather than
        // the thumbnail IFD. The independent TIFF test verifies the thumbnail.
        print("Apple ImageIO decoded DNG: \(rendered.width) × \(rendered.height)")
        guard let filter = CIRAWFilter(imageURL: url), let image = filter.outputImage else {
            throw NSError(domain: "DNGValidation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Apple RAW decoder rejected DNG"])
        }
        print("Apple DNG native size: \(filter.nativeSize); output extent: \(image.extent)")
        guard image.extent.width == CGFloat(width), image.extent.height == CGFloat(height),
              CIContext().createCGImage(image, from: image.extent) != nil else {
            throw NSError(domain: "DNGValidation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Apple RAW decoder did not render full-resolution DNG"])
        }
        print("Apple DNG check passed: ImageIO decoding and full-resolution RAW rendering")
    }
}
