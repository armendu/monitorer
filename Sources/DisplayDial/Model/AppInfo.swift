import Foundation

enum AppInfo {
    static let name = "DisplayDial"
    static let creator = "Armend Ukëhaxhaj"
    static let creatorURL = URL(string: "https://github.com/armendu")!
    static let m1ddcURL = URL(string: "https://github.com/waydabber/m1ddc")!

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static var version: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        // build.sh stamps one number into both; only show the build when it differs.
        if build == shortVersion { return String(localized: "Version \(shortVersion)") }
        return String(localized: "Version \(shortVersion) (\(build))")
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    }
}
