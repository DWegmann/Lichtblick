// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RatingCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "RatingCore", targets: ["RatingCore"])],
    targets: [
        .target(name: "RatingCore"),
        .testTarget(name: "RatingCoreTests", dependencies: ["RatingCore"]),
        .target(name: "CredentialSupport", path: "SMBRating/Services",
                exclude: ["DemoStore.swift", "ImagePipeline.swift", "SMBStore.swift", "ReadBackgroundRuntime.swift"],
                sources: ["CredentialStore.swift"]),
        .testTarget(name: "CredentialSupportTests", dependencies: ["CredentialSupport"])
    ]
)
