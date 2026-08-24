// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "F50Monitor",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .executable(name: "F50Monitor", targets: ["F50Monitor"]),
        .library(name: "F50Core", targets: ["F50Core"])
    ],
    targets: [
        // 共享核心层：网络抓取、解析、状态模型、凭据存储、通知
        // （macOS 菜单栏 App 与 iOS App 共用）
        .target(
            name: "F50Core",
            path: "Sources/F50Core"
        ),
        .executableTarget(
            name: "F50Monitor",
            dependencies: ["F50Core"],
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
            dependencies: ["F50Core"],
            path: "Tests/F50MonitorTests",
            resources: [.process("Fixtures")]
        )
    ]
)
