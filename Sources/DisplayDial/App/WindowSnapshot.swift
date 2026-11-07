import AppKit
import SwiftUI

/// Writes PNGs of the app's own windows for `make shot`: `screencapture` needs
/// Screen Recording permission, but a window can always render itself.
///
///   DISPLAYDIAL_SNAPSHOT_DIR   where to write the PNGs
///   DISPLAYDIAL_SETTINGS_TAB   also open Settings on that tab
enum WindowSnapshot {
    static let isActive = ProcessInfo.processInfo.environment["DISPLAYDIAL_SNAPSHOT_DIR"] != nil

    @MainActor
    static func scheduleIfRequested(model: MonitorModel) {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["DISPLAYDIAL_SNAPSHOT_DIR"] else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // A menu bar panel can't be opened from code, so its content gets a window of its own.
            let hosting = NSHostingView(rootView: MenuBarView().environment(model))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: hosting.fittingSize),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "Menu Bar Panel"
            window.contentView = hosting
            window.center()
            window.orderFrontRegardless()

            if let tab = environment["DISPLAYDIAL_SETTINGS_TAB"], !tab.isEmpty {
                UserDefaults.standard.set(tab, forKey: SettingsTab.storageKey)
                NSApp.activate()
                // `showSettingsWindow:` does nothing for SwiftUI's Settings scene; the ⌘, item does.
                let items = NSApp.mainMenu?.items.first?.submenu?.items ?? []
                if let item = items.first(where: { $0.keyEquivalent == "," }), let menu = item.menu {
                    menu.performActionForItem(at: menu.index(of: item))
                }
            }
        }

        // Late enough for the first m1ddc reads to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for window in NSApp.windows where window.isVisible && window.frame.height > 100 {
                guard let view = window.contentView?.superview,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = window.title.isEmpty ? "window" : window.title.lowercased().replacingOccurrences(of: " ", with: "-")
                let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
    }
}
