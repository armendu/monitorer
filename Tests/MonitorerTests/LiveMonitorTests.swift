import Foundation
import Testing
@testable import Monitorer

/// Read-only checks against a real monitor through the installed m1ddc.
/// Opt in with: MONITORER_LIVE=1 swift test --filter LiveMonitorTests
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MONITORER_LIVE"] == "1"))
struct LiveMonitorTests {
    @Test func readsConnectedMonitor() async throws {
        let model = MonitorModel(defaults: .scratch())
        try #require(model.ddc != nil, "m1ddc isn't installed")
        await model.refresh()

        let display = try #require(model.selected, "No external display found")
        #expect(model.errorMessage == nil)
        #expect((0...model.maximum(.luminance)).contains(model.value(.luminance)))
        #expect((0...model.maximum(.contrast)).contains(model.value(.contrast)))
        print("""
        \(display.name): brightness \(model.value(.luminance)), contrast \(model.value(.contrast)), \
        volume \(model.supportsVolume ? "\(model.value(.volume))" : "n/a"), muted \(model.isMuted), \
        input \(model.currentInput?.rawValue ?? "unknown")
        """)
    }
}
