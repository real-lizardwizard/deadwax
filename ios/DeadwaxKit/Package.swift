// swift-tools-version: 6.0
//
// DeadwaxKit: the iPhone app's logic, apart from its views.
//
//   DeadwaxCore   pure Swift and Foundation - no Apple-only import - so it builds and is tested on
//                 Linux (tokay-gecko, and ios.yml's ubuntu job) as well as on a Mac.
//   DeadwaxAudio  the audio engine: AVAudioEngine and AudioToolbox. Every file is inside
//                 `#if canImport(AVFAudio)`, so on Linux it compiles to nothing; it is built and its
//                 offline-render tests run on ios.yml's macOS job.
//
// See notes/ios.md.

import PackageDescription

let package = Package(
    name: "DeadwaxKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DeadwaxCore", targets: ["DeadwaxCore"]),
        .library(name: "DeadwaxAudio", targets: ["DeadwaxAudio"]),
    ],
    targets: [
        .target(name: "DeadwaxCore"),
        // Swift 5 mode: AVFoundation's callbacks and C function pointers are written against it,
        // and nothing here can be compiled on Linux to catch a strict-concurrency error early.
        .target(name: "DeadwaxAudio", dependencies: ["DeadwaxCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DeadwaxCoreTests", dependencies: ["DeadwaxCore"]),
        .testTarget(name: "DeadwaxAudioTests", dependencies: ["DeadwaxAudio", "DeadwaxCore"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
