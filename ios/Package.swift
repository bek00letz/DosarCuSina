// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DosarCuSina",
    defaultLocalization: "ro",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DosarCuSinaCore",
            targets: ["DosarCuSinaCore"]
        )
    ],
    targets: [
        .target(
            name: "DosarCuSinaCore",
            path: "DosarCuSina"
        )
    ]
)
