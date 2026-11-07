// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Monitorer",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Monitorer", path: "Sources/Monitorer"),
        .testTarget(name: "MonitorerTests", dependencies: ["Monitorer"], path: "Tests/MonitorerTests"),
    ],
    swiftLanguageModes: [.v5]
)
