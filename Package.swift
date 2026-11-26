// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "UsageMonitor",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "UsageKit"),
        .executableTarget(name: "UsageMonitor", dependencies: ["UsageKit"]),
        // Linked like Xcode links app extensions, so the system can launch it as a widget.
        .executableTarget(
            name: "UsageWidget",
            dependencies: ["UsageKit"],
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
