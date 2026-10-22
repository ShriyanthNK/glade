// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Glade",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "glade", targets: ["Glade"]),
    ],
    targets: [
        // Everything without UI: config, wire format, socket server. Unit-tested.
        .target(name: "GladeCore"),
        // The app and the `glade` CLI (one binary: no args = background app).
        .executableTarget(name: "Glade", dependencies: ["GladeCore"]),
        .testTarget(name: "GladeCoreTests", dependencies: ["GladeCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
