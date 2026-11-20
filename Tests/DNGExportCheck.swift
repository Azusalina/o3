import Foundation

@main
enum DNGExportCheck {
    static func main() throws {
        let width = 96, height = 129 // Three strips, with a partial last strip.
        var pixels = [UInt16](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    pixels[(y * width + x) * 3 + channel] = UInt16((y * 997 + x * 37 + channel * 10007) % 65536)
                }
            }
        }
        try pixels.withUnsafeBufferPointer { buffer in
            try LinearDNGWriter.write(to: URL(fileURLWithPath: CommandLine.arguments[1]),
                width: width, height: height, pixels: buffer.baseAddress!, originalName: "camera-test.dng")
        }
        print("Wrote DNG fixture: 96 × 129, RGB16, three strips")
    }
}
