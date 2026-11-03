// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TubeVault",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TubeVault",
            path: "Sources/TubeVault"
        )
    ]
)
