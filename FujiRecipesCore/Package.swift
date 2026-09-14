// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FujiRecipesCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FujiRecipesCore", targets: ["FujiRecipesCore"])
    ],
    targets: [
        .target(
            name: "FujiRecipesCore",
            path: "Sources/FujiRecipesCore"
        ),
        .testTarget(
            name: "FujiRecipesCoreTests",
            dependencies: ["FujiRecipesCore"],
            path: "Tests/FujiRecipesCoreTests"
        )
    ]
)
