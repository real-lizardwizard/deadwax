// swift-tools-version: 6.0
//
// DeadwaxKit: the iPhone app's logic, apart from its views.
//
//   DeadwaxCore   pure Swift and Foundation - no Apple-only import - so it builds and is tested on
//                 Linux (tokay-gecko, and ios.yml's ubuntu job) as well as on a Mac. Its download store reads
//                 SQLite through CSQLite (libsqlite3-dev on Linux).
//   DeadwaxAudio  the audio engine: AVAudioEngine and AudioToolbox. Every file is inside
//                 `#if canImport(AVFAudio)`, so on Linux it compiles to nothing; it is built and its
//                 offline-render tests run on ios.yml's macOS job.
//   CAudioRing    C11 atomics for the real-time renders (the EQ's triple buffer and counters; the turntable's
//                 rings): indices and bits, no floating point, nothing Apple's - so it builds on Linux too.
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
        // SQLite, for the download store (Phase 2): the system's own - Apple's SDKs carry it, and Linux gets it from
        // libsqlite3-dev (ios.yml's ubuntu job installs it). A system library, so the products are unchanged.
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "DeadwaxCore", dependencies: ["CSQLite"]),
        // The real-time renders' atomics (eq.md 1.6; 8, question 1): Synchronization's Atomic needs iOS 18.
        .target(name: "CAudioRing"),
        // Swift 5 mode: AVFoundation's callbacks and C function pointers are written against it,
        // and nothing here can be compiled on Linux to catch a strict-concurrency error early.
        .target(name: "DeadwaxAudio", dependencies: ["DeadwaxCore", "CAudioRing"],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        // Test-only: the allocation detector the real-time tests use (turntable.md 4.3, built first for the EQ's
        // EQRealTimeTests). No product, so the app never links it; stubs off Apple's platforms.
        .target(name: "CAllocHook", path: "Tests/CAllocHook"),
        // Fixtures/: what the Swift tests replay - traces recorded from the web app's own TypeScript and
        // vectors shared with the Python suite (ios/scripts/export-traces.cjs writes them). One folder
        // per area; read by Fixtures.url (Tests/DeadwaxCoreTests/FixtureFiles.swift): from the checkout,
        // else this copy in the test bundle.
        .testTarget(name: "DeadwaxCoreTests", dependencies: ["DeadwaxCore"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "DeadwaxAudioTests", dependencies: ["DeadwaxAudio", "DeadwaxCore", "CAudioRing", "CAllocHook"],
                    resources: [.copy("Fixtures")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
