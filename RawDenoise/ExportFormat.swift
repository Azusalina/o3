import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case dng
    case tiff

    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
    var details: String {
        switch self {
        case .dng: "16-bit linear DNG · demosaiced RGB"
        case .tiff: "16-bit TIFF · linear Rec.2020 RGB"
        }
    }
}
