import Foundation

/// Before 1.5.0 the app was called DisplayDial, and its settings live under that bundle ID.
/// Copy them once, so presets, monitor defaults and shortcuts survive the rename.
enum SettingsMigration {
    static let oldDomain = "com.armend.DisplayDial"
    static let doneKey = "migratedFromDisplayDial"

    static func run(
        into defaults: UserDefaults,
        from old: [String: Any]? = UserDefaults.standard.persistentDomain(forName: oldDomain)
    ) {
        guard !defaults.bool(forKey: doneKey) else { return }
        // Something set since the rename wins over the old value.
        for key in PreferenceKey.all where defaults.object(forKey: key) == nil {
            if let value = old?[key] { defaults.set(value, forKey: key) }
        }
        defaults.set(true, forKey: doneKey)
    }
}
