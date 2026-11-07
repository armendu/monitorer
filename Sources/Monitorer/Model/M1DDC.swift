import Foundation

struct Display: Identifiable, Hashable, Sendable {
    let index: Int
    let name: String
    let uuid: String
    var vendor: Int?

    var id: String { uuid }

    /// Apple panels (built-in, Studio Display) report vendor 0x0610 and don't speak DDC.
    var isApple: Bool { vendor == 0x0610 }
}

enum DDCError: LocalizedError, Equatable {
    case failed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .failed(let output): output.isEmpty ? String(localized: "m1ddc failed") : output
        case .timedOut: String(localized: "The monitor didn't answer. It may be asleep or switching inputs.")
        }
    }
}

enum Control: String, CaseIterable, Sendable {
    case luminance, contrast, volume
}

protocol CommandRunner: Sendable {
    func run(_ args: [String]) async throws -> String
}

/// Runs an executable as a child process and returns its combined output.
struct ProcessRunner: CommandRunner {
    let executable: URL
    /// A DDC transaction to a sleeping or input-switching monitor can hang. Without a limit,
    /// one stuck call would block every later read and write until the app was relaunched.
    var timeout: TimeInterval = 5

    func run(_ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let timedOut = Flag()
                let deadline = DispatchWorkItem {
                    timedOut.set()
                    process.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                // Read before waiting so a full pipe can't block the child.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                deadline.cancel()
                let output = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if timedOut.isSet {
                    continuation.resume(throwing: DDCError.timedOut)
                } else if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: DDCError.failed(output))
                }
            }
        }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }
}

/// Lets one call through at a time, in the order they arrive. A DDC read is an I2C write
/// followed by a read, and another process's write landing in between corrupts the reply,
/// so reads and writes share this one queue.
actor SerialRunner: CommandRunner {
    private let base: any CommandRunner
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ base: any CommandRunner) {
        self.base = base
    }

    func run(_ args: [String]) async throws -> String {
        if isBusy {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            isBusy = true
        }
        // Hand the turn straight to the next caller, so a new arrival can't jump the queue.
        defer {
            if waiting.isEmpty { isBusy = false } else { waiting.removeFirst().resume() }
        }
        return try await base.run(args)
    }
}

/// Typed wrapper around the m1ddc command-line tool. Every call goes through one
/// `SerialRunner`, so keep a single instance rather than making a new one per use.
struct M1DDC: Sendable {
    let runner: any CommandRunner

    init(runner: any CommandRunner) {
        self.runner = SerialRunner(runner)
    }

    static let searchPaths = ["/opt/homebrew/bin/m1ddc", "/usr/local/bin/m1ddc"]
    static let installCommand = "brew install m1ddc"

    static func locate() -> M1DDC? {
        searchPaths
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { M1DDC(runner: ProcessRunner(executable: URL(fileURLWithPath: $0))) }
    }

    func displays() async throws -> [Display] {
        Self.parseDisplays(try await runner.run(["display", "list", "detailed"]))
    }

    func value(of control: Control, on display: Display) async throws -> Int {
        try await get(control.rawValue, on: display)
    }

    /// Reads any property m1ddc can `get`. Besides the `Control` cases this includes
    /// `mute` (1 = on, 2 = off) and `input` (the standard VCP 0x60 code), which work
    /// even though m1ddc's help doesn't list them.
    func get(_ property: String, on display: Display) async throws -> Int {
        try Self.parseNumber(try await runner.run(["display", display.uuid, "get", property]))
    }

    func maximum(of control: Control, on display: Display) async throws -> Int {
        try Self.parseNumber(try await runner.run(["display", display.uuid, "max", control.rawValue]))
    }

    func set(_ args: [String], on display: Display) async throws {
        _ = try await runner.run(["display", display.uuid, "set"] + args)
    }

    /// Parses `m1ddc display list detailed`: a `[n] Name (UUID)` header per display,
    /// followed by indented ` - Key: value` attribute lines.
    static func parseDisplays(_ output: String) -> [Display] {
        let header = #/\[(\d+)\] (.*) \(([0-9A-Fa-f-]+)\)/#
        let vendor = #/Vendor:\s+(\d+)/#

        var displays: [Display] = []
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if let match = line.wholeMatch(of: header) {
                displays.append(Display(index: Int(match.1) ?? displays.count + 1, name: String(match.2), uuid: String(match.3)))
            } else if let match = line.firstMatch(of: vendor), !displays.isEmpty {
                displays[displays.count - 1].vendor = Int(match.1)
            }
        }
        return displays
    }

    static func parseNumber(_ output: String) throws -> Int {
        guard let value = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DDCError.failed(output)
        }
        return value
    }
}
