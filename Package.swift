// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LofiMen",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LofiMen", targets: ["LofiMen"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "LofiMenCore"),
        .target(name: "LofiMenSync", dependencies: ["LofiMenCore"]),
        .executableTarget(
            name: "LofiMen",
            dependencies: ["LofiMenCore", "LofiMenSync", .product(name: "Sparkle", package: "Sparkle")],
            resources: ["player.html", "house.jpg", "lofi.jpg", "sleepy.jpg", "synthwave.jpg", "lofi-head.svg", "app-icon.png"]
                .map { .process("Resources/\($0)") },
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        // A small executable test runner also works with Command Line Tools-only installs.
        .executableTarget(name: "LofiMenCoreTests", dependencies: ["LofiMenCore", "LofiMenSync"], path: "Tests/LofiMenCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
