import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Environment(MonitorModel.self) private var model
    @Environment(BrightnessShortcuts.self) private var shortcuts
    @AppStorage(PreferenceKey.brightnessShortcuts) private var brightnessShortcuts = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
            }

            Section {
                Toggle(isOn: $brightnessShortcuts) {
                    Text("Adjust brightness from the keyboard")
                    Text("\(BrightnessShortcuts.up.display) brighter, \(BrightnessShortcuts.down.display) dimmer, in steps of \(Int(BrightnessShortcuts.step)).")
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                if shortcuts.unavailable.count == 1, let shortcut = shortcuts.unavailable.first {
                    Text("\(shortcut.display) is already used by the system or another app.")
                        .foregroundStyle(.orange)
                } else if shortcuts.unavailable.count > 1 {
                    Text("\(shortcuts.unavailable.map(\.display).formatted()) are already used by the system or another app.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle("Use LG input codes", isOn: $model.useLGAlt)
            } header: {
                Text("Input Switching")
            } footer: {
                Text("LG monitors only switch inputs with m1ddc's alternate addressing. Turn this off for other brands.")
            }

            Section("Monitor") {
                LabeledContent("Display", value: model.selected?.name ?? String(localized: "None connected"))
                LabeledContent("m1ddc") {
                    if model.ddc == nil {
                        Text("Not installed").foregroundStyle(.orange)
                    } else {
                        Text("Installed")
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
                }
            } footer: {
                Text("DisplayDial runs from the menu bar. While its menu is open, ⌘Q quits it too.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 540)
        .onChange(of: brightnessShortcuts) { shortcuts.apply(enabled: brightnessShortcuts) }
        .alert("Launch at Login", isPresented: Binding(
            get: { loginItemError != nil },
            set: { if !$0 { loginItemError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(loginItemError ?? "")
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    loginItemError = error.localizedDescription
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }
}
