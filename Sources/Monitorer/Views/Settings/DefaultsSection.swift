import SwiftUI

/// The brightness and contrast that Restore Defaults goes back to, for the selected monitor.
struct DefaultsSection: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        Section {
            if let defaults = model.selectedDefaults {
                row("Brightness", value: defaults.brightness, maximum: model.maximum(.luminance)) {
                    model.setDefaults(PictureDefaults(brightness: $0, contrast: defaults.contrast))
                }
                row("Contrast", value: defaults.contrast, maximum: model.maximum(.contrast)) {
                    model.setDefaults(PictureDefaults(brightness: defaults.brightness, contrast: $0))
                }
                HStack {
                    Spacer()
                    Button("Use Current Values", action: model.useCurrentValuesAsDefaults)
                        .disabled(model.isAtDefaults || !model.hasReadings)
                }
            } else {
                Text("Connect a monitor to set its defaults.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Default Brightness & Contrast")
        } footer: {
            Text("Reset in the menu bar goes back to these. They start as the values Monitorer first read from this monitor; the monitor's own factory reset isn't available over m1ddc.")
        }
    }

    private func row(_ title: LocalizedStringKey, value: Int, maximum: Double, set: @escaping (Int) -> Void) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: Binding(get: { Double(value) }, set: { set(Int($0.rounded())) }), in: 0...maximum)
                    .labelsHidden()
                Text(value, format: .number)
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }
            .frame(width: 220)
        }
    }
}
