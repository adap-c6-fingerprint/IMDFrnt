// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IMDFrnt",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "IMDFrnt",
            path: "Sources/IMDFrnt"
        )
    ]
)
