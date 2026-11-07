import SwiftUI

struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppInfo.name)
                            .font(.title2.weight(.semibold))
                        Text(AppInfo.version)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Control your external monitor from the menu bar.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Created by") {
                    Link(AppInfo.creator, destination: AppInfo.creatorURL)
                }
                LabeledContent("Built on") {
                    Link("m1ddc", destination: AppInfo.m1ddcURL)
                }
            } footer: {
                Text("Monitorer talks to the monitor over DDC/CI through m1ddc, which does the actual work.")
            }

            Section {
                EmptyView()
            } footer: {
                Text("\(AppInfo.copyright) Not affiliated with Apple or LG.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 340)
    }
}
