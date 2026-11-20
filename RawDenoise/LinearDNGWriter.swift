import Foundation

/// Uncompressed, little-endian DNG 1.4 with a LinearRaw RGB IFD.
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
              UInt64(width) * UInt64(height) * 6 < UInt64(UInt32.max) - 65536 else {
            throw WriteError.invalidDimensions
        }
        let rowsPerStrip = 64
        let stripCount = (height + rowsPerStrip - 1) / rowsPerStrip
        let counts = (0..<stripCount).map { UInt32(min(rowsPerStrip, height - $0 * rowsPerStrip) * width * 6) }

        func entries(offsets: [UInt32]) -> [Entry] {
            [
                longs(254, [0]), longs(256, [UInt32(width)]), longs(257, [UInt32(height)]),
                shorts(258, [16, 16, 16]), shorts(259, [1]), shorts(262, [34892]),
                ascii(271, "RawDenoise"), ascii(272, "Linear Rec.2020"),
                longs(273, offsets), shorts(274, [1]), shorts(277, [3]),
                longs(278, [UInt32(rowsPerStrip)]), longs(279, counts), shorts(284, [1]),
                ascii(305, "RawDenoise"), shorts(339, [1, 1, 1]),
                bytes(50706, [1, 4, 0, 0]), bytes(50707, [1, 3, 0, 0]),
                ascii(50708, "RawDenoise Linear Rec2020"),
                shorts(50713, [1, 1]), rationals(50714, [0, 0, 0]), longs(50717, [65535, 65535, 65535]),
                rationals(50718, [1, 1]), longs(50719, [0, 0]), longs(50720, [UInt32(width), UInt32(height)]),
                // XYZ under D65 -> linear Rec.2020. DNG's calibration illuminant
                // identifies the reference white; readers perform their own adaptation.
                signedRationals(50721, [1.716651188, -0.355670784, -0.253366281,
                                       -0.666684352, 1.616481237, 0.015768546,
                                       0.017639857, -0.042770613, 0.942103121]),
                rationals(50728, [1, 1, 1]), signedRationals(50730, [0]),
                rationals(50731, [1]), rationals(50732, [0]), shorts(50778, [21]),
                ascii(50827, originalName), longs(50829, [0, 0, UInt32(height), UInt32(width)]),
                rationals(50935, [1]), ascii(50936, "Linear Rec.2020 D65"),
                floats(50940, [0, 0, 1, 1])
            ].sorted { $0.tag < $1.tag }
        }

        let placeholder = encode(entries(offsets: [UInt32](repeating: 0, count: stripCount)))
        var offset = UInt32(placeholder.count)
        let offsets = counts.map { count -> UInt32 in
            defer { offset += count }
            return offset
        }
        let header = encode(entries(offsets: offsets))
        precondition(header.count == placeholder.count)
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

    private static func encode(_ entries: [Entry]) -> Data {
        var result = Data([0x49, 0x49, 42, 0, 8, 0, 0, 0])
        result.appendLE(UInt16(entries.count))
        let dataStart = 8 + 2 + entries.count * 12 + 4
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
        result.appendLE(UInt32(0)) // No next IFD; this is the full-resolution raw IFD.
        result.append(extra)
        while result.count % 4 != 0 { result.append(0) }
        return result
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
