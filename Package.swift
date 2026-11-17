// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Quinzet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Quinzet",
            path: "Sources/Quinzet",
            linkerSettings: [.linkedFramework("EventKit")]
        )
    ]
)
