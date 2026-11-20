import Foundation

/// Uncompressed, little-endian DNG 1.4 with an sRGB preview and LinearRaw RGB SubIFD.
/// The pixels already contain white-balanced linear Rec.2020, so the profile describes
/// those primaries instead of reusing the source camera's sensor color matrices.
enum LinearDNGWriter {
    enum WriteError: LocalizedError {
        case invalidDimensions, cannotCreate
        var errorDescription: String? {
            switch self {
            case .invalidDimensions: "The image is too large for DNG export."
            case .cannotCreate: "Could not create the DNG. Check available storage."
            }
        }
    }

    private struct Entry {
        let tag: UInt16
        let type: UInt16
        let count: UInt32
        let data: Data
    }

    static func write(to url: URL, width: Int, height: Int,
                      pixels: UnsafePointer<UInt16>, originalName: String) throws {
        guard width > 0, height > 0, width <= 30000, height <= 30000,
              UInt64(width) * UInt64(height) * 6 < UInt64(UInt32.max) - 1_048_576 else {
            throw WriteError.invalidDimensions
        }
        let rowsPerStrip = 64
        let stripCount = (height + rowsPerStrip - 1) / rowsPerStrip
        let counts = (0..<stripCount).map { UInt32(min(rowsPerStrip, height - $0 * rowsPerStrip) * width * 6) }

        let preview = makePreview(width: width, height: height, pixels: pixels)
        func previewEntries(offset: UInt32, rawIFD: UInt32) -> [Entry] {
            [
                longs(254, [1]), longs(256, [UInt32(preview.width)]), longs(257, [UInt32(preview.height)]),
                shorts(258, [8, 8, 8]), shorts(259, [1]), shorts(262, [2]),
                ascii(271, "RawDenoise"), ascii(272, "Linear Rec.2020"),
                longs(273, [offset]), shorts(274, [1]), shorts(277, [3]),
                longs(278, [UInt32(preview.height)]), longs(279, [UInt32(preview.data.count)]),
                shorts(284, [1]), ascii(305, "RawDenoise"), longs(330, [rawIFD]),
                bytes(50706, [1, 4, 0, 0]), bytes(50707, [1, 3, 0, 0]),
                ascii(50708, "RawDenoise Linear Rec2020"),
                // XYZ under D65 -> linear Rec.2020. DNG's calibration illuminant
                // identifies the reference white; readers perform their own adaptation.
                signedRationals(50721, [1.716651188, -0.355670784, -0.253366281,
                                       -0.666684352, 1.616481237, 0.015768546,
                                       0.017639857, -0.042770613, 0.942103121]),
                rationals(50728, [1, 1, 1]), signedRationals(50730, [0]),
                rationals(50731, [1]), rationals(50732, [0]), shorts(50778, [21]),
                ascii(50827, originalName), ascii(50936, "Linear Rec.2020 D65"),
                floats(50940, [0, 0, 1, 1]), longs(50970, [2])
            ].sorted { $0.tag < $1.tag }
        }

        func rawEntries(offsets: [UInt32]) -> [Entry] {
            [
                longs(254, [0]), longs(256, [UInt32(width)]), longs(257, [UInt32(height)]),
                shorts(258, [16, 16, 16]), shorts(259, [1]), shorts(262, [34892]),
                longs(273, offsets), shorts(274, [1]), shorts(277, [3]),
                longs(278, [UInt32(rowsPerStrip)]), longs(279, counts), shorts(284, [1]),
                shorts(339, [1, 1, 1]), shorts(50713, [1, 1]), rationals(50714, [0, 0, 0]),
                longs(50717, [65535, 65535, 65535]), rationals(50718, [1, 1]),
                longs(50719, [0, 0]), longs(50720, [UInt32(width), UInt32(height)]),
                longs(50829, [0, 0, UInt32(height), UInt32(width)]), rationals(50935, [1])
            ].sorted { $0.tag < $1.tag }
        }

        let rootPlaceholder = encode(previewEntries(offset: 0, rawIFD: 0), at: 8)
        let rawIFD = UInt32(8 + rootPlaceholder.count)
        let rawPlaceholder = encode(rawEntries(offsets: [UInt32](repeating: 0, count: stripCount)), at: rawIFD)
        let previewOffset = rawIFD + UInt32(rawPlaceholder.count)
        let padding = (4 - preview.data.count % 4) % 4
        let pixelOffset = previewOffset + UInt32(preview.data.count + padding)
        var offset = pixelOffset
        let offsets = counts.map { count -> UInt32 in
            defer { offset += count }
            return offset
        }
        var header = Data([0x49, 0x49, 42, 0, 8, 0, 0, 0])
        header.append(encode(previewEntries(offset: previewOffset, rawIFD: rawIFD), at: 8))
        header.append(encode(rawEntries(offsets: offsets), at: rawIFD))
        header.append(preview.data)
        header.append(Data(repeating: 0, count: padding))
        precondition(header.count == Int(pixelOffset))
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw WriteError.cannotCreate }
        var complete = false
        let handle = try FileHandle(forWritingTo: url)
        defer {
            try? handle.close()
            if !complete { try? FileManager.default.removeItem(at: url) }
        }
        try handle.write(contentsOf: header)
        var sampleOffset = 0
        for count in counts {
            try Task.checkCancellation()
            let data = Data(bytes: pixels.advanced(by: sampleOffset), count: Int(count))
            try handle.write(contentsOf: data)
            sampleOffset += Int(count) / 2
        }
        try handle.synchronize()
        complete = true
    }

    private static func encode(_ entries: [Entry], at offset: UInt32) -> Data {
        var result = Data()
        result.appendLE(UInt16(entries.count))
        let dataStart = Int(offset) + 2 + entries.count * 12 + 4
        var extra = Data()
        for entry in entries {
            result.appendLE(entry.tag)
            result.appendLE(entry.type)
            result.appendLE(entry.count)
            if entry.data.count <= 4 {
                result.append(entry.data)
                result.append(Data(repeating: 0, count: 4 - entry.data.count))
            } else {
                while (dataStart + extra.count) % 4 != 0 { extra.append(0) }
                result.appendLE(UInt32(dataStart + extra.count))
                extra.append(entry.data)
            }
        }
        result.appendLE(UInt32(0)) // Raw data is reached through SubIFDs, not an IFD chain.
        result.append(extra)
        while (Int(offset) + result.count) % 4 != 0 { result.append(0) }
        return result
    }

    private static func makePreview(width: Int, height: Int, pixels: UnsafePointer<UInt16>)
        -> (width: Int, height: Int, data: Data) {
        let edge = max(1, min(256, max(width, height) / 2))
        let scale = Double(edge) / Double(max(width, height))
        let w = max(1, Int(Double(width) * scale)), h = max(1, Int(Double(height) * scale))
        var data = Data(capacity: w * h * 3)
        func encode(_ linear: Double) -> UInt8 {
            let value = min(1, max(0, linear))
            let encoded = value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
            return UInt8((encoded * 255).rounded())
        }
        for y in 0..<h {
            for x in 0..<w {
                let index = ((y * height / h) * width + x * width / w) * 3
                let r = Double(pixels[index]) / 65535
                let g = Double(pixels[index + 1]) / 65535
                let b = Double(pixels[index + 2]) / 65535
                // Linear Rec.2020 -> linear sRGB, then the sRGB transfer function.
                data.append(encode(1.660491 * r - 0.587641 * g - 0.072850 * b))
                data.append(encode(-0.124550 * r + 1.132900 * g - 0.008349 * b))
                data.append(encode(-0.018151 * r - 0.100579 * g + 1.118730 * b))
            }
        }
        return (w, h, data)
    }

    private static func bytes(_ tag: UInt16, _ values: [UInt8]) -> Entry {
        Entry(tag: tag, type: 1, count: UInt32(values.count), data: Data(values))
    }
    private static func ascii(_ tag: UInt16, _ text: String) -> Entry {
        // TIFF ASCII is 7-bit; retain a readable, null-terminated original name.
        let values = text.utf8.map { $0 < 128 && $0 > 0 ? $0 : UInt8(63) } + [0]
        return Entry(tag: tag, type: 2, count: UInt32(values.count), data: Data(values))
    }
    private static func shorts(_ tag: UInt16, _ values: [UInt16]) -> Entry {
        var data = Data()
        for value in values { data.appendLE(value) }
        return Entry(tag: tag, type: 3, count: UInt32(values.count), data: data)
    }
    private static func longs(_ tag: UInt16, _ values: [UInt32]) -> Entry {
        var data = Data()
        for value in values { data.appendLE(value) }
        return Entry(tag: tag, type: 4, count: UInt32(values.count), data: data)
    }
    private static func rationals(_ tag: UInt16, _ values: [UInt32]) -> Entry {
        var data = Data()
        for value in values { data.appendLE(value); data.appendLE(UInt32(1)) }
        return Entry(tag: tag, type: 5, count: UInt32(values.count), data: data)
    }
    private static func signedRationals(_ tag: UInt16, _ values: [Double]) -> Entry {
        var data = Data()
        for value in values {
            data.appendLE(Int32((value * 1_000_000).rounded()))
            data.appendLE(Int32(1_000_000))
        }
        return Entry(tag: tag, type: 10, count: UInt32(values.count), data: data)
    }
    private static func floats(_ tag: UInt16, _ values: [Float]) -> Entry {
        var data = Data()
        for value in values { data.appendLE(value.bitPattern) }
        return Entry(tag: tag, type: 11, count: UInt32(values.count), data: data)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
