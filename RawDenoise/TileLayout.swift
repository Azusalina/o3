import Foundation

enum TileLayout {
    static let size = 256
    static let stride = 192

    static func origins(length: Int) -> [Int] {
        guard length > size else { return [0] }
        var result = Array(Swift.stride(from: 0, through: length - size, by: stride))
        if result.last != length - size { result.append(length - size) }
        return result
    }

    static func weight(_ offset: Int) -> Float {
        // Positive endpoints avoid zero weights on the outermost image edges.
        Float(min(offset + 1, size - offset, 64)) / 64
    }

    static func normalization(length: Int, origins: [Int]) -> [Float] {
        var sums = [Float](repeating: 0, count: length)
        for start in origins {
            for offset in 0..<min(size, length - start) { sums[start + offset] += weight(offset) }
        }
        return sums
    }
}
