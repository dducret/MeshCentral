// swift-tools-version: 5.9
// SPDX-License-Identifier: Apache-2.0
import PackageDescription

let package = Package(
    name: "MeshCentralAgent",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "MeshCentralAgent", targets: ["MeshCentralAgent"])],
    targets: [
        .binaryTarget(name: "CMeshCore", path: "Artifacts/MeshCore.xcframework"),
        .target(name: "MeshCentralAgent", dependencies: ["CMeshCore"]),
        .testTarget(name: "MeshCentralAgentTests", dependencies: ["MeshCentralAgent", "CMeshCore"])
    ]
)
