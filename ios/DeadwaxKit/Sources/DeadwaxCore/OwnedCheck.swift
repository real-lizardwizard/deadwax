import Foundation

/// (Speed A, fix 5 - notes/ios.md "Speed A: what's asked again") Whether an artist page, as it opens, asks the library
/// which albums are yours (`/library/owned`) again: only when the index isn't in hand - as the album page asks - or a write
/// deadwax was told of (an Edit's apply, a delete, a re-file, a Get) has come since an artist page last asked. A pull asks
/// regardless, and so do the page's own writes (a Move); another person starts with no index in hand.
public enum OwnedCheck {
    /// `inHand` whether the index is; `writes` the writes told of now; `askedUnder` the writes an artist page last
    /// asked under (nil for none since the person signed in).
    public static func asks(inHand: Bool, writes: Int, askedUnder: Int?) -> Bool {
        !inHand || askedUnder != writes
    }
}
