// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LittleMark",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "LittleMark",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
