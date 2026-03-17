// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TinyKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TinyKit", targets: ["TinyKit"]),
    ],
    targets: [
        .target(name: "TinyKit"),
    ]
)
