import AppKit
import Observation

@MainActor
@Observable
final class MonitorModel {
    private(set) var ddc: M1DDC?
    private(set) var displays: [Display] = []
    private(set) var values: [Control: Double] = [:]
    private(set) var maxima: [Control: Double] = [:]
    private(set) var isMuted = false
    private(set) var currentInput: InputSource?
    private(set) var isLoading = false

    // Kept apart so a refresh, which clears its own read error, can't hide a failed write.
    private var readError: String?
    private var writeError: String?

    /// What the panel shows; setting it (Dismiss) clears both.
    var errorMessage: String? {
        get { writeError ?? readError }
        set {
            writeError = newValue
            readError = nil
        }
    }

    private(set) var selectedID: String? {
        // A snapshot copy shares the owner's defaults; it mustn't move their selection.
        didSet { if !isReadOnly { defaults.set(selectedID, forKey: PreferenceKey.selectedDisplay) } }
    }

    var useLGAlt: Bool {
        didSet { defaults.set(useLGAlt, forKey: PreferenceKey.useLGInputCodes) }
    }

    var presets: [Preset] {
        didSet { defaults.set(try? JSONEncoder().encode(presets), forKey: PreferenceKey.presets) }
    }

    /// Per display UUID. m1ddc can't send the monitor's own factory reset (VCP 0x04/0x05),
    /// so "default" is what DisplayDial first read from that monitor, or what the user set.
    private(set) var pictureDefaults: [String: PictureDefaults] {
        didSet { defaults.set(try? JSONEncoder().encode(pictureDefaults), forKey: PreferenceKey.pictureDefaults) }
    }

    private let defaults: UserDefaults
    private let locate: () -> M1DDC?
    /// Snapshot copies read the monitor but never write to it.
    private let isReadOnly: Bool

    /// A write remembers its display: the selection can change before it's sent.
    private struct Write {
        let display: Display
        let args: [String]
    }

    // Writes are coalesced per display and property, so dragging a slider sends only the
    // latest value. M1DDC's SerialRunner puts them and the reads through one queue.
    @ObservationIgnored private var pending: [String: Write] = [:]
    @ObservationIgnored private var order: [String] = []
    @ObservationIgnored private var sending: String?
    @ObservationIgnored private var writeGeneration: [String: Int] = [:]
    @ObservationIgnored private var drainTask: Task<Void, Never>?

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false

    init(defaults: UserDefaults, locate: @escaping () -> M1DDC? = M1DDC.locate, isReadOnly: Bool = RunMode.isReadOnly) {
        self.defaults = defaults
        self.locate = locate
        self.isReadOnly = isReadOnly
        ddc = locate()
        selectedID = defaults.string(forKey: PreferenceKey.selectedDisplay)
        useLGAlt = defaults.object(forKey: PreferenceKey.useLGInputCodes) as? Bool ?? true
        presets = defaults.data(forKey: PreferenceKey.presets)
            .flatMap { try? JSONDecoder().decode([Preset].self, from: $0) } ?? Preset.defaults
        pictureDefaults = defaults.data(forKey: PreferenceKey.pictureDefaults)
            .flatMap { try? JSONDecoder().decode([String: PictureDefaults].self, from: $0) } ?? [:]

        // The model lives as long as the app, so the observer is never removed.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    var selected: Display? { displays.first { $0.id == selectedID } }

    /// Volume is optional over DDC; it's only shown once the monitor reports it.
    var supportsVolume: Bool { values[.volume] != nil }

    /// False until brightness and contrast have been read, when `value` returns placeholders.
    var hasReadings: Bool { values[.luminance] != nil && values[.contrast] != nil }

    func value(_ control: Control) -> Double { values[control] ?? 50 }

    func maximum(_ control: Control) -> Double { maxima[control] ?? 100 }

    // MARK: Reading

    /// Reads the monitor. A call while a refresh is running doesn't start a second one or
    /// get dropped: it waits, and the running one goes round again so the caller sees fresh values.
    func refresh() async {
        if let refreshTask {
            refreshAgain = true
            await refreshTask.value
            return
        }
        let task = Task {
            isLoading = true
            repeat {
                refreshAgain = false
                await readMonitor()
            } while refreshAgain
            isLoading = false
            // No suspension since the loop's last check, so no caller can slip in between.
            refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func readMonitor() async {
        if ddc == nil { ddc = locate() }
        guard let ddc else {
            displays = []
            return
        }
        do {
            displays = try await ddc.displays().filter { !$0.isApple }
        } catch {
            displays = []
            readError = error.localizedDescription
            return
        }
        if selected == nil { selectedID = displays.first?.id }
        guard let display = selected else {
            readError = nil
            return
        }

        // The user can pick another display while this one is being read: stop, and let
        // `refresh` go round again for the new one rather than mixing the two.
        func stillSelected() -> Bool {
            if selectedID == display.id { return true }
            refreshAgain = true
            return false
        }

        var fresh: [Control: Int] = [:]
        for control in Control.allCases {
            do {
                let max = (try? await ddc.maximum(of: control, on: display)).flatMap { $0 > 0 ? $0 : nil } ?? 100
                let value = try await readUnlessWritten(control.rawValue, from: display, using: ddc)
                guard stillSelected() else { return }
                maxima[control] = Double(max)
                // Out of range is noise from the bus, like the garbage mute readings; ignore it.
                if let value, (0...max).contains(value) {
                    values[control] = Double(value)
                    fresh[control] = value
                }
            } catch where control == .volume {
                guard stillSelected() else { return }
                values[.volume] = nil
            } catch {
                guard stillSelected() else { return }
                readError = String(localized: "Couldn't read \(control.rawValue) from \(display.name): \(error.localizedDescription)")
                return
            }
        }

        // Mute and input are best-effort; mute is 1 (on) or 2 (off), anything else is noise.
        let mute = try? await readUnlessWritten("mute", from: display, using: ddc)
        guard stillSelected() else { return }
        if let mute, mute == 1 || mute == 2 { isMuted = mute == 1 }
        let code = try? await readUnlessWritten("input", from: display, using: ddc)
        guard stillSelected() else { return }
        if let code { currentInput = InputSource(code: code) }

        // The first reading of a monitor is the best guess at its defaults: nothing has changed
        // it yet. Only values actually read count, not ones the user set while reading.
        if pictureDefaults[display.id] == nil, !isReadOnly,
           let brightness = fresh[.luminance], let contrast = fresh[.contrast] {
            pictureDefaults[display.id] = PictureDefaults(brightness: brightness, contrast: contrast)
        }
        readError = nil
    }

    /// Reads a property, returning nil if a write to it was queued or sent meanwhile,
    /// since the monitor may have answered with the value from before that write.
    private func readUnlessWritten(_ property: String, from display: Display, using ddc: M1DDC) async throws -> Int? {
        let key = Self.key(property, display)
        let wasWriting = pending[key] != nil || sending == key
        let generation = writeGeneration[key, default: 0]
        let value = try await ddc.get(property, on: display)
        return !wasWriting && writeGeneration[key, default: 0] == generation ? value : nil
    }

    func select(_ id: String) {
        guard id != selectedID, displays.contains(where: { $0.id == id }) else { return }
        selectedID = id
        values = [:]
        maxima = [:]
        isMuted = false
        currentInput = nil
        Task { await refresh() }
    }

    // MARK: Writing

    func set(_ control: Control, to value: Double) {
        let clamped = min(max(value, 0), maximum(control))
        values[control] = clamped
        enqueue(control.rawValue, [control.rawValue, String(Int(clamped.rounded()))])
    }

    /// Steps a control from the keyboard, where the panel may never have been opened:
    /// without a reading first, the step would start from the 50 placeholder.
    func nudge(_ control: Control, by delta: Double) async {
        if values[control] == nil { await refresh() }
        guard let current = values[control] else { return }
        set(control, to: current + delta)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        enqueue("mute", ["mute", muted ? "on" : "off"])
    }

    func switchInput(_ input: InputSource) {
        currentInput = input
        enqueue("input", [useLGAlt ? "input-alt" : "input", String(input.code(lgAlt: useLGAlt))])
    }

    /// Waits until every queued write has been sent.
    func flush() async {
        while let task = drainTask { await task.value }
    }

    private static func key(_ property: String, _ display: Display) -> String {
        "\(display.uuid)/\(property)"
    }

    private func enqueue(_ property: String, _ args: [String]) {
        guard !isReadOnly, let display = selected else { return }
        let key = Self.key(property, display)
        writeGeneration[key, default: 0] += 1
        if pending.updateValue(Write(display: display, args: args), forKey: key) == nil, !order.contains(key) {
            order.append(key)
        }
        if drainTask == nil { drainTask = Task { await drain() } }
    }

    private func drain() async {
        var failed = false
        while !order.isEmpty {
            let key = order.removeFirst()
            guard let write = pending.removeValue(forKey: key), let ddc else { continue }
            sending = key
            do {
                try await ddc.set(write.args, on: write.display)
                writeError = nil
            } catch {
                writeError = error.localizedDescription
                failed = true
            }
            sending = nil
        }
        drainTask = nil
        // The sliders still show what couldn't be sent; read back what the monitor really has.
        if failed { Task { await refresh() } }
    }

    // MARK: Presets

    func apply(_ preset: Preset) {
        set(.luminance, to: Double(preset.brightness))
        set(.contrast, to: Double(preset.contrast))
        if let volume = preset.volume, supportsVolume { set(.volume, to: Double(volume)) }
    }

    func saveCurrentAsPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, hasReadings else { return }
        presets.append(Preset(
            name: trimmed,
            brightness: Int(value(.luminance).rounded()),
            contrast: Int(value(.contrast).rounded()),
            volume: values[.volume].map { Int($0.rounded()) }
        ))
    }

    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
    }

    // MARK: Defaults

    var selectedDefaults: PictureDefaults? {
        selectedID.flatMap { pictureDefaults[$0] }
    }

    var isAtDefaults: Bool {
        guard let defaults = selectedDefaults else { return true }
        return Int(value(.luminance).rounded()) == defaults.brightness
            && Int(value(.contrast).rounded()) == defaults.contrast
    }

    func restoreDefaults() {
        guard let defaults = selectedDefaults else { return }
        set(.luminance, to: Double(defaults.brightness))
        set(.contrast, to: Double(defaults.contrast))
    }

    func setDefaults(_ defaults: PictureDefaults) {
        guard let id = selectedID else { return }
        pictureDefaults[id] = PictureDefaults(
            brightness: min(max(defaults.brightness, 0), Int(maximum(.luminance))),
            contrast: min(max(defaults.contrast, 0), Int(maximum(.contrast)))
        )
    }

    func useCurrentValuesAsDefaults() {
        guard hasReadings else { return }
        setDefaults(PictureDefaults(brightness: Int(value(.luminance).rounded()), contrast: Int(value(.contrast).rounded())))
    }
}
