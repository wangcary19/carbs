// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "carbs",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "carbs", path: "Sources/carbs")
    ]
)
