import SwiftUI

/// Drawn like the items in the system's own panels (Wi-Fi, Bluetooth):
/// `.borderless` draws them grey with no hover, so they look disabled.
struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuItem(configuration: configuration)
    }

    private struct MenuItem: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        private var highlight: AnyShapeStyle {
            guard isEnabled else { return AnyShapeStyle(.clear) }
            if configuration.isPressed { return AnyShapeStyle(.tertiary) }
            return isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)
        }

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(highlight, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                // Into the margin: the text lines up with the rest of the panel, the highlight spans the row.
                .padding(.horizontal, -8)
                .onHover { isHovering = $0 }
        }
    }
}

struct MenuItemLabel: View {
    let title: LocalizedStringKey
    let shortcut: String

    init(_ title: LocalizedStringKey, shortcut: String) {
        self.title = title
        self.shortcut = shortcut
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: shortcut).foregroundStyle(.secondary)
        }
    }
}

/// Control Center's round icons: Liquid Glass when off, the accent colour when on.
/// Tinted glass is avoided because neighbouring glass shapes blend into each other.
struct CircleIconLabelStyle: LabelStyle {
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Group {
                if isOn {
                    icon(configuration)
                        .foregroundStyle(.white)
                        .background(.tint, in: .circle)
                } else {
                    icon(configuration)
                        .glassEffect(.regular, in: .circle)
                }
            }
            .accessibilityHidden(true)
            configuration.title
        }
    }

    private func icon(_ configuration: Configuration) -> some View {
        configuration.icon
            .font(.system(size: 12, weight: .medium))
            .frame(width: 26, height: 26)
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)
            .accessibilityAddTraits(.isHeader)
    }
}
