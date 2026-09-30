// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FujiRecipesMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FujiRecipesMac", targets: ["FujiRecipesMac"])
    ],
    dependencies: [
        .package(path: "../FujiRecipesCore"),
        .package(path: "../FujiPTPClient"),
    ],
    targets: [
        .executableTarget(
            name: "FujiRecipesMac",
            dependencies: [
                "FujiRecipesCore",
                .product(name: "X100VIHelper", package: "FujiPTPClient"),
                .product(name: "PTPClientMacOS", package: "FujiPTPClient"),
            ],
            path: "Source",
            exclude: ["Info.plist"],
            resources: [
                .process("../Resources/recipes-data.json"),
                .process("../Resources/Assets.xcassets")
            ]
        )
    ]
)
