// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snapline",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Snapline",
            path: "Sources/Snapline"
        )
    ]
)
