import Foundation

enum DenoiseModel: String, CaseIterable, Identifiable, Sendable {
    case general, light, superLight = "superlight", heavy

    var id: String { rawValue }
    var label: String {
        switch self {
        case .general: "General"
        case .light: "Light"
        case .superLight: "Super Light"
        case .heavy: "Heavy"
        }
    }
    var resourceName: String {
        switch self {
        case .general: "RawForgeGeneral"
        case .light: "RawForgeLight"
        case .superLight: "RawForgeSuperLight"
        case .heavy: "RawForgeHeavy"
        }
    }
}
