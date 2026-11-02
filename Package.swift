// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ditto",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Ditto", targets: ["Ditto"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "DittoCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Ditto", dependencies: ["DittoCore"]),
        .executableTarget(name: "DittoTests", dependencies: ["DittoCore"], path: "Tests/DittoCoreTests")
    ]
)
