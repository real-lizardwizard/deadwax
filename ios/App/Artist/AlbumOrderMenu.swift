import DeadwaxCore
import SwiftUI

/// The Albums heading's order (Last.fm, slice A2 - deadwax-plans/lastfm.md 3.3; notes/ios.md "Last.fm, slice A2"), as
/// ArtistView judges it for both devices: the order drawn, whether Most played can be chosen, whether the menu's room is
/// held, and the choice made.
struct AlbumOrderChoice {
    /// The order drawn (AlbumPlays.Shown.order) - the menu's tick, and what VoiceOver hears as its value.
    let shown: AlbumOrder
    /// Most played can be chosen: the answer in hand has albums by plays (AlbumPlays.offered).
    let offered: Bool
    /// With Most played not offered, the menu's room is held, blank and inert, while Last.fm's answer may yet bring it
    /// (the hero's line drawn) - so the heading is one height before the answer and after.
    let room: Bool
    /// A choice in the menu, in the tap: kept per device, and Most played ordering by the answer in hand at once.
    let choose: (AlbumOrder) -> Void

    /// Nothing of Last.fm's: no menu, no room.
    static let none = AlbumOrderChoice(shown: .newest, offered: false, room: false) { (_: AlbumOrder) -> Void in }
}

/// The menu's items: its two orders, "Newest first" and "Most played" (AlbumOrder.words), the one drawn ticked - one
/// list, on either device. Each a Toggle (a menu's checkmark item) whose every tap chooses its order - the ticked one's
/// too (A2's review): a Picker never sets the value it shows, so with the visit drawn Newest first while Most played was
/// stored, Newest first couldn't be chosen, and the next artist page opened in Most played.
struct AlbumOrderItems: View {
    let choice: AlbumOrderChoice

    var body: some View {
        ForEach(AlbumOrder.allCases, id: \.self) { (order: AlbumOrder) in
            Toggle(order.words, isOn: Binding(get: { choice.shown == order },
                                               set: { (_: Bool) -> Void in choice.choose(order) }))
        }
    }
}

/// The phone's menu at the Albums heading's end (lastfm.md 3.3): the glyph `arrow.up.arrow.down`, a flat button's - the
/// accent, no face, a finger's 44 round it (DWButtonStyle's small, as See All's) - "Sort albums" to VoiceOver, the order
/// drawn its value. The Mac's is MacArtistPage's pop-up, the same items.
struct AlbumOrderMenu: View {
    let choice: AlbumOrderChoice

    var body: some View {
        Menu {
            AlbumOrderItems(choice: choice)
        } label: {
            Text(Image(systemName: "arrow.up.arrow.down"))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(DWButtonStyle(size: .small))
        .fixedSize()
        .accessibilityLabel(LastfmWords.sortAlbums)
        .accessibilityValue(choice.shown.words)
        .albumOrderRoom(choice)
    }
}

extension View {
    /// The order menu while Most played is offered; with it not, and its room held, the same menu hidden and inert
    /// (nothing to tap, nothing read); else nothing.
    @ViewBuilder func albumOrderRoom(_ choice: AlbumOrderChoice) -> some View {
        if choice.offered {
            self
        } else if choice.room {
            self
                .hidden()
                .disabled(true)
                .accessibilityHidden(true)
        }
    }
}
