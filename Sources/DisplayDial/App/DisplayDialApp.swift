import SwiftUI

@main
struct DisplayDialApp: App {
    @State private var model: MonitorModel
    @State private var shortcuts: BrightnessShortcuts

    init() {
        // Left over from a quit with Settings open, or from `make shot TAB=…`.
        SettingsTab.reset()
        let model = MonitorModel(defaults: .standard)
        let shortcuts = BrightnessShortcuts(model: model)
        shortcuts.apply(enabled: UserDefaults.standard.bool(forKey: PreferenceKey.brightnessShortcuts))
        _model = State(initialValue: model)
        _shortcuts = State(initialValue: shortcuts)
        WindowSnapshot.scheduleIfRequested(model: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(systemName: "sun.max")
                .accessibilityLabel(AppInfo.name)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(shortcuts)
        }
    }
}
