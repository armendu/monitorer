import SwiftUI

struct PresetsSettings: View {
    @Environment(MonitorModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            DefaultsSection()

            Section {
                if model.presets.isEmpty {
                    Text("No presets")
                        .foregroundStyle(.secondary)
                }
                ForEach($model.presets) { $preset in
                    HStack {
                        Image(systemName: preset.symbol)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        TextField("Name", text: $preset.name)
                            .labelsHidden()
                        Text(preset.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Button("Delete \u{201C}\(preset.name)\u{201D}", systemImage: "minus.circle.fill", role: .destructive) {
                            model.delete(preset)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("To add a preset, choose Save Current as Preset… in the menu bar.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 480)
    }
}
