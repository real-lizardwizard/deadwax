import DeadwaxCore
import SwiftUI

/// Up Next (ui/src/app/UpNext.tsx), a sheet over Now Playing: what Core's `upNextView` says is to be drawn, and
/// nothing else - History, the songs already played, oldest first (2.1.3); the song playing (and, with Repeat One,
/// that it repeats); Shuffle and Repeat; Playing Next, with Clear, when songs have been added; the rest of the album or
/// list this time round, then "And N more songs."; and what comes after. Neither Repeat One's copies nor the later
/// times round are drawn.
///
/// A row's tap plays it now (PlayerModel.jump, by the row's key: a song in twice is two rows, and a key gone does
/// nothing); the songs it passes stay behind it, where Previous and History find them (James, 2026-11-11). A row of
/// History's - "{title}, play again" - ROLLS BACK to it (the web's 2.1.18, James: "so it just moves back up the list"):
/// the one list keeps its order, the playing point moves up to the row, and every row below it is to come, as drawn.
/// Nothing above the row changes, so with the scroll held the card - the row tapped, now playing - is where the row
/// was, under the finger; VoiceOver's focus goes to what plays next (the first row under the card, Done with none) and
/// "Playing {title}" is said - only once the jump took. History is hidden in Edit, and has no moves or removals. Edit
/// gives each row Move up, Move down and Remove - as VoiceOver actions, and as the List's own drag handle and the row's
/// own red (-), which takes the song out at once - each change made as it is made, a move staying in its group. Out of
/// Edit a row can't be swiped away, so a song isn't lost by a stray swipe; in Edit iOS offers no swipe (a List in Edit
/// takes none - notes/ios.md, "Up Next: one tap to take a song out"), so the (-) is the one action, in place of the
/// system's two (its (-), then Delete). What changed is read out, and VoiceOver's focus goes where the web's goes
/// (Pinned's rule): a moved row where it went; after a removal the next row, the one before at the end, Done with none;
/// Clear to the Shuffle chip; Edit to Done; a row's tap to the row after it - after a list row's, Playing Next's head,
/// carried after it - (Playing Next's last to the list's first), or Done, once the card is back at the top so it lands
/// in view. Each opening starts at the song playing, History above it scrolled up to, out of Edit; the song playing put
/// back at the top whenever it changes (a song's end, Next, Previous, an Up Next row's tap) or Edit goes on or off -
/// never for Shuffle, Repeat, Clear or Edit's moves, and not after a tap above the card (a roll-back). A bottom margin
/// lets the card reach the top near an album's end, where scrollTo would stop short. Done ends Edit, else closes; the
/// sheet closes by itself once nothing is queued.
///
/// PLAY HISTORY THAT LASTS (app 0.8; the web's 2.1.15, notes/ios.md "Play history on the phone" - James: "so you can
/// always look back and see what you played yesterday"): above History, ONE CONTINUOUS LIST goes on back through every
/// song the person has played, on this phone and on the web - no headings at all (History's own is gone too), no
/// times, skips drawn like plays. HistoryModel holds deadwax's pages and this phone's own starts; Core's
/// PlayHistory.pastRows leaves out every start the queue's own rows draw, so each is drawn once. Its next older page is
/// asked for as one of the list's first rows comes into view once the sheet has been placed at the song playing - a
/// spinner over the list's top while it comes, said in a listener's words with Try again if it can't (ErrorWords) -
/// and anything landing above what is in view holds the view where it was: the topmost row in view put back at the
/// top. (The web's 2.1.18) An older row's tap rolls back to it, as History's does (PlayerModel.rollBack): it and every
/// older row below it come back into the queue ahead of History's songs, and it plays - drawn as songs to come, never
/// above as well. The card is where the row was, focus to what plays next, "Playing {title}" said. Hidden in Edit.
///
/// Phase 2 (phase2-downloads.md 4.3.1): every song carries its download mark at the end of its line (the album row's
/// DownloadMark, outside the line's words), in Edit too; and while deadwax can't be reached, a song not on this phone
/// is dimmed - not a button out of Edit, its minus and handle still whole in it; the song playing's card is marked,
/// never dimmed. VoiceOver hears the state as the row's value. No download control here. The mark and the dim are
/// small views of their own, so a download's progress redraws them, never this list.
///
/// RADIO AND AUTOPLAY (Last.fm, slice A3 - deadwax-plans/lastfm.md 3.5; notes/ios.md "Last.fm, slice A3"): while Last.fm
/// is on, "Autoplay" after Repeat - on the phone the foot's flat button as Shuffle's and Repeat's, on the Mac (R16) the
/// dock header's `.btn.sm` - lit and "selected" while on, its hint "Keeps playing similar songs from your library when the
/// queue ends." Off by default. The rows Autoplay gave the queue, the list's tail, are drawn under a heading of their
/// own, "Autoplay" (Core's Station.split), after the list's own under its title; a radio's songs are the list itself.
/// They come out in Edit as any of the list's rows, and move among themselves (a drag stays under its heading, as it
/// stays in its group; the move is made in the whole list's places). Shuffle is dimmed while the queue has a station,
/// as during a library's shuffle.
///
/// (The panel review's R16 - notes/ios.md "The panel review, R16: the Mac's dock tabs (2026-11-26)"; Album.dc.html's
/// panel) In the Mac's dock no bar, no title, no Done - Escape is the panel's (MacPanel), and Done's while in Edit: a
/// DockHeader with Shuffle, Repeat and Autoplay as `.btn.sm`s lit while on, History and Clear at the right (in a •••
/// where the panel's 400 can't hold them all), then Edit (Done in it); `.navh` headings - Playing, Playing Next, "Next
/// from …", Autoplay - over the song playing (a row 44 tall on the selection's ground at a box's corners) and the rows,
/// each at View ▸ Row Size's height (DockQueueRow); the time left at the foot as before.
struct UpNextScreen: View {
    /// (R3b) In the sheet over Now Playing (iQueue): `‹ Now Playing` and the strip at its top, History, Clear and Edit at
    /// the top's right, the song playing as the selected row first - (R3b's review) no heading over it, nor over
    /// Playing Next's songs after it: the top has said where the page is - "Next from …" over the list, rows 48 tall,
    /// and Shuffle, Repeat and the time left at its foot. Nil in the Mac's side panel (R16: the dock's header, `.navh`s
    /// and rows), with the time left at its foot in the Mac's look.
    var sheet: SheetTop?

    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(HistoryModel.self) private var history
    @Environment(Reachability.self) private var reachability
    @Environment(ServerModel.self) private var server
    @Environment(\.dismiss) private var dismiss
    /// (The Mac app, slice 3) Drawn in the desktop frame's side panel: Done puts the panel away (MacPanel).
    @Environment(\.inSidePanel) private var inSidePanel
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editing = false
    /// The entry a roll-back moved to (a tap above the card): its change of song keeps the scroll where it is - nothing
    /// above the row tapped changed, so the card is where the row was, under the finger.
    @State private var holdAt: Int?
    /// Where an Up Next row's tap sends VoiceOver's focus - what plays next - set once the card is back at the top, so
    /// it lands on a row in view (the web's "so focus lands in view"): History grew above the card, which pushed the
    /// row down, maybe out of the List's drawn cells, until the scroll.
    @State private var focusAtCard: Focus?
    @AccessibilityFocusState private var focus: Focus?
    /// (app 0.8) The rows in view, and whether the sheet has been placed at the song playing - kept outside SwiftUI's
    /// state, so scrolling redraws nothing.
    @State private var seen = Seen()

    /// Where VoiceOver's focus goes after a change.
    enum Focus: Hashable {
        case row(Int)
        /// (app 0.8) an older row's, by its key
        case past(String)
        case done
        case shuffle
    }

    /// What is drawn above the song playing, and the moments it changes for anything else - what the view is held
    /// through (`hold`).
    private struct Above: Equatable {
        let past: [String]
        let failed: Bool
        let playing: Int?
        let editing: Bool
    }

    /// The rows in view (the older rows by key, History's and the queue's by theirs, the card), by their own
    /// onAppear and onDisappear.
    @MainActor
    private final class Seen {
        var ids: Set<AnyHashable> = []
        /// the sheet has been scrolled to the song playing once: rows above it seen since were scrolled to
        var placed = false
    }

    /// (R3b) The phone's selected row's cover, iQueue's `.row.tall .cover` (44): its rows have none - (R16) nor the
    /// dock's, whose song playing's is DockLook's.
    private static let rowCover: CGFloat = 44
    /// (R3b) iQueue: its rows' sides (`.row > div` padding 16; the Mac's dock's 10), the heading's room under its words
    /// (`.row.grp` padding-bottom 6), and the foot (`.f` height 60, gap 8, padding 0 16px).
    private static let side: CGFloat = 16
    private static let macSide: CGFloat = 10
    private static let headingFoot: CGFloat = 6
    private static let foot: Double = 60
    private static let footGap: CGFloat = 8
    /// The song playing's card, scrolled to the top - (R3b) on the phone its row.
    private static let card = "playing"
    /// Lower bounds of the card with the chips under it, and of a row - so the bottom margin made from them is never
    /// too little for the card to reach the top (at most a little more than needed).
    private static let cardAtLeast: CGFloat = 120
    private static let rowAtLeast: CGFloat = 56

    init(sheet: SheetTop? = nil) {
        self.sheet = sheet
    }

    /// (R3b) The phone's page, iQueue's: in the sheet's top, with its own rows.
    private var phone: Bool { sheet != nil }

    var body: some View {
        let view = player.upNext
        let listRows = view.list?.rows ?? []
        let editable = !view.added.isEmpty || !listRows.isEmpty
        //? (app 0.8) the older rows above History - none in Edit - each start drawn once (PlayHistory.pastRows)
        let past = editing || view.playing == nil ? [] : PlayHistory.pastRows(history.plays, queue: player.queue)
        let failure = editing ? nil : history.failure
        let above = Above(past: past.map(\.key), failed: failure != nil, playing: playingKey, editing: editing)
        NavigationStack {
            GeometryReader { space in
                ScrollViewReader { proxy in
                    List {
                        if let playing = view.playing {
                            //? (2.1.3) the songs already played, above the song playing - scrolled up to; not in Edit.
                            //? (app 0.8) One list with no heading: every song played before, oldest at the top, then
                            //? the queue's own History
                            if !editing && (!past.isEmpty || !view.history.isEmpty || failure != nil) {
                                Section {
                                    if let failure {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ErrorNote(failure, failed: UpNextWords.earlierFailed, retry: true)
                                            Button(UpNextWords.tryAgain) { history.retry() }
                                                .modifier(QueueTryAgain(phone: phone))
                                        }
                                        .modifier(QueuePhoneNote(phone: phone, side: Self.side))
                                    }
                                    ForEach(Array(past.enumerated()), id: \.element.key) { index, row in
                                        pastRow(row)
                                            .accessibilityFocused($focus, equals: .past(row.key))
                                            .onAppear { appeared(row.key, at: index) }
                                            .onDisappear { seen.ids.remove(row.key) }
                                    }
                                    ForEach(Array(view.history.enumerated()), id: \.element.key) { index, row in
                                        historyRow(row)
                                            .accessibilityFocused($focus, equals: .row(row.key))
                                            .onAppear { appeared(row.key, at: past.count + index) }
                                            .onDisappear { seen.ids.remove(row.key) }
                                    }
                                }
                            }

                            Section {
                                if phone {
                                    //? (R3b's review) the selected row first, no heading over it: `‹ Now Playing`
                                    //? over the strip has said it
                                    playingRow(playing)
                                        .id(Self.card)
                                        .onAppear { seen.ids.insert(Self.card) }
                                        .onDisappear { seen.ids.remove(Self.card) }
                                } else {
                                    //? (R16) the dock's: under its `.navh`, the selected row - Shuffle and Repeat are
                                    //? the dock's header's
                                    macHeading(MacDock.Words.playing)
                                    macPlaying(playing)
                                        .id(Self.card)
                                        .onAppear { seen.ids.insert(Self.card) }
                                        .onDisappear { seen.ids.remove(Self.card) }
                                }
                                if view.repeatOne {
                                    note(UpNextWords.repeatingOne)
                                }
                                if player.paged != nil {
                                    note(UpNextWords.shufflingLibrary)
                                }
                            }

                            if !view.added.isEmpty {
                                if phone {
                                    //? (R3b's review) no heading: Playing Next's songs follow the song playing, each
                                    //? with its artist and album, the album's own rows under "Next from …" after them
                                    Section {
                                        rows(view.added, lines: true) { index in
                                            view.added.indices.contains(index + 1) ? view.added[index + 1] : listRows.first
                                        }
                                    }
                                } else {
                                    //? (R16) under its `.navh`; Clear is the dock's header's
                                    Section {
                                        macHeading(UpNextWords.playingNext)
                                        rows(view.added, lines: true) { index in
                                            view.added.indices.contains(index + 1) ? view.added[index + 1] : listRows.first
                                        }
                                    }
                                }
                            }

                            if let whole = view.list {
                                //? (Last.fm, A3) the list's own rows under its title, then Autoplay's under theirs -
                                //? one group of rows, drawn in two parts (`part`), so a move or a removal is the list's
                                let split = player.stationSplit(whole)
                                let own = split.list?.rows.count ?? 0
                                if phone {
                                    if let list = split.list {
                                        Section {
                                            heading(QueuePageWords.heading(list.title))
                                            //? (2.1.3) Playing Next is carried after a list row tapped: what plays next
                                            //? is its head. (R3b) Under an album's heading its rows are their titles.
                                            rows(whole.rows, lines: QueuePageWords.showsLines(list.rows, title: list.title),
                                                 part: 0..<own) { index in
                                                view.added.first ?? (whole.rows.indices.contains(index + 1) ? whole.rows[index + 1] : nil)
                                            }
                                            if list.more > 0 {
                                                note(UpNextWords.more(list.more))
                                            }
                                        }
                                    }
                                    if !split.autoplay.isEmpty {
                                        Section {
                                            heading(LastfmWords.autoplay)
                                            rows(whole.rows, lines: true, part: own..<whole.rows.count) { index in
                                                view.added.first ?? (whole.rows.indices.contains(index + 1) ? whole.rows[index + 1] : nil)
                                            }
                                        }
                                    }
                                } else {
                                    //? (R16) Album.dc.html's: "Next from …" a `.navh` over the list's rows - an album's
                                    //? its titles, as the phone's - then Autoplay's under theirs
                                    if let list = split.list {
                                        Section {
                                            macHeading(QueuePageWords.heading(list.title))
                                            //? (2.1.3) Playing Next is carried after a list row tapped: what plays next
                                            //? is its head
                                            rows(whole.rows, lines: QueuePageWords.showsLines(list.rows, title: list.title),
                                                 part: 0..<own) { index in
                                                view.added.first ?? (whole.rows.indices.contains(index + 1) ? whole.rows[index + 1] : nil)
                                            }
                                            if list.more > 0 {
                                                note(UpNextWords.more(list.more))
                                            }
                                        }
                                    }
                                    if !split.autoplay.isEmpty {
                                        Section {
                                            macHeading(LastfmWords.autoplay)
                                            rows(whole.rows, lines: true, part: own..<whole.rows.count) { index in
                                                view.added.first ?? (whole.rows.indices.contains(index + 1) ? whole.rows[index + 1] : nil)
                                            }
                                        }
                                    }
                                }
                            }

                            if let then = view.then {
                                Section {
                                    note(then)
                                }
                            }
                        }
                    }
                    .modifier(QueueListLook(phone: phone))
                    //? near an album's end the card can't reach the top - scrollTo stops where the content ends - so room
                    //? below it, from lower bounds of what follows the card: never too little, at most a little more
                    .contentMargins(.bottom, room(space.size.height, view), for: .scrollContent)
                    .environment(\.editMode, .constant(editing ? .active : .inactive))
                    //? (app 0.8) an older page on its way: over the list's top, so nothing in it moves
                    .overlay(alignment: .top) {
                        if history.loading && !editing {
                            //? (R16) on the look's card, both devices - no material
                            ProgressView()
                                .padding(10)
                                .background(DWPalette.card, in: DWCorners.boxShape)
                                .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line))
                                .padding(.top, 8)
                                .accessibilityLabel(UpNextWords.loadingEarlier)
                        }
                    }
                    //? (R3b) the time left at the foot: on the phone with Shuffle and Repeat (iQueue's), on the Mac in
                    //? the dock's look
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if phone {
                            phoneFoot(view)
                        } else {
                            macFoot(view)
                        }
                    }
                    .onAppear {
                        toCard(proxy)
                        history.opened()
                    }
                    .onChange(of: above) { old, now in hold(old, now, view, proxy) }
                    .onChange(of: scenePhase) { _, phase in
                        //? back at the front: what the web played meanwhile
                        if phase == .active { history.refresh() }
                    }
                    //? the network back: the newest page, not asked offline
                    .onChange(of: reachability.online) { _, online in
                        if online { history.refresh() }
                    }
                    //? an older page landed with the rows near the top still in view: none came into view to ask for
                    //? the next, so it is asked for here
                    .onChange(of: history.landed) { _, _ in askAgainNearTop() }
                    .onChange(of: playingKey) { _, now in
                        let target = focusAtCard
                        focusAtCard = nil
                        if let held = holdAt, held == now {
                            holdAt = nil
                            return
                        }
                        holdAt = nil
                        toCard(proxy, then: target)
                    }
                    .onChange(of: editing) { _, _ in toCard(proxy) }
                    .queueTop(sheet) {
                        phoneTop(view, editable: editable, earlier: !past.isEmpty || !view.history.isEmpty, proxy: proxy)
                    } mac: {
                        macTop(view, editable: editable, earlier: !past.isEmpty || !view.history.isEmpty, proxy: proxy)
                    }
                }
            }
        }
        // the marks' progress, once for the sheet (it asks the session only while something is fetching)
        .task { await downloads.followProgress() }
        .onChange(of: player.hasQueue) { _, queued in
            if !queued { close() }
        }
        .onChange(of: editable) { _, can in
            if !can { editing = false }
        }
    }

    /// Put away: the sheet over Now Playing, or (the Mac app, slice 3) the desktop frame's side panel.
    private func close() {
        if inSidePanel { navigation.closePanel() } else { dismiss() }
    }

    // MARK: the tops (R3b)

    /// (R16) The Mac's dock's header (Album.dc.html's): Shuffle, Repeat and Autoplay at the left (macModes); History
    /// and Clear at the right, out of Edit - in a ••• where the panel's 400 can't hold them beside the three (Autoplay
    /// with "Repeat one": test_ios_dock_look.py works it out); then Edit, Done while editing - focused after a change with
    /// nothing left to focus, dimmed with nothing to edit, and Escape's while editing, which holds the panel's Escape
    /// (`dockHoldsEscape`) so Escape ends Edit before it puts the panel away.
    private func macTop(_ view: UpNextView, editable: Bool, earlier: Bool, proxy: ScrollViewProxy) -> some View {
        let clearable = !view.added.isEmpty
        return DockHeader {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DockLook.headerGap) {
                    macModes
                    Spacer(minLength: 0)
                    if !editing {
                        Button(UpNextWords.history) { toHistory(proxy) }
                            .disabled(!earlier)
                        Button(UpNextWords.clear, action: clear)
                            .disabled(!clearable)
                    }
                }
                HStack(spacing: DockLook.headerGap) {
                    macModes
                    Spacer(minLength: 0)
                    if !editing {
                        Menu {
                            Button(UpNextWords.history) { toHistory(proxy) }
                                .disabled(!earlier)
                            Button(UpNextWords.clear, action: clear)
                                .disabled(!clearable)
                        } label: {
                            Image(systemName: "ellipsis")
                                .accessibilityLabel(QueuePageWords.more)
                        }
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
            }
        } trailing: {
            Button(editing ? UpNextWords.done : UpNextWords.edit) {
                if editing {
                    editing = false
                } else {
                    editing = true
                    refocus(.done)
                }
            }
            .disabled(!editing && !editable)
            .accessibilityFocused($focus, equals: .done)
            // (R16) Escape ends Edit first - MacFrame.escape's panel, the panel's own key standing aside meanwhile
            .escapeCloses(editing && MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == .panel)
        }
        .background(DWPalette.panel)
        .dockHoldsEscape(editing)
    }

    /// (R16) The dock's Shuffle, Repeat and (Last.fm, A3) Autoplay, as `.btn.sm`s: each lit while on (`.btn.on`) and
    /// "selected" to VoiceOver - Shuffle dimmed during a library's shuffle, and while the queue has a station; Autoplay
    /// only while Last.fm is on, with its hint. One group for VoiceOver, as the chips were.
    private var macModes: some View {
        let mode = player.repeatMode
        return HStack(spacing: DockLook.headerGap) {
            Button(UpNextWords.shuffle, action: toggleShuffle)
                .buttonStyle(DWButtonStyle(kind: player.shuffle ? .on : .normal, size: .small))
                .disabled(player.paged != nil || player.stationHoldsShuffle)
                .accessibilityAddTraits(player.shuffle ? .isSelected : [])
                .accessibilityFocused($focus, equals: .shuffle)
            Button(repeatLabel(mode), action: cycleRepeat)
                .buttonStyle(DWButtonStyle(kind: mode != .off ? .on : .normal, size: .small))
                .accessibilityAddTraits(mode != .off ? .isSelected : [])
            if server.access.lastfm == .on {
                Button(LastfmWords.autoplay, action: toggleAutoplay)
                    .buttonStyle(DWButtonStyle(kind: player.autoplay ? .on : .normal, size: .small))
                    .accessibilityAddTraits(player.autoplay ? .isSelected : [])
                    .accessibilityHint(LastfmWords.autoplayHint)
                    .help(LastfmWords.autoplayHint)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UpNextWords.modesGroup)
    }

    /// (R3b) The phone's top's right (iQueue's): History - the songs before the one playing, scrolled to - and Clear,
    /// then Edit (Done while editing - focused after a change with nothing left to focus, as the old Done was; dimmed
    /// with nothing to edit). From xLarge text the two go into a ••• beside Edit (`folds`): `‹ Now Playing` (17), History,
    /// Clear and Edit (13.5, 11 either side, 8 apart) and the bar's margins take about 362 of a 375-point phone at Large
    /// (0.55 em a letter, taken wide), and would take about 395 at xLarge; folded, about 323 at xxxLarge, where the top
    /// stops growing (test_ios_nowplaying_pages_look.py works it out).
    @ViewBuilder
    private func phoneTop(_ view: UpNextView, editable: Bool, earlier: Bool, proxy: ScrollViewProxy) -> some View {
        let clearable = !view.added.isEmpty
        if !editing {
            if Self.folds(dynamicTypeSize) {
                Menu {
                    Button(UpNextWords.history) { toHistory(proxy) }
                        .disabled(!earlier)
                    Button(UpNextWords.clear, action: clear)
                        .disabled(!clearable)
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel(QueuePageWords.more)
                }
                .menuStyle(.button)
                .buttonStyle(DWButtonStyle(size: .small))
            } else {
                Button(UpNextWords.history) { toHistory(proxy) }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(!earlier)
                Button(UpNextWords.clear, action: clear)
                    .buttonStyle(DWButtonStyle(size: .small))
                    .disabled(!clearable)
            }
        }
        Button(editing ? UpNextWords.done : UpNextWords.edit) {
            if editing {
                editing = false
            } else {
                editing = true
                refocus(.done)
            }
        }
        .buttonStyle(DWButtonStyle(size: .small))
        .disabled(!editing && !editable)
        .accessibilityFocused($focus, equals: .done)
    }

    /// From xLarge text, History and Clear in a ••• (the arithmetic is phoneTop's).
    static func folds(_ size: DynamicTypeSize) -> Bool {
        size > .large
    }

    /// (R3b) History: the songs played before the one playing scrolled into view - the song playing's row at the
    /// view's foot, what was played before over it - as a swipe down to them would.
    private func toHistory(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo(Self.card, anchor: .bottom) }
    }

    /// (R3b) The phone's foot (iQueue's `.f`): Shuffle and Repeat, lit while on (VoiceOver's "selected"), and the time
    /// left at the right - capped at xxxLarge as a bar is; where the three don't fit on one line (the larger sizes, a
    /// long "over 1 hr 12 min left"), the time left goes on a line of its own under the two, never pushing them off.
    private func phoneFoot(_ view: UpNextView) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Self.footGap) {
                modeButtons
                Spacer(minLength: 0)
                QueueTimeLeftLine(view: view)
                    .fixedSize()
            }
            VStack(alignment: .leading, spacing: Self.footGap / 2) {
                HStack(spacing: Self.footGap) {
                    modeButtons
                }
                QueueTimeLeftLine(view: view)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Self.footGap)
        }
        .padding(.horizontal, Self.side)
        .lookHeight(Self.foot)
        .frame(maxWidth: .infinity)
        .background(DWPalette.panel)
        .overlay(alignment: .top) { DWRule(colour: DWPalette.line) }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// (R3b) The foot's Shuffle and Repeat: each lit while on, and "selected" to VoiceOver; Shuffle dimmed during a
    /// library's shuffle, as its chip was - and (Last.fm, A3) while the queue has a station, unless it is on (it can be
    /// turned off). Then Autoplay, while
    /// Last.fm is on: lit and "selected" while on, with its hint. The three fit a 375-point phone on one line at
    /// xxxLarge, where the foot stops growing (test_ios_lastfm_a3.py works it out); the time left goes under them.
    @ViewBuilder private var modeButtons: some View {
        let mode = player.repeatMode
        Button(action: toggleShuffle) {
            Text(UpNextWords.shuffle)
        }
        .buttonStyle(DWButtonStyle(kind: player.shuffle ? .on : .normal))
        .disabled(player.paged != nil || player.stationHoldsShuffle)
        .accessibilityAddTraits(player.shuffle ? .isSelected : [])
        .accessibilityFocused($focus, equals: .shuffle)
        Button(action: cycleRepeat) {
            Text(repeatLabel(mode))
        }
        .buttonStyle(DWButtonStyle(kind: mode != .off ? .on : .normal))
        .accessibilityAddTraits(mode != .off ? .isSelected : [])
        if server.access.lastfm == .on {
            Button(action: toggleAutoplay) {
                Text(LastfmWords.autoplay)
            }
            .buttonStyle(DWButtonStyle(kind: player.autoplay ? .on : .normal))
            .accessibilityAddTraits(player.autoplay ? .isSelected : [])
            .accessibilityHint(LastfmWords.autoplayHint)
        }
    }

    /// (R3b) The Mac's foot: the time left, in the dock's look - a row's height, under the line's edge, (R3b's review)
    /// at its left, as the status bar's words are.
    private func macFoot(_ view: UpNextView) -> some View {
        HStack(spacing: 0) {
            QueueTimeLeftLine(view: view)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Self.macSide)
        .lookHeight(DWLook.here.rowHeight)
        .background(DWPalette.panel)
        .overlay(alignment: .top) { DWRule(colour: DWPalette.line) }
    }

    /// The entry playing, by its key (a plain queue's, its place): what changes when the song playing does - a song's
    /// end, Next, Previous, a tap - and nothing else does.
    private var playingKey: Int? {
        let queue = player.queue
        guard queue.current != nil else { return nil }
        guard let marks = queue.upNext?.marks, marks.indices.contains(queue.index) else { return queue.index }
        return marks[queue.index].key
    }

    /// The bottom margin that lets the card reach the top: the screen's height less lower bounds of the card and the
    /// rows after it; none once they fill it.
    private func room(_ height: CGFloat, _ view: UpNextView) -> CGFloat {
        let after = view.added.count + (view.list?.rows.count ?? 0)
        return max(0, height - Self.cardAtLeast - Self.rowAtLeast * CGFloat(after))
    }

    /// The song playing's card to the top, History above it scrolled off - once the change has been drawn - and then
    /// VoiceOver's focus to `target`, if any (an Up Next row's tap: what plays next, now in view).
    private func toCard(_ proxy: ScrollViewProxy, then target: Focus? = nil) {
        Task { @MainActor in
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { proxy.scrollTo(Self.card, anchor: .top) }
            seen.placed = true
            if let target { focus = target }
        }
    }

    /// (app 0.8) A row above the song playing came into view: one of the list's first `HistoryAsking.near`, once the
    /// sheet has been placed (scrolled up to, then), asks for the next older page - while there is one, none is on its
    /// way, and the last older one didn't fail (Try again asks then; the newest page's failure never stops it).
    private func appeared(_ id: AnyHashable, at index: Int) {
        seen.ids.insert(id)
        guard seen.placed, index < HistoryAsking.near, history.mayAskOlder else { return }
        history.older()
    }

    /// (app 0.8) An older page landed: the next asked for at once when a row among the list's first
    /// `HistoryAsking.near` is still in view (HistoryAsking.asksAgain) - a page that added no row above them brings
    /// none into view to ask.
    private func askAgainNearTop() {
        guard seen.placed, !editing, player.upNext.playing != nil, history.mayAskOlder else { return }
        let order = PlayHistory.pastRows(history.plays, queue: player.queue).map { AnyHashable($0.key) }
            + player.upNext.history.map { AnyHashable($0.key) }
        if HistoryAsking.asksAgain(order, inView: seen.ids, more: history.more) { history.older() }
    }

    /// (app 0.8) Something above changed - a page of older songs landed, the newest page came, a failure said or let
    /// go - with the same song playing, in or out of Edit as before (those put the card back at the top themselves):
    /// the view held where it was, the topmost row in view put back at the top - unless nothing above it changed.
    /// Before the sheet is placed, nothing to hold.
    private func hold(_ old: Above, _ now: Above, _ view: UpNextView, _ proxy: ScrollViewProxy) {
        guard seen.placed, old.playing == now.playing, old.editing == now.editing else { return }
        let below: [AnyHashable] = view.history.map { AnyHashable($0.key) } + [AnyHashable(Self.card)]
            + view.added.map { AnyHashable($0.key) } + (view.list?.rows ?? []).map { AnyHashable($0.key) }
        let order = old.past.map { AnyHashable($0) } + below
        guard let anchor = order.first(where: { seen.ids.contains($0) }) else { return }
        if let key = anchor.base as? String, key != Self.card {
            guard let place = now.past.firstIndex(of: key) else { return }
            if place == old.past.firstIndex(of: key) && old.failed == now.failed { return }
        }
        Task { @MainActor in
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                if let key = anchor.base as? Int {
                    proxy.scrollTo(key, anchor: .top)
                } else if let key = anchor.base as? String {
                    proxy.scrollTo(key, anchor: .top)
                }
            }
        }
    }

    // MARK: the song playing, and Shuffle and Repeat

    /// (R16) The dock's song playing (Album.dc.html's `.row.on`): 44 tall on the selection's ground and edge at a box's
    /// corners, 8 in from the panel's sides - its cover (30), its title, "Artist · Album" under it, its mark and its
    /// length in Courier Prime at the right. One element and a heading, as the card was; marked, never dimmed.
    private func macPlaying(_ playing: QueueTrack) -> some View {
        let line = UpNextWords.songLine(artist: playing.artist, album: playing.album)
        return HStack(spacing: DockLook.rowSide) {
            CoverImage(id: playing.coverArt, size: DockLook.playingCover)
                .frame(width: DockLook.playingCover, height: DockLook.playingCover)
                .clipShape(DWCorners.chipShape)
            VStack(alignment: .leading, spacing: 1) {
                Text(playing.title)
                    .font(DockType.words.weight(.semibold))
                    .lineLimit(1)
                    .help(playing.title)
                if !line.isEmpty {
                    Text(line)
                        .font(DockType.small)
                        .lineLimit(1)
                        .help(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            UpNextSongMark(songID: playing.id)
            Text(AboutCard.trackTime(playing.duration))
                .font(DockType.smallReadout)
                .frame(width: DockLook.lengthWidth, alignment: .trailing)
        }
        .foregroundStyle(DWPalette.selt)
        .padding(.horizontal, DockLook.rowSide)
        .frame(height: DockLook.playingRow)
        .background(DWPalette.selbg, in: DWCorners.boxShape)
        .overlay(DWCorners.boxShape.strokeBorder(DWPalette.selbd, lineWidth: 1))
        .accessibilityElement(children: .combine)
        //? (2.1.3) the song playing's title a heading, as the web's: between History and what's to come
        .accessibilityAddTraits(.isHeader)
        .modifier(UpNextDownload(songID: playing.id, part: .card))
        .dockListRow(rule: false)
    }

    /// (R16) A `.navh` in the dock's list - Playing, Playing Next, "Next from …", Autoplay: 11.5 semibold in the label's
    /// colour, 13 above and 4 below, at the header's 12 from the panel's side; a heading for VoiceOver.
    private func macHeading(_ words: String) -> some View {
        Text(words)
            .font(DockType.heading)
            .foregroundStyle(DWPalette.label)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, DockLook.headerSide - DockLook.rowInset)
            .padding(.top, Self.navhAbove)
            .padding(.bottom, Self.navhBelow)
            .accessibilityAddTraits(.isHeader)
            .dockListRow(rule: false)
    }

    /// (R16) `.navh`'s room: 13 above its words, 4 below.
    private static let navhAbove: CGFloat = 13
    private static let navhBelow: CGFloat = 4

    /// (R3b) The phone's song playing (iQueue's `.row.tall.on`): the selected row - the selection's ground, edge and
    /// words - 60 tall at least, its cover 44, its title, "Artist · Album" under it and its length at the right, square.
    /// One element and a heading, as the card was; marked, never dimmed.
    private func playingRow(_ playing: QueueTrack) -> some View {
        let line = UpNextWords.songLine(artist: playing.artist, album: playing.album)
        return HStack(spacing: Self.footGap + 4) {
            CoverImage(id: playing.coverArt, size: Self.rowCover)
                .frame(width: Self.rowCover, height: Self.rowCover)
                .clipShape(Corners.artShape)
            VStack(alignment: .leading, spacing: 2) {
                Text(playing.title)
                    .font(Typeface.Phone.text(.row).weight(.semibold))
                    .lineLimit(1)
                if !line.isEmpty {
                    Text(line)
                        .font(Typeface.Phone.text(.small))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            UpNextSongMark(songID: playing.id)
            Text(AboutCard.trackTime(playing.duration))
                .font(Typeface.Phone.mono(.small))
        }
        .foregroundStyle(DWPalette.selt)
        .padding(.horizontal, Self.side)
        .lookHeight(DWLook.here.tallRowHeight)
        .background(DWPalette.selbg)
        .overlay(Rectangle().strokeBorder(DWPalette.selbd, lineWidth: 1))
        .accessibilityElement(children: .combine)
        //? (2.1.3) the song playing's title a heading, as the web's: between History and what's to come
        .accessibilityAddTraits(.isHeader)
        .modifier(UpNextDownload(songID: playing.id, part: .card))
        .modifier(QueuePhoneRow(phone: true, rule: false))
    }

    /// (R3b) A group's heading on the phone (iQueue's `.row.grp`): "Next from …", the list's title - 38 tall at least,
    /// its words at its foot in the heading's colour; a heading for VoiceOver.
    private func heading(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Phone.text(.row).weight(.semibold))
            .foregroundStyle(DWPalette.head)
            .frame(maxWidth: .infinity, minHeight: CGFloat(DWLook.here.groupRowHeight) - Self.headingFoot,
                   alignment: .bottomLeading)
            .padding(.leading, Self.side)
            .padding(.bottom, Self.headingFoot)
            .accessibilityAddTraits(.isHeader)
            .modifier(QueuePhoneRow(phone: true, rule: false))
    }

    /// A line under a group - "And 12 more songs.", Repeat one's, what comes after: the footnote's on the Mac; (R3b) on
    /// the phone the small words in the second colour, at the rows' side.
    @ViewBuilder
    private func note(_ words: String) -> some View {
        if phone {
            Text(words)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(QueuePhoneNote(phone: true, side: Self.side))
        } else {
            Text(words)
                .font(DockType.label)
                .foregroundStyle(DWPalette.t3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(QueuePhoneNote(phone: false, side: DockLook.rowSide))
        }
    }

    // MARK: a group's rows

    /// One group's rows - `next(index)` is the row a tap on the row at `index` moves focus to, what plays next (Playing
    /// Next's last: the list's first; a list row's: Playing Next's head, carried after it). In Edit the List's own drag
    /// handle moves them, a drag staying in its group, and each row's (-) takes it out. No onDelete, in Edit or out:
    /// out of it, it would be a swipe that loses a song; in it, the system's two-step (-). (Last.fm, A3) `part`: the rows
    /// of the group drawn here - the list's own, or Autoplay's under their heading - every index the group's, so a move
    /// or a removal is made in the whole group.
    private func rows(_ rows: [UpNextRow], lines: Bool, part: Range<Int>? = nil,
                      next: @escaping (Int) -> UpNextRow?) -> some View {
        let drawn = part.map { $0.clamped(to: rows.indices) } ?? rows.indices
        return ForEach(Array(Array(rows.enumerated())[drawn]), id: \.element.key) { index, row in
            Group {
                if editing {
                    editRow(row, index: index, rows: rows, lines: lines)
                } else {
                    playRow(row, next: next(index), lines: lines)
                }
            }
            .modifier(QueuePhoneRow(phone: phone))
            .accessibilityFocused($focus, equals: .row(row.key))
            .onAppear { seen.ids.insert(row.key) }
            .onDisappear { seen.ids.remove(row.key) }
        }
        .onMove(perform: mover(rows, from: drawn.lowerBound))
    }

    /// The List's drag in Edit, as a move to the row's new place (none out of Edit: no handles) - (A3) the drag's
    /// places counted from `offset`, where the part drawn begins in its group.
    private func mover(_ rows: [UpNextRow], from offset: Int = 0) -> ((IndexSet, Int) -> Void)? {
        guard editing else { return nil }
        return { source, destination in
            guard let first = source.first, rows.indices.contains(first + offset) else { return }
            let from = first + offset
            move(rows[from], in: rows, to: UpNextWords.movedTo(from: from, destination: destination + offset))
        }
    }

    private func playRow(_ row: UpNextRow, next: UpNextRow?, lines: Bool) -> some View {
        Button {
            //? it plays now, so it leaves the list: focus to what plays next - once the jump took, and only after the
            //? card is back at the top (the song playing's change scrolls there, onChange of playingKey), what plays
            //? next under it in view. A jump that took always changes the entry playing, so the change comes
            if player.jump(to: row.key) { focusAtCard = next.map { .row($0.key) } ?? .done }
        } label: {
            rowLabel(row.track, lines: lines)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UpNextWords.playNow(row.track.title))
        .modifier(UpNextDownload(songID: row.track.id, part: .row))
    }

    /// (2.1.3; the web's 2.1.18) A row of History's: ROLLED BACK to - the playing point moves up to it, nothing added or
    /// copied, and every row below it (the song that was playing among them) is to come, in the order drawn. Nothing
    /// above it changes, so the scroll is held and the card - the row, now playing - is where it was under the finger
    /// (rolledTo); then focus to what plays next and what started said - all only once the jump took (a key gone does
    /// nothing, and says nothing).
    private func historyRow(_ row: UpNextRow) -> some View {
        Button {
            guard player.jump(to: row.key) else { return }
            rolledTo(row.track)
        } label: {
            rowLabel(row.track, lines: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UpNextWords.playAgain(row.track.title))
        .modifier(UpNextDownload(songID: row.track.id, part: .row))
        .modifier(QueuePhoneRow(phone: phone))
    }

    /// (app 0.8; the web's 2.1.18) An older row - a song played before, above History: rolled back to, everywhere
    /// (PlayerModel.rollBack) - it and every older row below it come back into the queue ahead of History's songs, in
    /// the order drawn, and it plays: what PlayHistory.brought hands it (the web's replayPast, held to it by
    /// export-history.cjs's vectors) - the rows from the one tapped at the setting's level for a song, and the floor,
    /// the first entry Up Next draws for this queue now, which the rows were read against. The rows above it aren't rewritten,
    /// so the card is where the row was (the scroll held), then focus to what plays next and what started said - only
    /// once it took. A song not on this phone is dimmed and can't be tapped offline, as every row is.
    private func pastRow(_ row: PastRow) -> some View {
        Button {
            let handed = PlayHistory.brought(history.plays, queue: player.queue, key: row.key, setting: player.normalization)
            guard player.rollBack(handed.rows, floor: handed.floor) else { return }
            rolledTo(row.track)
        } label: {
            rowLabel(row.track, lines: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UpNextWords.playAgain(row.track.title))
        .modifier(UpNextDownload(songID: row.track.id, part: .row))
        .modifier(QueuePhoneRow(phone: phone))
    }

    /// (the web's 2.1.18 rolledTo) A tap above the card taken: the scroll held (the card where the row was), then - once
    /// the change has been drawn, as the web says them from the draw that shows the tap taken (said during the redraw,
    /// VoiceOver can cut them off) - focus to what plays next in the queue now (Playing Next's head, else the list's
    /// first; Done with none) and what started said.
    private func rolledTo(_ track: QueueTrack) {
        holdAt = playingKey
        let now = player.upNext
        let next: Focus = (now.added.first ?? now.list?.rows.first).map { .row($0.key) } ?? .done
        let words = UpNextWords.playing(track.title)
        Task { @MainActor in
            focus = next
            Notice.announce(words)
        }
    }

    /// A row's look: on the Mac its cover and its words; (R3b) on the phone iQueue's - its words, its length at the
    /// right in mono, 48 tall at least, no cover.
    @ViewBuilder
    private func rowLabel(_ track: QueueTrack, lines: Bool) -> some View {
        if phone {
            // (25 Nov) beside one line, the length sits on the title's baseline: Courier Prime's line is shorter than
            // Libre Franklin's, so centred it would sit higher. Beside two it is centred on them, as iQueue draws it.
            let oneLine = !lines || UpNextWords.songLine(artist: track.artist, album: track.album).isEmpty
            HStack(alignment: oneLine ? .firstTextBaseline : .center, spacing: Self.footGap) {
                text(track, lines: lines)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(AboutCard.trackTime(track.duration))
                    .font(Typeface.Phone.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            }
            .padding(.horizontal, Self.side)
            .lookHeight(DWLook.here.rowHeight)
            .contentShape(Rectangle())
        } else {
            macWords(track, lines: lines)
        }
    }

    /// (R16) A row's words in the dock (DockQueueRow): its title, its line where `lines` says so, its mark and its
    /// length - at View ▸ Row Size's height.
    private func macWords(_ track: QueueTrack, lines: Bool) -> some View {
        DockQueueRow(title: track.title, line: lines ? UpNextWords.songLine(artist: track.artist, album: track.album) : "",
                     length: AboutCard.trackTime(track.duration)) {
            UpNextSongMark(songID: track.id)
        }
    }

    /// A row in Edit: its red (-), which takes it out at once, and its words; the List draws the drag handle. One
    /// VoiceOver element, its words read as they were and its (-) left out of it - Remove is among its actions, and
    /// a double tap on the row does nothing, so VoiceOver can't take a song out by landing on it.
    private func editRow(_ row: UpNextRow, index: Int, rows: [UpNextRow], lines: Bool) -> some View {
        let title = row.track.title
        let line = UpNextWords.songLine(artist: row.track.artist, album: row.track.album)
        return HStack(spacing: 8) {
            if phone {
                Button {
                    remove(row, at: index, in: rows)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .font(Typeface.symbol(.title3))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityHidden(true)
                //? offline, only the words and the mark dim: the minus and the handle stay whole, and work
                text(row.track, lines: lines)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(UpNextDownload(songID: row.track.id, part: .look))
            } else {
                //? (R16) the dock's: the red (-) in the look's red, at the row's height, then the row's words
                Button {
                    remove(row, at: index, in: rows)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DWPalette.text, DWPalette.redChipText)
                        .font(DockType.words)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, DockLook.rowSide)
                .accessibilityHidden(true)
                macWords(row.track, lines: lines)
                    .modifier(UpNextDownload(songID: row.track.id, part: .look))
            }
        }
        //? (R3b) the phone's row: 48 tall at least, as out of Edit
        .modifier(QueueRowHeight(phone: phone))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, line].filter { !$0.isEmpty }.joined(separator: ", "))
        .modifier(UpNextDownload(songID: row.track.id, part: .words))
        .accessibilityActions {
            //? disabled at the group's ends, as the web's are: an end has only the other way
            if index > 0 {
                Button(UpNextWords.moveUp(title)) { move(row, in: rows, to: index - 1) }
            }
            if index < rows.count - 1 {
                Button(UpNextWords.moveDown(title)) { move(row, in: rows, to: index + 1) }
            }
            Button(UpNextWords.remove(title)) { remove(row, at: index, in: rows) }
        }
    }

    /// The row's title and line, the song's download mark at the line's end - outside its words, so a long line wraps
    /// before it - or, with no line, after the title (4.3.1). (R3b) On the phone iQueue's: the title at the row's 16,
    /// the line small in the second colour, each on one line; and no line where `lines` is false (an album's rows under
    /// its heading).
    private func text(_ track: QueueTrack, lines: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            let line = lines ? UpNextWords.songLine(artist: track.artist, album: track.album) : ""
            if line.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    title(track.title)
                    UpNextSongMark(songID: track.id)
                }
            } else {
                title(track.title)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(line)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                    UpNextSongMark(songID: track.id)
                }
            }
        }
    }

    /// A row's title: (R3b) the phone's at the row's 16 in white, on one line - (R16) the Mac's words are DockQueueRow's.
    private func title(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Phone.text(.row))
            .foregroundStyle(DWPalette.text)
            .lineLimit(1)
    }

    // MARK: what each change does

    private func toggleShuffle() {
        guard player.paged == nil, !player.stationHoldsShuffle else { return }
        let on = !player.shuffle
        player.toggleShuffle()
        Notice.announce(UpNextWords.shuffleSaid(on))
    }

    private func cycleRepeat() {
        let mode = nextRepeat(player.repeatMode)
        player.setRepeat(mode)
        Notice.announce(UpNextWords.repeatSaid(mode))
    }

    /// (Last.fm, A3) Autoplay on or off - off takes its rows still to come out (PlayerModel.setAutoplay).
    private func toggleAutoplay() {
        let on = !player.autoplay
        player.setAutoplay(on)
        Notice.announce(LastfmWords.autoplaySaid(on))
    }

    private func clear() {
        player.clearPlayingNext()
        Notice.announce(UpNextWords.clearedSaid)
        refocus(.shuffle)
    }

    private func move(_ row: UpNextRow, in rows: [UpNextRow], to: Int) {
        guard let from = rows.firstIndex(of: row), to != from, rows.indices.contains(to) else { return }
        player.move(key: row.key, to: to)
        Notice.announce(UpNextWords.movedSaid(row.track.title, to: to, of: rows.count))
        refocus(.row(row.key))
    }

    private func remove(_ row: UpNextRow, at index: Int, in rows: [UpNextRow]) {
        let next = rows.indices.contains(index + 1) ? rows[index + 1] : (index > 0 ? rows[index - 1] : nil)
        player.remove(key: row.key)
        Notice.announce(UpNextWords.removedSaid(row.track.title))
        refocus(next.map { .row($0.key) } ?? .done)
    }

    /// VoiceOver's focus to `target` once the change has been drawn.
    private func refocus(_ target: Focus) {
        Task { @MainActor in focus = target }
    }
}

/// A song's download mark in Up Next (phase2-downloads.md 4.3.1): 3.3's song mark - the album row's DownloadMark, at
/// caption size, the ring alone while downloading - or nothing for a song not asked for. A view of its own, reading
/// the download model for its one song, so a download's change or progress redraws only it, never Up Next's list.
private struct UpNextSongMark: View {
    let songID: String

    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        let state = downloads.state(songID)
        if let mark = DownloadWords.mark(state) {
            DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(state), font: Typeface.symbol(.caption))
                .fixedSize()
        }
    }
}

/// A song's dim and VoiceOver value in Up Next (4.3.1): while deadwax can't be reached, a song not on this phone - by
/// downloads alone, as the album page's rows - drawn at Palette.off, and a row whose tap plays it not a button; its
/// state ("Downloaded", "Downloading, 40 percent", "Not on this phone") the value VoiceOver reads after the row's name.
/// A modifier of its own, reading the models for its one song, so their changes redraw only it.
private struct UpNextDownload: ViewModifier {
    enum Part {
        /// A row whose tap plays (the list's, Playing Next's, History's): dimmed, disabled, said.
        case row
        /// An Edit row's words and mark: dimmed only - its minus and the List's handle stay whole.
        case look
        /// An Edit row's one element: said only.
        case words
        /// The song playing's card: its state said, never dimmed (the player speaks for the song playing).
        case card
    }

    let songID: String
    let part: Part

    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability

    @ViewBuilder func body(content: Content) -> some View {
        let state = downloads.state(songID)
        let notHere = !reachability.online && !state.isHere
        switch part {
        case .row:
            content
                .opacity(notHere ? Palette.off : 1)
                .disabled(notHere)
                .accessibilityValue(words(state, notHere: notHere))
        case .look:
            content
                .opacity(notHere ? Palette.off : 1)
        case .words:
            content
                .accessibilityValue(words(state, notHere: notHere))
        case .card:
            content
                .accessibilityValue(DownloadWords.songLine(state, device: Platform.device) ?? "")
        }
    }

    private func words(_ state: SongDownload, notHere: Bool) -> String {
        (notHere ? DownloadWords.notOnDevice(Platform.device) : DownloadWords.songLine(state, device: Platform.device)) ?? ""
    }
}

/// (R16) The history's Try again: the phone's words in the accent (R3b's, as it was), the Mac's a `.btn.sm`.
private struct QueueTryAgain: ViewModifier {
    let phone: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if phone {
            content
                .buttonStyle(.borderless)
        } else {
            content
                .buttonStyle(DWButtonStyle(size: .small))
        }
    }
}

/// (R3b) The Queue's list: on the phone iQueue's plain list on the sheet's ground - its own rows, hairlines and
/// headings, none of the system's - and (R16) on the Mac the same, on the panel's ground: the dock's rows and `.navh`s.
private struct QueueListLook: ViewModifier {
    let phone: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if phone {
            content
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listSectionSpacing(0)
                .environment(\.defaultMinListRowHeight, 0)
        } else {
            content
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listSectionSpacing(0)
                .environment(\.defaultMinListRowHeight, 0)
                .background(DWPalette.panel)
        }
    }
}

/// (R3b) One of the phone's rows in the Queue's list (iQueue's `.row`): edge to edge on the sheet's ground, its own
/// hairline under it (`.dw.ph .row`'s #1c1b22) - none under a heading or the selected row - and no system separator.
private struct QueuePhoneRow: ViewModifier {
    let phone: Bool
    var rule = true

    @ViewBuilder func body(content: Content) -> some View {
        if phone {
            content
                .overlay(alignment: .bottom) {
                    if rule { DWRule(colour: DWPalette.rowRule) }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(DWPalette.panel)
        } else {
            //? (R16) the dock's row: 8 in from the panel's sides, its rowline under it
            content
                .dockListRow(rule: rule)
        }
    }
}

/// (R3b) A row's height in Edit on the phone: 48 at least, as out of Edit (DWLook's rowHeight); (R16) the Mac's its
/// words' own (DockQueueRow's, at View ▸ Row Size's height).
private struct QueueRowHeight: ViewModifier {
    let phone: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if phone {
            content.lookHeight(DWLook.here.rowHeight)
        } else {
            content
        }
    }
}

/// (R3b) A note in the phone's list - a line under a group, History's failure - at the rows' side, with room above and
/// below; (R16) on the Mac the same, at the dock's rows' side.
private struct QueuePhoneNote: ViewModifier {
    let phone: Bool
    let side: CGFloat

    @ViewBuilder func body(content: Content) -> some View {
        if phone {
            content
                .padding(.horizontal, side)
                .padding(.vertical, side / 2)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(DWPalette.panel)
        } else {
            content
                .padding(.horizontal, side)
                .padding(.vertical, side / 2)
                .dockListRow(rule: false)
        }
    }
}

/// (R3b) The time left (QueueTimeLeft: "8 songs · 33 min left"), in the third colour - the phone's extra-small in mono,
/// at the page's right; (R3b's review) on the Mac the status bar's 11.5 in its own type, not mono, at the dock's left
/// (the look's chip role: Typeface.Mac is named only from the Mac's frame). A view of its own, reading the player's
/// position (twice a second) and speed, so their changes redraw only it, never the list.
private struct QueueTimeLeftLine: View {
    let view: UpNextView

    @Environment(PlayerModel.self) private var player

    var body: some View {
        if let words = QueueTimeLeft.words(view, position: player.shownPosition, speed: player.speed) {
            Text(words)
                .font(Platform.mac ? Typeface.Look.text(.chip) : Typeface.Phone.mono(.extraSmall))
                .foregroundStyle(DWPalette.t3)
                .multilineTextAlignment(Platform.mac ? .leading : .trailing)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension View {
    /// (R3b) The Queue's top: in the sheet over Now Playing the sheet's (`‹ Now Playing`, the strip, and the page's own
    /// at its right); (R16) in the Mac's side panel no bar - the dock's header (DockHeader) at the top of the page.
    @ViewBuilder
    fileprivate func queueTop<Phone: View, Mac: View>(_ sheet: SheetTop?, @ViewBuilder phone: () -> Phone,
                                                      @ViewBuilder mac: () -> Mac) -> some View {
        if let sheet {
            sheetTop(sheet, trailing: phone)
        } else {
            let top = mac()
            self.toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) { top }
        }
    }
}
