// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LofiMen",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LofiMen", targets: ["LofiMen"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "LofiMenCore"),
        .executableTarget(
            name: "LofiMen",
            dependencies: ["LofiMenCore", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // A small executable test runner also works with Command Line Tools-only installs.
        .executableTarget(name: "LofiMenCoreTests", dependencies: ["LofiMenCore"], path: "Tests/LofiMenCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
