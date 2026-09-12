// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MicroKeys",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic, no AppKit/IOKit: protocol decoding, config, shortcut grammar, mapping.
        .target(name: "MicroKeysCore", path: "Sources/MicroKeysCore"),
        // The menu bar app: IOKit HID reader, CGEvent synthesizer, permissions, UI.
        .executableTarget(
            name: "MicroKeys",
            dependencies: ["MicroKeysCore"],
            path: "Sources/MicroKeys",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "MicroKeysCoreTests",
            dependencies: ["MicroKeysCore"],
            path: "Tests/MicroKeysCoreTests"
        ),
    ]
)
