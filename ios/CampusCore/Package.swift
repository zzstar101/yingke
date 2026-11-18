// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CampusCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "CampusCore", targets: ["CampusCore"])],
    targets: [
        .target(name: "CampusCore"),
        .testTarget(name: "CampusCoreTests", dependencies: ["CampusCore"]),
    ]
)
