import Foundation

// The Mac app (notes/ios.md "The Mac app, slice 1: it runs and plays"): the iPhone app's own code built for the Mac
// through Mac Catalyst. Where Core's words or rules differ on a Mac, they take the device as a value - never a compile
// condition inside Core - so both are tested on Linux by `swift test`. The App says which it is, once
// (ios/App/Shared/Platform.swift: `Platform.device`).

/// The device the app runs on.
public enum Device: String, Sendable, CaseIterable {
    /// The iPhone build.
    case iPhone
    /// The Mac build (Mac Catalyst, the Mac idiom).
    case mac
}
