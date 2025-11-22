// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SFParkingZoneFinder",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SFParkingZoneFinder",
            targets: ["SFParkingZoneFinder"]
        ),
    ],
    dependencies: [
        // Google Maps SDK for iOS
        .package(
            url: "https://github.com/nicklockwood/SwiftFormat",
            from: "0.52.0"
        ),
    ],
    targets: [
        .target(
            name: "SFParkingZoneFinder",
            dependencies: [],
            path: "SFParkingZoneFinder"
        ),
        .testTarget(
            name: "SFParkingZoneFinderTests",
            dependencies: ["SFParkingZoneFinder"],
            path: "SFParkingZoneFinderTests"
        ),
    ]
)

// Note: Google Maps SDK must be added via Xcode SPM UI or CocoaPods
// URL: https://github.com/nicklockwood/SwiftFormat (for development)
// Google Maps: Add via Xcode: File > Add Package Dependencies
//   URL: https://github.com/nicklockwood/GoogleMaps-iOS-SDK (unofficial)
//   Or use official CocoaPods: pod 'GoogleMaps'
