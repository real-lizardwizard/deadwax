import SwiftUI

/// The app's corners, one set for every screen (the squared look, 14 Nov - notes/ios.md "The squared look"). James, on
/// app 0.11: "let's square everything off a bit more, especially the album arts". So every rounded rectangle in the app
/// takes one of these, and nothing in ios/App writes a radius of its own (tests/test_ios_palette.py holds that):
///
/// - `art`: every cover - an album's, a playlist's, a song's - wherever it is drawn: the album and playlist pages' hero,
///   Now Playing's cover, the tiles, the rows, the play bar's cover, the cards of Up Next and Info.
/// - `card`: what sits over the page or in it as a panel - the notice, the first ask, a list that
///   couldn't be asked again, the sign-in's reason, the song you searched for on its album.
/// - `control`: what a finger takes - buttons (the primary and the secondary pill, PrimaryFace), chips, pills, badges,
///   fields, the Library's switch and its segments.
/// - `track` and `fill`: a bar's sunken track and the fill inside it (the web's --dw-radius-track and -fill).
///
/// Actual corners (15 Nov, James: "let's square off everything already square a bit more. Actual corners. ... I like
/// the square look." - notes/ios.md "Actual corners"): every one is 0, so all of them are truly square; they stay
/// named, so what each is for stays said, and a corner can come back to one kind without touching the others.
///
/// Round stays round: dots, the avatar, artists' pictures, the rings, a slider's knob, the Library's two buttons at its
/// top ("the search button and options button at the top can be circles"), Requests' round ▶ and ✕. The turntable keeps
/// its own corners (TurntableFace.lookRadius - the plinth, the look button, the speed chip), and the app icon is left
/// alone.
///
/// Against the web (theme.css section 10): the web's --dw-radius-cover is 3, --dw-radius-card 6, --dw-radius-control 4
/// (PrimaryButton.radius keeps it, the web's number), --dw-radius-track 2 and --dw-radius-fill 1 - the phone is square
/// where the web is rounded, on purpose, as James asked of the phone.
enum Corners {
    /// Covers.
    static let art: CGFloat = 0
    /// Panels and cards. (The mini player was one until it joined the tab bar, square, on 15 Nov.)
    static let card: CGFloat = 0
    /// Buttons, chips, pills, fields, the switch.
    static let control: CGFloat = 0
    /// A bar's track.
    static let track: CGFloat = 0
    /// The fill inside a bar's track.
    static let fill: CGFloat = 0

    /// The shapes: rounded rectangles of these radii (so square), each an InsettableShape as before.
    static var artShape: RoundedRectangle { RoundedRectangle(cornerRadius: art, style: .continuous) }
    static var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: card, style: .continuous) }
    static var controlShape: RoundedRectangle { RoundedRectangle(cornerRadius: control, style: .continuous) }
    static var trackShape: RoundedRectangle { RoundedRectangle(cornerRadius: track, style: .continuous) }
    static var fillShape: RoundedRectangle { RoundedRectangle(cornerRadius: fill, style: .continuous) }

    /// A system button's border (`.bordered`, PasteButton) squared to a control's.
    static let controlBorder = ButtonBorderShape.roundedRectangle(radius: control)
}
