// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LofiMen",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LofiMen", targets: ["LofiMen"])],
    targets: [
        .target(name: "LofiMenCore"),
        .executableTarget(
            name: "LofiMen",
            dependencies: ["LofiMenCore"],
            resources: [.process("Resources")]
        ),
        // A small executable test runner also works with Command Line Tools-only installs.
        .executableTarget(name: "LofiMenCoreTests", dependencies: ["LofiMenCore"], path: "Tests/LofiMenCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
