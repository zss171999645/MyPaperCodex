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
        .executable(name: "CodeArxivFavoritesMigrator", targets: ["CodeArxivFavoritesMigrator"]),
        .executable(name: "PaperCodexCoreChecks", targets: ["PaperCodexCoreChecks"]),
        .executable(name: "PaperCodexSearchChecks", targets: ["PaperCodexSearchChecks"])
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
            dependencies: ["PaperCodexCore"],
            exclude: ["Resources"]
        ),
        .executableTarget(
            name: "CodeArxivFavoritesMigrator",
            dependencies: ["PaperCodexCore"]
        ),
        .executableTarget(
            name: "PaperCodexCoreChecks",
            dependencies: ["PaperCodexCore"]
        ),
        .executableTarget(
            name: "PaperCodexSearchChecks",
            dependencies: ["PaperCodexCore"]
        )
    ]
)
