import SwiftUI

/// Stored only so `make shot` can pick a tab before opening Settings; reset when
/// Settings closes, so plain ⌘, always lands on General.
enum SettingsTab: String {
    case general, presets, about
    // A snapshot copy shares the owner's defaults: a key of its own keeps it from
    // moving their open Settings window to another tab.
    static let storageKey = RunMode.isReadOnly ? "snapshotSettingsTab" : "settingsTab"

    static func reset() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

struct SettingsView: View {
    @AppStorage(SettingsTab.storageKey) private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            PresetsSettings()
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.presets)
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 500)
        // Opened from the menu bar, the app isn't active yet.
        .onAppear { NSApp.activate() }
        .onDisappear(perform: SettingsTab.reset)
    }
}
