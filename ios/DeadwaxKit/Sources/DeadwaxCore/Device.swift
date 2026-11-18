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

extension Device {
    /// What the app's words call the device they're shown on, after "this" or "the" (notes/ios.md "The Mac app, slice
    /// 4: the Mac's words"): "phone" on an iPhone - every word the phones said before the Mac, unchanged - and "Mac".
    public var noun: String {
        switch self {
        case .iPhone: return "phone"
        case .mac: return "Mac"
        }
    }

    /// "This phone", "This Mac": Settings' row and page, and a sentence's first words.
    public var this: String { "This \(noun)" }
}
