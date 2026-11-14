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
struct UpNextScreen: View {
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(HistoryModel.self) private var history
    @Environment(Reachability.self) private var reachability
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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

    /// The covers' sizes: the song playing's, and a row's.
    private static let playingCover: CGFloat = 64
    private static let rowCover: CGFloat = 44
    /// The song playing's card, scrolled to the top.
    private static let card = "playing"
    /// Lower bounds of the card with the chips under it, and of a row - so the bottom margin made from them is never
    /// too little for the card to reach the top (at most a little more than needed).
    private static let cardAtLeast: CGFloat = 120
    private static let rowAtLeast: CGFloat = 56

    init() {}

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
                                                .buttonStyle(.borderless)
                                        }
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
                                playingCard(playing)
                                    .id(Self.card)
                                    .onAppear { seen.ids.insert(Self.card) }
                                    .onDisappear { seen.ids.remove(Self.card) }
                                if view.repeatOne {
                                    Text(UpNextWords.repeatingOne)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.quiet)
                                }
                                modes
                                if player.paged != nil {
                                    Text(UpNextWords.shufflingLibrary)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.quiet)
                                }
                            }

                            if !view.added.isEmpty {
                                Section {
                                    rows(view.added) { index in
                                        view.added.indices.contains(index + 1) ? view.added[index + 1] : listRows.first
                                    }
                                } header: {
                                    HStack {
                                        Text(UpNextWords.playingNext)
                                            .accessibilityAddTraits(.isHeader)
                                        Spacer()
                                        Button(UpNextWords.clear, action: clear)
                                            .buttonStyle(.borderless)
                                            .font(.subheadline)
                                    }
                                    .textCase(nil)
                                }
                            }

                            if let list = view.list {
                                Section {
                                    //? (2.1.3) Playing Next is carried after a list row tapped: what plays next is its head
                                    rows(list.rows) { index in
                                        view.added.first ?? (list.rows.indices.contains(index + 1) ? list.rows[index + 1] : nil)
                                    }
                                    if list.more > 0 {
                                        Text(UpNextWords.more(list.more))
                                            .font(.footnote)
                                            .foregroundStyle(Palette.quiet)
                                    }
                                } header: {
                                    Text(list.title)
                                        .textCase(nil)
                                        .accessibilityAddTraits(.isHeader)
                                }
                            }

                            if let then = view.then {
                                Section {
                                    Text(then)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.quiet)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    //? near an album's end the card can't reach the top - scrollTo stops where the content ends - so room
                    //? below it, from lower bounds of what follows the card: never too little, at most a little more
                    .contentMargins(.bottom, room(space.size.height, view), for: .scrollContent)
                    .environment(\.editMode, .constant(editing ? .active : .inactive))
                    //? (app 0.8) an older page on its way: over the list's top, so nothing in it moves
                    .overlay(alignment: .top) {
                        if history.loading && !editing {
                            ProgressView()
                                .padding(10)
                                .background(.regularMaterial, in: Capsule())
                                .padding(.top, 8)
                                .accessibilityLabel(UpNextWords.loadingEarlier)
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
                }
            }
            .navigationTitle(UpNextWords.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !editing && editable {
                        Button(UpNextWords.edit) {
                            editing = true
                            refocus(.done)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(UpNextWords.done) {
                        if editing { editing = false } else { dismiss() }
                    }
                    .accessibilityFocused($focus, equals: .done)
                }
            }
        }
        // the marks' progress, once for the sheet (it asks the session only while something is fetching)
        .task { await downloads.followProgress() }
        .onChange(of: player.hasQueue) { _, queued in
            if !queued { dismiss() }
        }
        .onChange(of: editable) { _, can in
            if !can { editing = false }
        }
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

    private func playingCard(_ playing: QueueTrack) -> some View {
        HStack(spacing: 12) {
            CoverImage(id: playing.coverArt, size: Self.playingCover)
                .frame(width: Self.playingCover, height: Self.playingCover)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                let line = UpNextWords.songLine(artist: playing.artist, album: playing.album)
                if line.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(playing.title)
                            .font(.headline)
                        UpNextSongMark(songID: playing.id)
                    }
                } else {
                    Text(playing.title)
                        .font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(Palette.quiet)
                        UpNextSongMark(songID: playing.id)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        //? (2.1.3) the song playing's title a heading, as the web's: between History and what's to come
        .accessibilityAddTraits(.isHeader)
        //? marked, never dimmed: the song playing is the player's to speak for (7.3's stopped line)
        .modifier(UpNextDownload(songID: playing.id, part: .card))
    }

    private var modes: some View {
        let mode = player.repeatMode
        let paged = player.paged != nil
        return HStack(spacing: 8) {
            Chip(glyph: "shuffle", label: UpNextWords.shuffle, on: player.shuffle, enabled: !paged, action: toggleShuffle)
                .accessibilityFocused($focus, equals: .shuffle)
            Chip(glyph: mode == .one ? "repeat.1" : "repeat", label: repeatLabel(mode), on: mode != .off, enabled: true, action: cycleRepeat)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UpNextWords.modesGroup)
    }

    // MARK: a group's rows

    /// One group's rows - `next(index)` is the row a tap on the row at `index` moves focus to, what plays next (Playing
    /// Next's last: the list's first; a list row's: Playing Next's head, carried after it). In Edit the List's own drag
    /// handle moves them, a drag staying in its group, and each row's (-) takes it out. No onDelete, in Edit or out:
    /// out of it, it would be a swipe that loses a song; in it, the system's two-step (-).
    private func rows(_ rows: [UpNextRow], next: @escaping (Int) -> UpNextRow?) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
            Group {
                if editing {
                    editRow(row, index: index, rows: rows)
                } else {
                    playRow(row, next: next(index))
                }
            }
            .accessibilityFocused($focus, equals: .row(row.key))
            .onAppear { seen.ids.insert(row.key) }
            .onDisappear { seen.ids.remove(row.key) }
        }
        .onMove(perform: mover(rows))
    }

    /// The List's drag in Edit, as a move to the row's new place (none out of Edit: no handles).
    private func mover(_ rows: [UpNextRow]) -> ((IndexSet, Int) -> Void)? {
        guard editing else { return nil }
        return { source, destination in
            guard let from = source.first, rows.indices.contains(from) else { return }
            move(rows[from], in: rows, to: UpNextWords.movedTo(from: from, destination: destination))
        }
    }

    private func playRow(_ row: UpNextRow, next: UpNextRow?) -> some View {
        Button {
            //? it plays now, so it leaves the list: focus to what plays next - once the jump took, and only after the
            //? card is back at the top (the song playing's change scrolls there, onChange of playingKey), what plays
            //? next under it in view. A jump that took always changes the entry playing, so the change comes
            if player.jump(to: row.key) { focusAtCard = next.map { .row($0.key) } ?? .done }
        } label: {
            rowLabel(row.track)
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
            rowLabel(row.track)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UpNextWords.playAgain(row.track.title))
        .modifier(UpNextDownload(songID: row.track.id, part: .row))
    }

    /// (app 0.8; the web's 2.1.18) An older row - a song played before, above History: rolled back to, everywhere
    /// (PlayerModel.rollBack) - it and every older row below it (PlayHistory.rowsFrom) come back into the queue ahead of
    /// History's songs, in the order drawn, and it plays. `floor` the first entry Up Next draws for this queue now -
    /// History's first row, else the song playing's: the rows were read against it. The rows above it aren't rewritten,
    /// so the card is where the row was (the scroll held), then focus to what plays next and what started said - only
    /// once it took. A song not on this phone is dimmed and can't be tapped offline, as every row is.
    private func pastRow(_ row: PastRow) -> some View {
        Button {
            let past = PlayHistory.pastRows(history.plays, queue: player.queue)
            guard player.rollBack(PlayHistory.rowsFrom(past, row.key), floor: player.upNext.history.first?.key ?? playingKey)
            else { return }
            rolledTo(row.track)
        } label: {
            rowLabel(row.track)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UpNextWords.playAgain(row.track.title))
        .modifier(UpNextDownload(songID: row.track.id, part: .row))
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

    private func rowLabel(_ track: QueueTrack) -> some View {
        HStack(spacing: 12) {
            CoverImage(id: track.coverArt, size: Self.rowCover)
                .frame(width: Self.rowCover, height: Self.rowCover)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            text(track)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// A row in Edit: its red (-), which takes it out at once, and its words; the List draws the drag handle. One
    /// VoiceOver element, its words read as they were and its (-) left out of it - Remove is among its actions, and
    /// a double tap on the row does nothing, so VoiceOver can't take a song out by landing on it.
    private func editRow(_ row: UpNextRow, index: Int, rows: [UpNextRow]) -> some View {
        let title = row.track.title
        let line = UpNextWords.songLine(artist: row.track.artist, album: row.track.album)
        return HStack(spacing: 8) {
            Button {
                remove(row, at: index, in: rows)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityHidden(true)
            //? offline, only the words and the mark dim: the minus and the handle stay whole, and work
            text(row.track)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(UpNextDownload(songID: row.track.id, part: .look))
        }
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
    /// before it - or, with no line, after the title (4.3.1).
    private func text(_ track: QueueTrack) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            let line = UpNextWords.songLine(artist: track.artist, album: track.album)
            if line.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(track.title)
                        .foregroundStyle(.primary)
                    UpNextSongMark(songID: track.id)
                }
            } else {
                Text(track.title)
                    .foregroundStyle(.primary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                    UpNextSongMark(songID: track.id)
                }
            }
        }
    }

    // MARK: what each change does

    private func toggleShuffle() {
        guard player.paged == nil else { return }
        let on = !player.shuffle
        player.toggleShuffle()
        Notice.announce(UpNextWords.shuffleSaid(on))
    }

    private func cycleRepeat() {
        let mode = nextRepeat(player.repeatMode)
        player.setRepeat(mode)
        Notice.announce(UpNextWords.repeatSaid(mode))
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
            DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(state), font: .caption)
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
                .accessibilityValue(DownloadWords.songLine(state) ?? "")
        }
    }

    private func words(_ state: SongDownload, notHere: Bool) -> String {
        (notHere ? DownloadWords.notOnPhone : DownloadWords.songLine(state)) ?? ""
    }
}

/// Shuffle or Repeat as Up Next's chip: its glyph and its words, pressed (VoiceOver's "selected") and tinted while on.
private struct Chip: View {
    let glyph: String
    let label: String
    let on: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: glyph)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(on ? Color.black : Color.primary)
                .background(on ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.primary.opacity(0.12)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
