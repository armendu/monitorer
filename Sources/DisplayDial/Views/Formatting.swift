import Foundation

extension InputSource {
    var title: String {
        switch self {
        case .displayPort: String(localized: "DisplayPort")
        case .hdmi1: String(localized: "HDMI 1")
        case .hdmi2: String(localized: "HDMI 2")
        }
    }

    var symbol: String {
        switch self {
        case .displayPort: "display"
        case .hdmi1, .hdmi2: "tv"
        }
    }
}

extension Preset {
    /// Picked from the name, since presets don't store an icon of their own.
    var symbol: String {
        let name = name.lowercased()
        if name.contains("night") || name.contains("dark") { return "moon" }
        if name.contains("day") || name.contains("bright") { return "sun.max" }
        if name.contains("game") { return "gamecontroller" }
        if name.contains("movie") || name.contains("film") { return "film" }
        return "slider.horizontal.3"
    }

    var summary: String {
        if let volume {
            return String(localized: "Brightness \(brightness) · Contrast \(contrast) · Volume \(volume)")
        }
        return String(localized: "Brightness \(brightness) · Contrast \(contrast)")
    }
}
