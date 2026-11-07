import Foundation
import Testing
@testable import Monitorer

@MainActor
@Suite struct SettingsMigrationTests {
    private let old: [String: Any] = [
        PreferenceKey.selectedDisplay: Fixtures.lgUUID,
        PreferenceKey.useLGInputCodes: false,
        PreferenceKey.brightnessShortcuts: true,
        "unrelated": "left behind",
    ]

    @Test func copiesTheOldSettingsOnce() {
        let defaults = UserDefaults.scratch()
        SettingsMigration.run(into: defaults, from: old)

        #expect(defaults.string(forKey: PreferenceKey.selectedDisplay) == Fixtures.lgUUID)
        #expect(defaults.object(forKey: PreferenceKey.useLGInputCodes) as? Bool == false)
        #expect(defaults.bool(forKey: PreferenceKey.brightnessShortcuts))
        #expect(defaults.object(forKey: "unrelated") == nil)

        // A second launch doesn't copy again over what the user changed since.
        defaults.set(false, forKey: PreferenceKey.brightnessShortcuts)
        SettingsMigration.run(into: defaults, from: old)
        #expect(!defaults.bool(forKey: PreferenceKey.brightnessShortcuts))
    }

    @Test func keepsValuesAlreadySetUnderTheNewName() {
        let defaults = UserDefaults.scratch()
        defaults.set(Fixtures.dellUUID, forKey: PreferenceKey.selectedDisplay)
        SettingsMigration.run(into: defaults, from: old)
        #expect(defaults.string(forKey: PreferenceKey.selectedDisplay) == Fixtures.dellUUID)
    }

    @Test func presetsAndDefaultsSurviveTheRename() async {
        let before = UserDefaults.scratch()
        let model = MonitorModel(defaults: before, locate: { M1DDC(runner: FakeRunner(handler: Fixtures.monitor(luminance: 80))) })
        await model.refresh()
        model.saveCurrentAsPreset(named: "Evening")

        let after = UserDefaults.scratch()
        SettingsMigration.run(into: after, from: before.dictionaryRepresentation())
        let renamed = MonitorModel(defaults: after, locate: { M1DDC(runner: FakeRunner(handler: Fixtures.monitor())) })

        #expect(renamed.presets.map(\.name).contains("Evening"))
        await renamed.refresh()
        #expect(renamed.selectedDefaults == PictureDefaults(brightness: 80, contrast: 70))
    }

    @Test func nothingToMigrate() {
        let defaults = UserDefaults.scratch()
        SettingsMigration.run(into: defaults, from: nil)
        #expect(defaults.bool(forKey: SettingsMigration.doneKey))
        #expect(defaults.object(forKey: PreferenceKey.presets) == nil)
    }
}
