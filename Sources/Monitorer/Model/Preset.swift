import Foundation

enum InputSource: String, CaseIterable, Identifiable, Codable {
    case displayPort = "DisplayPort"
    case hdmi1 = "HDMI 1"
    case hdmi2 = "HDMI 2"

    var id: String { rawValue }

    /// Matches a code read back from the monitor; LGs report the standard code even
    /// though they need the alternate one to switch.
    init?(code: Int) {
        guard let input = Self.allCases.first(where: { $0.code(lgAlt: false) == code || $0.code(lgAlt: true) == code }) else {
            return nil
        }
        self = input
    }

    /// LG monitors ignore the standard VCP 0x60 codes and need m1ddc's `input-alt` addressing.
    func code(lgAlt: Bool) -> Int {
        switch self {
        case .displayPort: lgAlt ? 208 : 15
        case .hdmi1: lgAlt ? 144 : 17
        case .hdmi2: lgAlt ? 145 : 18
        }
    }
}

struct PictureDefaults: Codable, Hashable {
    var brightness: Int
    var contrast: Int
}

struct Preset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var brightness: Int
    var contrast: Int
    var volume: Int?

    static let defaults = [
        Preset(name: "Day", brightness: 70, contrast: 70),
        Preset(name: "Night", brightness: 20, contrast: 60),
    ]
}
