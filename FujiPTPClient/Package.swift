// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FujiPTPClient",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FujiPTPClient", targets: ["PTPClient"]),
        .library(name: "PTPClientMacOS", targets: ["PTPClientMacOS"]),
        .library(name: "PTPClientiOS", targets: ["PTPClientiOS"]),
        .library(name: "GPhoto2CLI", targets: ["GPhoto2CLI"]),
        .library(name: "GPhoto2Wrapper", targets: ["GPhoto2Wrapper"]),
        .library(name: "X100VIHelper", targets: ["X100VIHelper"]),
        .executable(name: "GPhoto2CLITest", targets: ["GPhoto2CLITest"]),
    ],
    dependencies: [
        .package(path: "../FujiRecipesCore")
    ],
    targets: [
        .target(
            name: "PTPClient",
            dependencies: ["FujiRecipesCore"],
            path: "Sources/PTPClient"
        ),
        .target(
            name: "PTPClientMacOS",
            dependencies: ["PTPClient", "FujiRecipesCore"],
            path: "Sources/PTPClientMacOS",
            resources: [
                .process("Resources/libgphoto2")
            ]
        ),
        .target(
            name: "PTPClientiOS",
            dependencies: ["PTPClient", "FujiRecipesCore"],
            path: "Sources/PTPClientiOS"
        ),
        .target(
            name: "GPhoto2CLI",
            dependencies: ["FujiRecipesCore"],
            path: "Sources/GPhoto2CLI"
        ),
        .executableTarget(
            name: "GPhoto2CLITest",
            dependencies: ["GPhoto2CLI"],
            path: "Tests/GPhoto2CLITest"
        ),
        .target(
            name: "GPhoto2Wrapper",
            path: "Sources/GPhoto2Wrapper",
            cSettings: [
                .headerSearchPath("."),
                .unsafeFlags(["-I/opt/homebrew/include", "-I/usr/local/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-L/usr/local/lib", "-lgphoto2", "-lgphoto2_port"])
            ]
        ),
        .executableTarget(
            name: "FujiPTPHelper",
            dependencies: [
                "GPhoto2Wrapper",
                "FujiRecipesCore"
            ],
            path: "Sources/FujiPTPHelper",
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/lib", "-L/usr/local/lib", "-lgphoto2", "-lgphoto2_port"])
            ]
        ),
        .target(
            name: "X100VIHelper",
            dependencies: [
                "FujiRecipesCore"
            ],
            path: "Sources/X100VIHelper"
        ),
        .testTarget(
            name: "X100VIHelperTests",
            dependencies: ["X100VIHelper", "FujiRecipesCore"],
            path: "Tests/X100VIHelperTests"
        ),
    ]
)
