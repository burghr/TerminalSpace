// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TerminalSpace",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.20.0")
    ],
    targets: [
        .executableTarget(
            name: "TerminalSpace",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
