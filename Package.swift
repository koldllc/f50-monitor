// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "F50Monitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "F50Monitor", targets: ["F50Monitor"])
    ],
    targets: [
        .executableTarget(
            name: "F50Monitor",
            path: "Sources/F50Monitor",
            exclude: [
                "AppIcon.icns",
                "ChinaMobileLogo.svg",
                "ChinaUnicomLogo.svg",
                "ChinaTelecomLogo.svg",
                "ChinaBroadnetLogo.png"
            ]
        ),
        .testTarget(
            name: "F50MonitorTests",
            dependencies: ["F50Monitor"],
            path: "Tests/F50MonitorTests"
        )
    ]
)
