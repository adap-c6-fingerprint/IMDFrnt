// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IMDFrnt",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "IMDFrnt",
            path: "Sources/IMDFrnt"
        )
    ],
    swiftLanguageModes: [.v6]
)
