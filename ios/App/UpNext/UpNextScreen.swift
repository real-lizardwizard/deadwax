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
/// History's - "{title}, play again" - plays that song again, a new entry after the song playing; History isn't
/// rewritten, so the row stays under the finger, VoiceOver's focus stays on it and "Playing {title}" is said - only
/// once the jump took. History is hidden in Edit, and has no moves or removals. Edit gives each row Move up, Move down and Remove - as VoiceOver actions, and as the List's own drag
/// handle and the row's own red (-), which takes the song out at once - each change made as it is made, a move
/// staying in its group. Out of Edit a row can't be swiped away, so a song isn't lost by a stray swipe; in Edit iOS
/// offers no swipe (a List in Edit takes none - notes/ios.md, "Up Next: one tap to take a song out"), so the (-)
/// is the one action, in place of the system's two (its (-), then Delete). What changed is read out, and
/// VoiceOver's focus goes where the web's goes (Pinned's rule): a moved row where it went; after a removal the next
/// row, the one before at the end, Done with none; Clear to the Shuffle chip; Edit to Done; a row's tap to the row
/// after it - after a list row's, Playing Next's head, carried after it - (Playing Next's last to the list's first), or
/// Done, once the card is back at the top so it lands in view. Each opening starts at the song playing, History above it scrolled up to, out of Edit; the song playing put
/// back at the top whenever it changes (a song's end, Next, Previous, an Up Next row's tap) or Edit goes on or off -
/// never for Shuffle, Repeat, Clear or Edit's moves, and not after a History tap. A bottom margin lets the card reach
/// the top near an album's end, where scrollTo would stop short. Done ends Edit, else closes; the sheet closes by
/// itself once nothing is queued.
struct UpNextScreen: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    /// The entry a History tap moved to: its change of song keeps the scroll where it is (the row under the finger).
    @State private var holdAt: Int?
    /// Where an Up Next row's tap sends VoiceOver's focus - what plays next - set once the card is back at the top, so
    /// it lands on a row in view (the web's "so focus lands in view"): History grew above the card, which pushed the
    /// row down, maybe out of the List's drawn cells, until the scroll.
    @State private var focusAtCard: Focus?
    @AccessibilityFocusState private var focus: Focus?

    /// Where VoiceOver's focus goes after a change.
    enum Focus: Hashable {
        case row(Int)
        case done
        case shuffle
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
        NavigationStack {
            GeometryReader { space in
                ScrollViewReader { proxy in
                    List {
                        if let playing = view.playing {
                            if !editing && !view.history.isEmpty {
                                Section {
                                    ForEach(view.history, id: \.key) { row in
                                        historyRow(row)
                                            .accessibilityFocused($focus, equals: .row(row.key))
                                    }
                                } header: {
                                    Text(UpNextWords.history)
                                        .textCase(nil)
                                        .accessibilityAddTraits(.isHeader)
                                }
                            }

                            Section {
                                playingCard(playing)
                                    .id(Self.card)
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
                    .onAppear { toCard(proxy) }
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
            if let target { focus = target }
        }
    }

    // MARK: the song playing, and Shuffle and Repeat

    private func playingCard(_ playing: QueueTrack) -> some View {
        HStack(spacing: 12) {
            CoverImage(id: playing.coverArt, size: Self.playingCover)
                .frame(width: Self.playingCover, height: Self.playingCover)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(playing.title)
                    .font(.headline)
                let line = UpNextWords.songLine(artist: playing.artist, album: playing.album)
                if !line.isEmpty {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
            }
        }
        .accessibilityElement(children: .combine)
        //? (2.1.3) the song playing's title a heading, as the web's: between History and what's to come
        .accessibilityAddTraits(.isHeader)
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
            rowLabel(row)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UpNextWords.playNow(row.track.title))
    }

    /// (2.1.3) A row of History's: the song again, now - a new entry after the song playing. History isn't rewritten,
    /// so the row stays where it is under the finger (the scroll held) and VoiceOver's focus on it, and since nothing
    /// in view moves, what started is said - all only once the jump took (a key gone does nothing, and says nothing).
    private func historyRow(_ row: UpNextRow) -> some View {
        Button {
            guard player.jump(to: row.key) else { return }
            holdAt = playingKey
            //? focus kept on the row, then the words - both once the change has been drawn, as the web says them from
            //? the draw that shows the tap taken: said during the redraw, VoiceOver can cut them off
            let words = UpNextWords.playing(row.track.title)
            Task { @MainActor in
                focus = .row(row.key)
                Notice.announce(words)
            }
        } label: {
            rowLabel(row)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UpNextWords.playAgain(row.track.title))
    }

    private func rowLabel(_ row: UpNextRow) -> some View {
        HStack(spacing: 12) {
            CoverImage(id: row.track.coverArt, size: Self.rowCover)
                .frame(width: Self.rowCover, height: Self.rowCover)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            text(row)
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
            text(row)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, line].filter { !$0.isEmpty }.joined(separator: ", "))
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

    private func text(_ row: UpNextRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.track.title)
                .foregroundStyle(.primary)
            let line = UpNextWords.songLine(artist: row.track.artist, album: row.track.album)
            if !line.isEmpty {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
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
