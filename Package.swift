// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "DisplayDial",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "DisplayDial", path: "Sources/DisplayDial"),
        .testTarget(name: "DisplayDialTests", dependencies: ["DisplayDial"], path: "Tests/DisplayDialTests"),
    ],
    swiftLanguageModes: [.v5]
)
