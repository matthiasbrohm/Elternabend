// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ElternabendAbgleich",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ElternabendAbgleich", path: "Sources")
    ]
)
