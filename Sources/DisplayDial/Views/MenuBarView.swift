import SwiftUI

/// The menu bar panel, laid out like the system's own Sound and Display panels.
struct MenuBarView: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @State private var isNamingPreset = false
    @State private var confirmingInput: InputSource?
    @State private var newPresetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Failures surface here: the panel is the only place DisplayDial has.
            if let error = model.errorMessage {
                HStack(alignment: .firstTextBaseline) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Dismiss", systemImage: "xmark.circle.fill") { model.errorMessage = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                Divider()
            }

            header

            if model.ddc == nil {
                notInstalled
            } else if model.displays.isEmpty {
                Text("No external display found. Connect it over USB-C or DisplayPort, or the Mac's HDMI port, and turn on DDC/CI in the monitor's menu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                picture
                if model.supportsVolume {
                    Divider()
                    sound
                }
                Divider()
                inputs
                Divider()
                presets
            }

            Divider()
            // A Button rather than SettingsLink, which can't close the panel or activate the app.
            Button(action: showSettings) { MenuItemLabel("Settings…", shortcut: "⌘,") }
                .keyboardShortcut(",")
        }
        .buttonStyle(MenuItemButtonStyle())
        .padding(.horizontal, 12)
        .padding(.top, 12)
        // System menus end about 5 points under their last item's highlight; the full 12 on
        // top of the row's own padding left a visible gap under Settings.
        .padding(.bottom, 5)
        .frame(width: 280)
        .task { await model.refresh() }
        // There's no app menu to carry ⌘Q, so the panel does while it's open.
        .background {
            Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .hidden()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            if model.displays.count > 1 {
                Picker("Display", selection: Binding(
                    get: { model.selectedID ?? "" },
                    set: { model.select($0) }
                )) {
                    ForEach(model.displays) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
            } else {
                Text(model.selected?.name ?? AppInfo.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
            // Overlaid on a fixed frame so the header keeps its height while loading.
            Color.clear
                .frame(width: 16, height: 16)
                .overlay {
                    if model.isLoading { ProgressView().controlSize(.small) }
                }
        }
    }

    private var picture: some View {
        VStack(spacing: 8) {
            slider(.luminance, title: "Brightness", minimumSymbol: "sun.min", maximumSymbol: "sun.max")
            slider(.contrast, title: "Contrast", minimumSymbol: "circle.lefthalf.filled", maximumSymbol: "circle.lefthalf.filled")
            if let defaults = model.selectedDefaults {
                Button(action: model.restoreDefaults) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .disabled(model.isAtDefaults)
                .help("Back to brightness \(defaults.brightness) and contrast \(defaults.contrast). Change them in Settings › Presets.")
                .accessibilityLabel("Reset brightness and contrast")
            }
        }
    }

    private var sound: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { !model.isMuted }, set: { model.setMuted(!$0) })) {
                Text("Sound").font(.headline)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(model.isMuted ? "Unmute" : "Mute")
            slider(.volume, title: "Volume", minimumSymbol: "speaker.fill", maximumSymbol: "speaker.wave.3.fill")
                .disabled(model.isMuted)
        }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader("Input")
            ForEach(InputSource.allCases) { input in
                Button {
                    // Switching away can blank this Mac's screen, with only the monitor's own
                    // buttons to get back, so it asks first rather than acting on a misclick.
                    confirmingInput = input == model.currentInput ? nil : input
                } label: {
                    Label(input.title, systemImage: input.symbol)
                }
                .labelStyle(CircleIconLabelStyle(isOn: model.currentInput == input))
                .accessibilityAddTraits(model.currentInput == input ? .isSelected : [])
            }
            if let input = confirmingInput {
                confirmation(for: input)
            }
        }
    }

    private func confirmation(for input: InputSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch to \(input.title)? If this Mac is connected only through \(model.currentInput?.title ?? String(localized: "the current input")), its screen goes dark, and you'll need the monitor's own buttons to switch back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { confirmingInput = nil }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                Button("Switch") {
                    model.switchInput(input)
                    confirmingInput = nil
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader("Presets")
            ForEach(model.presets) { preset in
                Button { model.apply(preset) } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(preset.name)
                            Text(preset.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: preset.symbol)
                    }
                }
                .labelStyle(CircleIconLabelStyle())
                .contextMenu {
                    Button("Delete \u{201C}\(preset.name)\u{201D}", role: .destructive) { model.delete(preset) }
                }
            }

            if isNamingPreset {
                TextField("Preset Name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(savePreset)
                    .onExitCommand { isNamingPreset = false }
                    .padding(.vertical, 2)
            } else {
                Button("Save Current as Preset…") {
                    newPresetName = ""
                    isNamingPreset = true
                }
                // Until the monitor has been read, the sliders show placeholders, not its values.
                .disabled(!model.hasReadings)
            }
        }
    }

    private var notInstalled: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DisplayDial needs m1ddc to talk to your monitor. Install it with Homebrew, then reopen this menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(M1DDC.installCommand, forType: .string)
            } label: {
                Label("Copy \u{201C}\(M1DDC.installCommand)\u{201D}", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK: Helpers

    private func slider(_ control: Control, title: LocalizedStringKey, minimumSymbol: String, maximumSymbol: String) -> some View {
        let value = model.value(control)
        let percent = Int((value / model.maximum(control) * 100).rounded())
        return Slider(
            value: Binding(get: { value }, set: { model.set(control, to: $0) }),
            in: 0...model.maximum(control)
        ) {
            Text(title)
        } minimumValueLabel: {
            Image(systemName: minimumSymbol).imageScale(.small)
        } maximumValueLabel: {
            Image(systemName: maximumSymbol).imageScale(.medium)
        }
        .labelsHidden()
        .foregroundStyle(.secondary)
        .help(Text("\(Text(title)) \(percent)%"))
        .accessibilityValue("\(percent)%")
    }

    private func showSettings() {
        // Closes the panel; measured on macOS 27, it's hidden before Settings opens.
        dismiss()
        // A menu bar app isn't active, so Settings would open behind other windows.
        NSApp.activate()
        openSettings()
    }

    private func savePreset() {
        model.saveCurrentAsPreset(named: newPresetName)
        isNamingPreset = false
    }
}
