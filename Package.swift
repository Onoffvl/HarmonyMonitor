// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HarmonyCore",
    products: [.library(name: "HarmonyCore", targets: ["HarmonyCore"])],
    targets: [
        .target(name: "HarmonyCore", path: "HarmonyCore"),
        .testTarget(name: "HarmonyCoreTests", dependencies: ["HarmonyCore"])
    ]
)
