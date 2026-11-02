// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ditto",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Ditto", targets: ["Ditto"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "DittoCore", dependencies: ["CSQLite"]),
        .target(name: "DittoCapture", dependencies: ["DittoCore"]),
        .target(name: "DittoE2E", dependencies: ["DittoCore", "DittoCapture"], path: "Tests/NativeE2E"),
        .executableTarget(name: "Ditto", dependencies: ["DittoCore", "DittoCapture", "DittoE2E"]),
        .executableTarget(name: "DittoTests", dependencies: ["DittoCore", "DittoCapture"], path: "Tests/DittoCoreTests")
    ]
)
