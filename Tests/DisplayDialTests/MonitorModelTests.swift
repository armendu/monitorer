import Foundation
import Testing
@testable import DisplayDial

@MainActor
@Suite struct MonitorModelTests {
    private func makeModel(
        _ runner: FakeRunner,
        defaults: UserDefaults = .scratch()
    ) -> MonitorModel {
        MonitorModel(defaults: defaults, locate: { M1DDC(runner: runner) })
    }

    @Test func refreshSkipsAppleDisplaysAndReadsValues() async {
        let model = makeModel(FakeRunner(handler: Fixtures.monitor()))
        await model.refresh()

        #expect(model.displays.map(\.name) == ["LG ULTRAGEAR+"])
        #expect(model.selectedID == Fixtures.lgUUID)
        #expect(model.value(.luminance) == 40)
        #expect(model.value(.contrast) == 70)
        #expect(model.value(.volume) == 30)
        #expect(model.maximum(.luminance) == 100)
        #expect(model.supportsVolume)
        #expect(model.errorMessage == nil)
    }

    @Test func noExternalDisplayLeavesNothingSelected() async {
        let runner = FakeRunner(handler: Fixtures.monitor(listing: Fixtures.builtInOnly))
        let model = makeModel(runner)
        await model.refresh()

        #expect(model.displays.isEmpty)
        #expect(model.selected == nil)
        #expect(model.errorMessage == nil)
        #expect(await runner.calls.count == 1)
    }

    @Test func missingBinaryShowsNoDisplays() async {
        let model = MonitorModel(defaults: .scratch(), locate: { nil })
        await model.refresh()
        #expect(model.ddc == nil)
        #expect(model.displays.isEmpty)
    }

    @Test func volumeIsHiddenWhenUnsupported() async {
        let model = makeModel(FakeRunner(handler: Fixtures.monitor(volume: nil)))
        await model.refresh()

        #expect(!model.supportsVolume)
        #expect(model.value(.luminance) == 40)
        #expect(model.errorMessage == nil)
    }

    @Test func failedReadShowsError() async {
        let model = makeModel(FakeRunner(handler: Fixtures.monitor(failing: .contrast)))
        await model.refresh()

        let message = model.errorMessage ?? ""
        #expect(message.contains("contrast"))
        #expect(message.contains("DDC read failed"))
    }

    @Test func setTargetsSelectedDisplay() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = makeModel(runner)
        await model.refresh()

        model.set(.luminance, to: 55.4)
        await model.flush()

        #expect(model.value(.luminance) == 55.4)
        #expect(await runner.calls.last == ["display", Fixtures.lgUUID, "set", "luminance", "55"])
    }

    @Test func rapidChangesAreCoalesced() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = makeModel(runner)
        await model.refresh()

        // A burst in one run-loop turn collapses into a single write of the final value.
        for value in 10...30 { model.set(.luminance, to: Double(value)) }
        await model.flush()
        #expect(await runner.writes == [["luminance", "30"]])

        // Changes made while a write is in flight collapse into one follow-up write.
        await runner.hold { $0.last == "40" }
        model.set(.luminance, to: 40)
        await runner.waitUntilHeld()
        for value in 41...50 { model.set(.luminance, to: Double(value)) }
        await runner.release()
        await model.flush()

        #expect(await runner.writes == [["luminance", "30"], ["luminance", "40"], ["luminance", "50"]])
        #expect(model.value(.luminance) == 50)
    }

    @Test func differentControlsAreAllSent() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = makeModel(runner)
        await model.refresh()

        model.set(.luminance, to: 60)
        model.set(.contrast, to: 65)
        model.setMuted(true)
        await model.flush()

        #expect(await runner.writes == [["luminance", "60"], ["contrast", "65"], ["mute", "on"]])
        #expect(model.isMuted)
    }

    @Test func changeDuringReadIsNotOverwrittenByStaleValue() async {
        let runner = FakeRunner(handler: Fixtures.monitor(luminance: 40))
        let model = makeModel(runner)

        // The brightness read is in flight when the user drags; it answers with the old 40,
        // since the write is queued behind it.
        await runner.hold { $0.suffix(2) == ["get", "luminance"] }
        let refresh = Task { await model.refresh() }
        await runner.waitUntilHeld()
        model.set(.luminance, to: 95)
        await runner.release()
        await refresh.value
        await model.flush()

        #expect(model.value(.luminance) == 95)
        #expect(model.value(.contrast) == 70)
        #expect(await runner.writes == [["luminance", "95"]])
    }

    @Test func refreshAfterAQueuedWriteShowsTheWrittenValue() async {
        let runner = FakeRunner(handler: Fixtures.monitor(luminance: 40))
        let model = makeModel(runner)
        await model.refresh()

        model.set(.luminance, to: 95)
        await model.refresh()
        await model.flush()

        #expect(model.value(.luminance) == 95)
    }

    @Test func readsAndWritesNeverOverlap() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = makeModel(runner)
        await model.refresh()

        // With the write held, a refresh started now must queue behind it, not run beside it.
        await runner.hold { $0.contains("set") }
        model.set(.luminance, to: 60)
        await runner.waitUntilHeld()
        let refresh = Task { await model.refresh() }
        try? await Task.sleep(for: .milliseconds(50))
        let callsWhileHeld = await runner.calls.count
        await runner.release()
        await refresh.value

        #expect(callsWhileHeld == (await runner.calls.firstIndex { $0.contains("set") } ?? -1) + 1)
        #expect(model.value(.luminance) == 60)
    }

    @Test func writesGoToTheDisplayTheyWereMadeFor() async {
        let runner = FakeRunner(handler: Fixtures.monitor(listing: Fixtures.withLGAndDell))
        let model = makeModel(runner)
        await model.refresh()
        #expect(model.selectedID == Fixtures.lgUUID)

        // A preset is several writes; the user switches to the Dell while the first is sent.
        await runner.hold { $0.contains("set") }
        model.apply(Preset(name: "Movie", brightness: 77, contrast: 77, volume: 77))
        await runner.waitUntilHeld()
        model.select(Fixtures.dellUUID)
        await runner.release()
        await model.flush()

        #expect(await runner.writeTargets == [Fixtures.lgUUID, Fixtures.lgUUID, Fixtures.lgUUID])
    }

    @Test func selectingDuringARefreshReadsTheNewDisplay() async {
        let runner = FakeRunner(handler: Fixtures.monitor(
            listing: Fixtures.withLGAndDell,
            luminanceByDisplay: [Fixtures.lgUUID: 40, Fixtures.dellUUID: 85]
        ))
        let model = makeModel(runner)
        await model.refresh()

        await runner.hold { $0.suffix(2) == ["get", "luminance"] }
        let refresh = Task { await model.refresh() }
        await runner.waitUntilHeld()
        model.select(Fixtures.dellUUID)
        await runner.release()
        await refresh.value
        await model.refresh()

        #expect(model.selected?.name == "DELL U2723QE (rev. A)")
        #expect(model.value(.luminance) == 85)
        #expect(await runner.calls.contains(["display", Fixtures.dellUUID, "get", "luminance"]))
    }

    @Test func refreshDuringARefreshIsNotDropped() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = makeModel(runner)

        await runner.hold { $0.starts(with: ["display", "list"]) }
        let first = Task { await model.refresh() }
        await runner.waitUntilHeld()
        let second = Task { await model.refresh() }
        try? await Task.sleep(for: .milliseconds(20))
        await runner.release()
        await first.value
        await second.value

        // The second call made the first go round again: two display lists, not one.
        #expect(await runner.calls.filter { $0.starts(with: ["display", "list"]) }.count == 2)
        #expect(!model.isLoading)
    }

    @Test func nudgeDuringARefreshWaitsForIt() async {
        let runner = FakeRunner(handler: Fixtures.monitor(luminance: 40))
        let model = makeModel(runner)

        await runner.hold { $0.starts(with: ["display", "list"]) }
        let refresh = Task { await model.refresh() }
        await runner.waitUntilHeld()
        let nudge = Task { await model.nudge(.luminance, by: 10) }
        try? await Task.sleep(for: .milliseconds(20))
        await runner.release()
        await refresh.value
        await nudge.value
        await model.flush()

        #expect(await runner.writes == [["luminance", "50"]])
    }

    @Test func outOfRangeReadingsAreIgnored() async {
        let model = makeModel(FakeRunner(handler: Fixtures.monitor(luminance: 9388)))
        await model.refresh()

        #expect(model.values[.luminance] == nil)
        #expect(model.value(.contrast) == 70)
        // Not saved as the monitor's default either.
        #expect(model.selectedDefaults == nil)
    }

    @Test func writesAreClampedToTheMonitorsRange() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = makeModel(runner)
        await model.refresh()

        model.set(.luminance, to: 140)
        model.set(.contrast, to: -5)
        await model.flush()

        #expect(await runner.writes == [["luminance", "100"], ["contrast", "0"]])
    }

    @Test func savingAPresetNeedsReadings() async {
        let model = makeModel(FakeRunner(handler: Fixtures.monitor(listing: Fixtures.builtInOnly)))
        await model.refresh()
        #expect(!model.hasReadings)

        model.saveCurrentAsPreset(named: "Placeholder")
        #expect(!model.presets.map(\.name).contains("Placeholder"))
    }

    @Test func muteOnAndOff() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = makeModel(runner)
        await model.refresh()

        model.setMuted(true)
        await model.flush()
        model.setMuted(false)
        await model.flush()

        #expect(await runner.writes == [["mute", "on"], ["mute", "off"]])
        #expect(!model.isMuted)
    }

    @Test func inputUsesLGCodesByDefault() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = makeModel(runner)
        await model.refresh()

        model.switchInput(.hdmi1)
        await model.flush()
        model.useLGAlt = false
        model.switchInput(.displayPort)
        await model.flush()

        #expect(await runner.writes == [["input-alt", "144"], ["input", "15"]])
        #expect(model.currentInput == .displayPort)
    }

    @Test func refreshReadsMuteAndInput() async {
        let model = makeModel(FakeRunner(handler: Fixtures.monitor(mute: 1, input: 17)))
        await model.refresh()

        #expect(model.isMuted)
        #expect(model.currentInput == .hdmi1)
    }

    @Test func implausibleMuteReadingIsIgnored() async {
        // Seen on the real LG: a mute read right after a write once returned 9388.
        let model = makeModel(FakeRunner(handler: Fixtures.monitor(mute: 9388)))
        await model.refresh()
        #expect(!model.isMuted)
        #expect(model.errorMessage == nil)
    }

    @Test func unknownOrUnsupportedInputShowsNoSelection() async {
        let usbC = makeModel(FakeRunner(handler: Fixtures.monitor(input: 27)))
        await usbC.refresh()
        #expect(usbC.currentInput == nil)

        let unsupported = makeModel(FakeRunner(handler: Fixtures.monitor(mute: nil, input: nil)))
        await unsupported.refresh()
        #expect(unsupported.currentInput == nil)
        #expect(!unsupported.isMuted)
        #expect(unsupported.errorMessage == nil)
    }

    @Test func switchedInputSurvivesRefresh() async {
        let model = makeModel(FakeRunner(handler: Fixtures.monitor(input: 15)))
        await model.refresh()
        #expect(model.currentInput == .displayPort)

        model.switchInput(.hdmi2)
        await model.flush()
        await model.refresh()
        #expect(model.currentInput == .hdmi2)
    }

    @Test func applyingPresetSendsItsValues() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = makeModel(runner)
        await model.refresh()

        model.apply(Preset(name: "Movie", brightness: 35, contrast: 75, volume: 60))
        await model.flush()

        #expect(await runner.writes == [["luminance", "35"], ["contrast", "75"], ["volume", "60"]])
    }

    @Test func applyingPresetSkipsVolumeWhenUnsupported() async {
        let runner = FakeRunner(handler: Fixtures.monitor(volume: nil))
        let model = makeModel(runner)
        await model.refresh()

        model.apply(Preset(name: "Movie", brightness: 35, contrast: 75, volume: 60))
        await model.flush()

        #expect(await runner.writes == [["luminance", "35"], ["contrast", "75"]])
    }

    @Test func presetsAndSettingsPersist() async {
        let defaults = UserDefaults.scratch()
        let model = makeModel(FakeRunner(handler: Fixtures.monitor()), defaults: defaults)
        #expect(model.presets.map(\.name) == ["Day", "Night"])
        await model.refresh()

        model.saveCurrentAsPreset(named: "  Gaming  ")
        model.saveCurrentAsPreset(named: "   ")
        model.delete(model.presets[0])
        model.useLGAlt = false

        let reloaded = makeModel(FakeRunner(handler: Fixtures.monitor()), defaults: defaults)
        #expect(reloaded.presets.map(\.name) == ["Night", "Gaming"])
        #expect(reloaded.presets.last == Preset(id: reloaded.presets.last!.id, name: "Gaming", brightness: 40, contrast: 70, volume: 30))
        #expect(!reloaded.useLGAlt)
    }

    @Test func selectionPersistsAndRereadsValues() async {
        let defaults = UserDefaults.scratch()
        let runner = FakeRunner(handler: Fixtures.monitor(listing: Fixtures.withLGAndDell))
        let model = makeModel(runner, defaults: defaults)
        await model.refresh()
        #expect(model.selectedID == Fixtures.lgUUID)

        model.select(Fixtures.dellUUID)
        model.select("not-a-display")
        await model.refresh()
        #expect(model.selected?.name == "DELL U2723QE (rev. A)")
        #expect(await runner.calls.contains(["display", Fixtures.dellUUID, "get", "luminance"]))

        let reloaded = makeModel(FakeRunner(handler: Fixtures.monitor(listing: Fixtures.withLGAndDell)), defaults: defaults)
        await reloaded.refresh()
        #expect(reloaded.selectedID == Fixtures.dellUUID)
    }

    @Test func forgottenDisplayFallsBackToFirst() async {
        let defaults = UserDefaults.scratch()
        defaults.set("GONE-0000", forKey: "selectedDisplay")
        let model = makeModel(FakeRunner(handler: Fixtures.monitor()), defaults: defaults)
        await model.refresh()
        #expect(model.selectedID == Fixtures.lgUUID)
    }

    @Test func failedWriteShowsError() async {
        let runner = FakeRunner { args in
            if args.contains("set") { throw DDCError.failed("I2C timeout") }
            return try Fixtures.monitor()(args)
        }
        let model = makeModel(runner)
        await model.refresh()

        model.set(.contrast, to: 10)
        await model.flush()
        #expect(model.value(.contrast) == 10)

        // The failed write triggers a read-back, which mustn't clear the write's error.
        await model.refresh()
        #expect(model.value(.contrast) == 70)
        #expect(model.errorMessage == "I2C timeout")

        model.errorMessage = nil
        #expect(model.errorMessage == nil)
    }

    @Test func readOnlyCopyNeverWrites() async {
        let runner = FakeRunner(handler: Fixtures.monitor())
        let model = MonitorModel(defaults: .scratch(), locate: { M1DDC(runner: runner) }, isReadOnly: true)
        await model.refresh()

        model.set(.luminance, to: 10)
        model.setMuted(true)
        model.switchInput(.hdmi1)
        model.apply(Preset(name: "Night", brightness: 20, contrast: 60))
        await model.flush()

        #expect(await runner.writes.isEmpty)
        #expect(model.value(.luminance) == 20)
    }

    @Test func nudgeReadsFirstThenStepsWithinRange() async {
        let runner = FakeRunner(handler: Fixtures.monitor(luminance: 95))
        let model = makeModel(runner)

        // Never refreshed, as when a shortcut fires before the panel was opened.
        await model.nudge(.luminance, by: 10)
        await model.flush()
        #expect(model.value(.luminance) == 100)

        await model.nudge(.luminance, by: -30)
        await model.flush()
        #expect(await runner.writes == [["luminance", "100"], ["luminance", "70"]])
    }

    @Test func firstReadingBecomesTheDefaults() async {
        let defaults = UserDefaults.scratch()
        let model = makeModel(FakeRunner(handler: Fixtures.monitor(luminance: 80, contrast: 65)), defaults: defaults)
        await model.refresh()
        #expect(model.selectedDefaults == PictureDefaults(brightness: 80, contrast: 65))
        #expect(model.isAtDefaults)

        // Later readings don't move them, and they survive a relaunch.
        model.set(.luminance, to: 30)
        await model.flush()
        await model.refresh()
        let reloaded = makeModel(FakeRunner(handler: Fixtures.monitor(luminance: 30)), defaults: defaults)
        await reloaded.refresh()
        #expect(reloaded.selectedDefaults == PictureDefaults(brightness: 80, contrast: 65))
        #expect(!reloaded.isAtDefaults)
    }

    @Test func restoreDefaultsSendsBothValues() async {
        let runner = FakeRunner(handler: Fixtures.monitor(luminance: 80, contrast: 65))
        let model = makeModel(runner)
        await model.refresh()

        model.set(.luminance, to: 20)
        model.set(.contrast, to: 40)
        await model.flush()
        model.restoreDefaults()
        await model.flush()

        #expect(await runner.writes.suffix(2) == [["luminance", "80"], ["contrast", "65"]])
        #expect(model.isAtDefaults)
    }

    @Test func defaultsCanBeChangedAndAreClamped() async {
        let model = makeModel(FakeRunner(handler: Fixtures.monitor(luminance: 80, contrast: 65)))
        await model.refresh()

        model.set(.luminance, to: 45)
        model.useCurrentValuesAsDefaults()
        #expect(model.selectedDefaults == PictureDefaults(brightness: 45, contrast: 65))

        model.setDefaults(PictureDefaults(brightness: 140, contrast: -5))
        #expect(model.selectedDefaults == PictureDefaults(brightness: 100, contrast: 0))
    }

    @Test func defaultsArePerMonitor() async {
        let runner = FakeRunner(handler: Fixtures.monitor(listing: Fixtures.withLGAndDell, luminance: 80))
        let model = makeModel(runner)
        await model.refresh()
        model.setDefaults(PictureDefaults(brightness: 10, contrast: 10))

        model.select(Fixtures.dellUUID)
        await model.refresh()
        // The Dell's first reading, not the LG's edited defaults.
        #expect(model.selectedDefaults == PictureDefaults(brightness: 80, contrast: 70))
    }

    @Test func readOnlyCopyRecordsNoDefaults() async {
        let model = MonitorModel(defaults: .scratch(), locate: { M1DDC(runner: FakeRunner(handler: Fixtures.monitor())) }, isReadOnly: true)
        await model.refresh()
        #expect(model.selectedDefaults == nil)
    }

    @Test func nudgeDoesNothingWithoutAMonitor() async {
        let runner = FakeRunner(handler: Fixtures.monitor(listing: Fixtures.builtInOnly))
        let model = makeModel(runner)
        await model.nudge(.luminance, by: 10)
        await model.flush()
        #expect(await runner.writes.isEmpty)
    }
}
