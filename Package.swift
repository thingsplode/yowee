// swift-tools-version: 5.10
import PackageDescription

let testingFrameworkPath = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let testingLibPath = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "yowee",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", .upToNextMajor(from: "0.9.0")),
    ],
    targets: [
        // Pure-logic library — no SwiftData/SwiftUI macros; builds with swift build and swift test.
        .target(
            name: "YoweeCore",
            path: "Sources/YoweeCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                // Allow @testable imports from TestRunner executable.
                .unsafeFlags(["-enable-testing"]),
            ]
        ),
        // macOS app — requires Xcode (SwiftData @Model macros need Xcode's compiler plugin infrastructure).
        // `swift build` without Xcode will fail on this target; use `swift run TestRunner` for CLI tests.
        .executableTarget(
            name: "yowee",
            dependencies: [
                "YoweeCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/yowee"
        ),
        // Standalone test runner: `swift run TestRunner` — works without Xcode's swiftpm_testing_helper.
        // Sources symlink to Tests/YoweeTests/ so the same files serve both this target and Xcode.
        .executableTarget(
            name: "TestRunner",
            dependencies: ["YoweeCore"],
            path: "Sources/TestRunner",
            swiftSettings: [
                .unsafeFlags([
                    "-F", testingFrameworkPath,
                    "-enable-testing",
                    "-plugin-path",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", testingFrameworkPath,
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", testingFrameworkPath,
                    "-Xlinker", "-rpath",
                    "-Xlinker", testingLibPath,
                ]),
            ]
        ),
        // testTarget kept for `xcodebuild test` (Xcode has swiftpm_testing_helper; CLT does not).
        .testTarget(
            name: "YoweeTests",
            dependencies: ["YoweeCore"],
            path: "Tests/YoweeTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", testingFrameworkPath,
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", testingFrameworkPath,
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", testingFrameworkPath,
                    "-Xlinker", "-rpath",
                    "-Xlinker", testingLibPath,
                ]),
            ]
        ),
    ]
)
