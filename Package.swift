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
        .executableTarget(name: "Ditto", dependencies: ["DittoCore", "DittoCapture"]),
        .executableTarget(name: "DittoTests", dependencies: ["DittoCore", "DittoCapture"], path: "Tests/DittoCoreTests")
    ]
)
