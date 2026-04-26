// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PaperCodex",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PaperCodexCore", targets: ["PaperCodexCore"]),
        .executable(name: "PaperCodexApp", targets: ["PaperCodexApp"]),
        .executable(name: "PaperCodexCoreChecks", targets: ["PaperCodexCoreChecks"])
    ],
    targets: [
        .target(
            name: "PaperCodexCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "PaperCodexApp",
            dependencies: ["PaperCodexCore"]
        ),
        .executableTarget(
            name: "PaperCodexCoreChecks",
            dependencies: ["PaperCodexCore"]
        )
    ]
)
