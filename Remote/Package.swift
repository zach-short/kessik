// swift-tools-version: 5.9
import PackageDescription

// Kessik Remote, the Mac side of the Remote tab. It builds with the Command Line Tools, so the
// Mac it runs on does not need Xcode. `scripts/kessik remote` builds it and makes the app bundle.
let package = Package(
    name: "KessikRemote",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "RemoteWire"),
        .executableTarget(name: "KessikRemote", dependencies: ["RemoteWire"]),
    ]
)
