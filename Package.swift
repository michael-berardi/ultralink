// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UltraLink",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "UltraLink",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/UltraLink",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
