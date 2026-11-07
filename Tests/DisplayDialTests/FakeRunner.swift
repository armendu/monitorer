import Foundation
import Testing
@testable import DisplayDial

/// Records m1ddc invocations and answers them from a handler instead of spawning a process.
///
/// Races are staged with `hold(where:)` and `release()` rather than delays: a held call
/// doesn't answer until the test says so, and since M1DDC serializes calls, everything
/// queued behind it waits too. Delays depended on which timer woke first.
actor FakeRunner: CommandRunner {
    private(set) var calls: [[String]] = []
    private let handler: @Sendable ([String]) throws -> String
    private var holdPredicate: (@Sendable ([String]) -> Bool)?
    private var held: [CheckedContinuation<Void, Never>] = []

    init(handler: @escaping @Sendable ([String]) throws -> String) {
        self.handler = handler
    }

    func run(_ args: [String]) async throws -> String {
        calls.append(args)
        if let holdPredicate, holdPredicate(args) {
            await withCheckedContinuation { held.append($0) }
        }
        return try handler(args)
    }

    /// From now on, calls matching `predicate` wait for `release()`.
    func hold(where predicate: @escaping @Sendable ([String]) -> Bool) {
        holdPredicate = predicate
    }

    /// Lets every held call answer, and stops holding new ones.
    func release() {
        holdPredicate = nil
        held.forEach { $0.resume() }
        held = []
    }

    /// Waits until a call is being held, failing the test instead of hanging if none arrives.
    func waitUntilHeld() async {
        await waitFor { !held.isEmpty }
    }

    /// Waits until a call matching `predicate` has been received.
    func waitForCall(where predicate: ([String]) -> Bool) async {
        await waitFor { calls.contains(where: predicate) }
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Timed out waiting on the fake m1ddc")
    }

    /// The `set` arguments sent so far, without the `display <uuid> set` prefix.
    var writes: [[String]] {
        calls.filter { $0.count > 3 && $0[2] == "set" }.map { Array($0.dropFirst(3)) }
    }

    /// The displays the `set` calls went to, in order.
    var writeTargets: [String] {
        calls.filter { $0.count > 3 && $0[2] == "set" }.map { $0[1] }
    }
}

enum Fixtures {
    static let builtInUUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    static let lgUUID = "5B1C0E5A-1111-2222-3333-444455556666"
    static let dellUUID = "9F00AA11-BBBB-CCCC-DDDD-EEEEFFFF0000"

    /// Captured from `m1ddc display list detailed` on a MacBook with no external display.
    static let builtInOnly = """
    [1] Unknown Display (37D8832A-2D66-02CA-B9F7-8F30A301B230)
     - Product name:  Unknown Display
     - Manufacturer:  00-10-fa
     - AN Serial:     (null)
     - Vendor:        1552 (0x0610)
     - Model:         41038 (0xa04e)
     - Serial:        4251086178 (0xfd626d62)
     - Display ID:    1
     - System UUID:   37D8832A-2D66-02CA-B9F7-8F30A301B230
     - EDID UUID:     (null)
     - IO Location:   IOService:/AppleARMPE/arm-io@10F00000/AppleH15IO/disp0@7C000000/IOMobileFramebufferShim
     - Adapter:       15619
    """

    static let withLG = builtInOnly + """

    [2] LG ULTRAGEAR+ (\(lgUUID))
     - Product name:  LG ULTRAGEAR+
     - Vendor:        7789 (0x1e6d)
     - Display ID:    2
    """

    static let withLGAndDell = withLG + """

    [3] DELL U2723QE (rev. A) (\(dellUUID))
     - Vendor:        4268 (0x10ac)
    """

    /// A handler that behaves like m1ddc talking to monitors that remember what's written to
    /// them. Every display starts from the same values unless `luminanceByDisplay` says otherwise.
    static func monitor(
        listing: String = withLG,
        luminance: Int = 40,
        contrast: Int = 70,
        volume: Int? = 30,
        mute: Int? = 2,
        input: Int? = 15,
        luminanceByDisplay: [String: Int] = [:],
        failing: Control? = nil
    ) -> @Sendable ([String]) throws -> String {
        let state = MonitorState(
            ["luminance": luminance, "contrast": contrast, "volume": volume, "mute": mute, "input": input],
            luminanceByDisplay: luminanceByDisplay
        )
        return { args in
            if args.starts(with: ["display", "list"]) { return listing }
            guard args.count >= 4 else { throw DDCError.failed("bad args \(args)") }
            let display = args[1]
            let property = args[3]
            switch args[2] {
            case "set":
                guard args.count >= 5 else { throw DDCError.failed("missing value") }
                switch property {
                case "mute": state[display, "mute"] = args[4] == "on" ? 1 : 2
                // Like a real LG: switched with the alternate code, reported with the standard one.
                case "input", "input-alt": state[display, "input"] = Int(args[4]).flatMap(InputSource.init(code:))?.code(lgAlt: false)
                default: state[display, property] = Int(args[4])
                }
                return "Writing \(args[4])"
            case "max":
                return "100"
            case "get":
                if property == failing?.rawValue { throw DDCError.failed("DDC read failed") }
                guard let value = state[display, property] else { throw DDCError.failed("Unsupported") }
                return "\(value)"
            default:
                throw DDCError.failed("unknown command \(args)")
            }
        }
    }
}

/// Thread-safe storage for each fake monitor's current values; `nil` means unsupported.
final class MonitorState: @unchecked Sendable {
    private let lock = NSLock()
    private let initial: [String: Int?]
    private var values: [String: Int?] = [:]

    init(_ initial: [String: Int?], luminanceByDisplay: [String: Int]) {
        self.initial = initial
        for (display, luminance) in luminanceByDisplay {
            values["\(display)/luminance"] = luminance
        }
    }

    subscript(display: String, property: String) -> Int? {
        get { lock.withLock { values["\(display)/\(property)"] ?? initial[property] ?? nil } }
        set {
            lock.withLock {
                // Unsupported properties stay unsupported.
                if case .some(.some) = initial[property] { values["\(display)/\(property)"] = newValue }
            }
        }
    }
}

extension UserDefaults {
    /// A throwaway defaults domain so tests don't touch the real app's settings.
    ///
    /// Named by an absolute path, so its plist lives in a temporary folder rather than
    /// ~/Library/Preferences. Named suites there were rewritten by cfprefsd after the test
    /// process deleted them, leaving ~30 empty plists per run.
    static func scratch() -> UserDefaults {
        UserDefaults(suiteName: ScratchSuites.directory.appending(path: UUID().uuidString).path)!
    }
}

private enum ScratchSuites {
    static let directory: URL = {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DisplayDialTests-\(getpid())")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        atexit { try? FileManager.default.removeItem(at: ScratchSuites.directory) }
        return directory
    }()
}
