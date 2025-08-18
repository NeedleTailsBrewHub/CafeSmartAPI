// swift-tools-version:6.1
import PackageDescription

let package = Package(
  name: "cafe-smart-api",
  platforms: [
    .macOS(.v13)
  ],
  dependencies: [
    // 💧 A server-side Swift web framework.
    .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
    // 🔵 Non-blocking, event-driven networking for Swift. Used for custom executors
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    .package(
      url: "https://github.com/brokenhandsio/VaporSecurityHeaders.git",
      .upToNextMajor(from: "4.2.0")),
    .package(url: "https://github.com/swiftpackages/DotEnv.git", .upToNextMajor(from: "3.0.0")),
    .package(url: "https://github.com/orlandos-nl/MongoKitten.git", .upToNextMajor(from: "7.9.4")),
    .package(url: "https://github.com/vapor/jwt.git", .upToNextMajor(from: "5.0.0")),
    .package(url: "https://github.com/NeedleTailsBrewHub/swift-onnx-runtime.git", branch: "main")
  ],
  targets: [
    .executableTarget(
      name: "cafe-smart-api",
      dependencies: [
        .product(name: "Vapor", package: "vapor"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "MongoKitten", package: "MongoKitten"),
        .product(name: "Meow", package: "MongoKitten"),
        .product(name: "VaporSecurityHeaders", package: "VaporSecurityHeaders"),
        .product(name: "JWT", package: "jwt"),
        .product(name: "DotEnv", package: "DotEnv"),
        .product(name: "CONNX", package: "swift-onnx-runtime", condition: .when(platforms: [.linux]))
      ],
      path: "Sources/App",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "ApiTests",
      dependencies: [
        .target(name: "cafe-smart-api")
      ],
      swiftSettings: swiftSettings
    ),
  ]
)

var swiftSettings: [SwiftSetting] {
  [
    .enableUpcomingFeature("ExistentialAny")
  ]
}
