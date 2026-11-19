// swift-tools-version:5.9
import PackageDescription

// The app's logic, kept free of UIKit/SwiftUI so it builds and tests on macOS, iOS and Linux alike.
//  - MGKit:  MG India i-SMART client (login, status, charging, remote commands).
//  - EVCore: car models, battery profile, pre-cool decision and what the app learns about the car.
//  - OpenMeteo: current weather from Open-Meteo (free for non-commercial use, no key).
// PlannerKit (energy model, trips) and MapsKit (Google routes, places) join in milestone 2.
let package = Package(
    name: "MGEVKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MGKit", targets: ["MGKit"]),
        .library(name: "EVCore", targets: ["EVCore"]),
        .library(name: "OpenMeteo", targets: ["OpenMeteo"]),
    ],
    dependencies: [
        // CryptoKit on Apple platforms, BoringSSL elsewhere; _CryptoExtras adds AES-CBC, which MG's gateway uses.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "4.0.0"),
    ],
    targets: [
        .target(
            name: "MGKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .target(name: "OpenMeteo"),
        .target(name: "EVCore", dependencies: ["MGKit", "OpenMeteo"]),
        .testTarget(
            name: "MGKitTests",
            dependencies: ["MGKit"],
            resources: [.copy("Resources/ismart_vectors.json")]
        ),
        .testTarget(name: "EVCoreTests", dependencies: ["EVCore"]),
        .testTarget(name: "OpenMeteoTests", dependencies: ["OpenMeteo"]),
    ]
)
