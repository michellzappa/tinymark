// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TinyMark",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
        .package(path: "Packages/TinyKit"),
    ],
    targets: [
        .executableTarget(
            name: "TinyMark",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "TinyKit", package: "TinyKit"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
