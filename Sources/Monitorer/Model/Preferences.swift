import Foundation

enum PreferenceKey {
    static let selectedDisplay = "selectedDisplay"
    static let useLGInputCodes = "useLGAlt"
    static let presets = "presets"
    static let brightnessShortcuts = "brightnessShortcuts"
    static let pictureDefaults = "pictureDefaults"

    /// Every setting the user chose; `SettingsMigration` carries these across a rename.
    static let all = [selectedDisplay, useLGInputCodes, presets, brightnessShortcuts, pictureDefaults]
}
