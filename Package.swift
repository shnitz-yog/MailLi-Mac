// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MailLi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MailLi", path: "Sources/MailLi")
    ]
)
