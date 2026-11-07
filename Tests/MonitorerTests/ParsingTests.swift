import Foundation
import Testing
@testable import Monitorer

@Suite struct ParsingTests {
    @Test func parsesBuiltInDisplay() {
        let displays = M1DDC.parseDisplays(Fixtures.builtInOnly)
        #expect(displays.count == 1)
        #expect(displays[0].index == 1)
        #expect(displays[0].name == "Unknown Display")
        #expect(displays[0].uuid == Fixtures.builtInUUID)
        #expect(displays[0].vendor == 0x0610)
        #expect(displays[0].isApple)
    }

    @Test func parsesSeveralDisplaysAndKeepsVendorsSeparate() {
        let displays = M1DDC.parseDisplays(Fixtures.withLGAndDell)
        #expect(displays.map(\.uuid) == [Fixtures.builtInUUID, Fixtures.lgUUID, Fixtures.dellUUID])
        #expect(displays.map(\.vendor) == [0x0610, 0x1E6D, 0x10AC])
        #expect(displays.map(\.isApple) == [true, false, false])
    }

    @Test func keepsParenthesesInDisplayNames() {
        let displays = M1DDC.parseDisplays(Fixtures.withLGAndDell)
        #expect(displays.last?.name == "DELL U2723QE (rev. A)")
    }

    @Test func displayWithoutVendorLineHasNoVendor() {
        let displays = M1DDC.parseDisplays("[1] Mystery (ABCDEF01-0000-0000-0000-000000000000)")
        #expect(displays.count == 1)
        #expect(displays[0].vendor == nil)
        #expect(!displays[0].isApple)
    }

    @Test(arguments: ["", "Could not find a suitable external display."])
    func outputWithoutHeadersHasNoDisplays(output: String) {
        #expect(M1DDC.parseDisplays(output).isEmpty)
    }

    @Test func parsesNumbers() throws {
        #expect(try M1DDC.parseNumber("42") == 42)
        #expect(try M1DDC.parseNumber(" 7\n") == 7)
    }

    @Test func rejectsNonNumericOutput() {
        #expect(throws: DDCError.failed("Could not find a suitable external display.")) {
            try M1DDC.parseNumber("Could not find a suitable external display.")
        }
    }

    @Test func inputCodes() {
        #expect(InputSource.allCases.map { $0.code(lgAlt: true) } == [208, 144, 145])
        #expect(InputSource.allCases.map { $0.code(lgAlt: false) } == [15, 17, 18])
    }

    @Test func inputFromReadBackCode() {
        #expect(InputSource(code: 15) == .displayPort)
        #expect(InputSource(code: 145) == .hdmi2)
        #expect(InputSource(code: 27) == nil)
    }

    @Test func presetRoundTripsAndToleratesMissingVolume() throws {
        let preset = Preset(name: "Gaming", brightness: 90, contrast: 80, volume: 55)
        let decoded = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(preset))
        #expect(decoded == preset)

        let json = #"{"id":"\#(UUID().uuidString)","name":"Night","brightness":20,"contrast":60}"#
        let legacy = try JSONDecoder().decode(Preset.self, from: Data(json.utf8))
        #expect(legacy.volume == nil)
    }

    @Test func processRunnerReportsExitStatus() async throws {
        let echo = ProcessRunner(executable: URL(fileURLWithPath: "/bin/echo"))
        #expect(try await echo.run(["hello"]) == "hello")

        let failing = ProcessRunner(executable: URL(fileURLWithPath: "/bin/sh"))
        await #expect(throws: DDCError.failed("nope")) {
            try await failing.run(["-c", "echo nope; exit 1"])
        }
    }

    @Test func processRunnerGivesUpOnAHungCall() async {
        let hung = ProcessRunner(executable: URL(fileURLWithPath: "/bin/sleep"), timeout: 0.2)
        let start = ContinuousClock.now
        await #expect(throws: DDCError.timedOut) {
            try await hung.run(["10"])
        }
        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test func serialRunnerRunsOneCallAtATime() async throws {
        let probe = OverlapProbe()
        let serial = SerialRunner(probe)
        try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<8 { group.addTask { try await serial.run(["\(index)"]) } }
            for try await _ in group {}
        }
        #expect(await probe.maximumInFlight == 1)
        #expect(await probe.started == 8)
    }
}

/// Counts how many calls are running at once.
private actor OverlapProbe: CommandRunner {
    private(set) var maximumInFlight = 0
    private(set) var started = 0
    private var inFlight = 0

    func run(_ args: [String]) async throws -> String {
        inFlight += 1
        started += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        try await Task.sleep(for: .milliseconds(5))
        inFlight -= 1
        return ""
    }
}
