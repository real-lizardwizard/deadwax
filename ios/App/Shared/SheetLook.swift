import DeadwaxCore
import SwiftUI

/// What the panel review's undrawn sheets, faces and banners are drawn from (the redesign, slice R18 - notes/ios.md "The
/// panel review, R18: sheets, faces and banners (2026-11-26)"; James, 26 Nov, answer 4: "the undrawn pages are drawn
/// from the canvas's pieces: flat on the phone, the Mac's boxes and groups on the Mac"). No drawing has Add to a
/// playlist, New playlist, the Library's Edit order, Choose the folder, the Navidrome gate or Can't reach deadwax, so
/// each is built from dw.css's pieces - in both devices' sizes from here, since a shared file names no Mac type
/// (tests/test_ios_mac_reach.py): the Mac's words through the look's own roles, which are the Mac's sizes there.
///
/// - `ground`: a sheet's own ground - the phone's page black (`.dw.ph`'s), the Mac's window ground (--bg).
/// - `side`: a sheet's sides and its parts' gap - the phone's pages' 16 (`.dw.ph`), and 12 between.
/// - `words`: a row's words - the phone's 16 (`.dw.ph .go`), the Mac's 13 (`.dw`'s, the look's field role).
/// - `title`: a sheet's or a page's heading - the phone's 17 (`.dw.ph`'s top's name), the Mac's 13; semibold.
/// - `small`: a line under them - the phone's 13, the Mac's 12 (`.s`, the look's small button role).
/// - `mono`: an address or a path - Courier Prime at `small` (`.mono.s`).
/// - `legend`: a group's heading - the phone's 13 (`.dw.ph .group > .legend`), the Mac's 11.5 (`.navh`, the look's chip
///   role); semibold, in the second colour (the Mac's in its label colour).
/// - `rule`: a row's hairline - the phone's #1c1b22 (`.dw.ph .row`), the Mac's --rowline.
enum SheetLook {
    static let side: CGFloat = 16
    static let gap: CGFloat = 12
    static var ground: Color { Platform.mac ? DWPalette.bg : DWPalette.page }
    static var words: Font { Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.row) }
    static var title: Font {
        (Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.topName)).weight(.semibold)
    }
    static var small: Font { Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small) }
    static var mono: Font { Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small) }
    static var legend: Font {
        (Platform.mac ? Typeface.Look.text(.chip) : Typeface.Phone.text(.legend)).weight(.semibold)
    }
    static var legendColour: Color { Platform.mac ? DWPalette.label : DWPalette.t2 }
    static var rule: Color { Platform.mac ? DWPalette.rowline : DWPalette.rowRule }
    /// A row's least height (DWLook's): the phone's 48 (`.dw.ph .row`), growing with the text; the Mac's 30 (`.row`) -
    /// its Row Size's Small, what a sheet's own window reads (MacRowSizing: a view outside the frame reads Small).
    static var rowHeight: CGFloat { CGFloat(DWLook.here.rowHeight) }
    /// A Mac row's cover in a sheet: 20 (Albums.dc.html's `.row .cover`, Row Size's Small - the one a sheet's window
    /// reads), 10 short of its 30. The phone's rows take LibraryLook.rowCover's 44 (iArtists').
    static let macCover: CGFloat = 20
}

/// A sheet's page, flat: its parts down the page `SheetLook.gap` apart, `SheetLook.side` in from each edge, in the
/// rows' words, the keyboard put away by a drag - on the sheet's own ground, behind its bar too (no sheet's grey above
/// or below it, as the manual search's and People's sheets are).
struct SheetPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SheetLook.gap) {
                content
            }
            .font(SheetLook.words)
            .foregroundStyle(DWPalette.text)
            .padding(.horizontal, SheetLook.side)
            .padding(.vertical, SheetLook.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SheetLook.ground.ignoresSafeArea())
    }
}

/// Rows in a sheet: on the phone straight on the page, each over its hairline (`.dw.ph .row`), no fill; on the Mac a box
/// (dw.css's `.box`: the raised ground, the line's edge, a box's corners) holding them, each over the rowline but the
/// last, whose falls under the box's edge.
struct SheetRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if Platform.mac {
            VStack(spacing: 0) {
                content
            }
            // the last row's line under the box's edge, clipped
            .padding(.bottom, -1)
            .clipped()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DWPalette.card, in: DWCorners.boxShape)
            .clipShape(DWCorners.boxShape)
            .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))
        } else {
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension View {
    /// One of SheetRows' rows: at its least height, its words 10 in on the Mac (`.row > div`'s padding) and at the page's
    /// edge on the phone, over the row's hairline.
    func sheetRow() -> some View {
        padding(.horizontal, Platform.mac ? 10 : 0)
            .frame(maxWidth: .infinity, minHeight: SheetLook.rowHeight, alignment: .leading)
            .overlay(alignment: .bottom) { DWRule(colour: SheetLook.rule) }
    }
}

/// A sheet's buttons, side by side - or (the largest text sizes) one over the other, each the width of the page, its
/// words up to three lines, as every flat page stacks its own.
struct SheetButtons<Content: View>: View {
    @ViewBuilder let content: (_ stacked: Bool) -> Content

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        if stacked {
            VStack(alignment: .leading, spacing: 10) {
                content(true)
            }
        } else {
            HStack(spacing: 12) {
                content(false)
            }
        }
    }
}

/// A button's words: one line, three at the accessibility sizes (where its button fills the page's width).
struct SheetButtonWords: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(text)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
