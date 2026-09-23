// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TinyTitanBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TinyTitanBar", targets: ["TinyTitanBar"])
    ],
    targets: [
        .executableTarget(
            name: "TinyTitanBar",
            path: "Sources/TinyTitanBar"
        )
    ]
)
