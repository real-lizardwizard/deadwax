import DeadwaxCore
import SwiftUI

/// Up Next (ui/src/app/UpNext.tsx), a sheet over Now Playing: what Core's `upNextView` says is to be drawn, and
/// nothing else - the song playing (and, with Repeat One, that it repeats); Shuffle and Repeat; Playing Next, with
/// Clear, when songs have been added; the rest of the album or list this time round, then "And N more songs."; and
/// what comes after. Neither Repeat One's copies nor the later times round are drawn.
///
/// A row's tap plays it now (PlayerModel.jump, by the row's key: a song in twice is two rows, and a key gone does
/// nothing). Edit gives each row Move up, Move down and Remove - as VoiceOver actions, and as the List's own drag
/// handle and delete - each change made as it is made, a move staying in its group. What changed is read out, and
/// VoiceOver's focus goes where the web's goes (Pinned's rule): a moved row where it went; after a removal the next
/// row, the one before at the end, Done with none; Clear to the Shuffle chip; Edit to Done; a row's tap to the row
/// after it (Playing Next's last to the list's first), or Done. Each opening starts at the top, out of Edit; Done
/// ends Edit, else closes; the sheet closes by itself once nothing is queued.
struct UpNextScreen: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
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

    init() {}

    var body: some View {
        let view = player.upNext
        let listRows = view.list?.rows ?? []
        let editable = !view.added.isEmpty || !listRows.isEmpty
        NavigationStack {
            List {
                if let playing = view.playing {
                    Section {
                        playingCard(playing)
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
                            rows(view.added, after: listRows.first)
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
                            rows(list.rows, after: nil)
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
            .environment(\.editMode, .constant(editing ? .active : .inactive))
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

    /// One group's rows - `after` is the row a tap on its last moves focus to (Playing Next's: the list's first). In
    /// Edit the List's own drag handle and delete work on them, a drag staying in its group.
    private func rows(_ rows: [UpNextRow], after: UpNextRow?) -> some View {
        ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
            Group {
                if editing {
                    editRow(row, index: index, rows: rows)
                } else {
                    playRow(row, index: index, rows: rows, after: after)
                }
            }
            .accessibilityFocused($focus, equals: .row(row.key))
        }
        .onMove(perform: mover(rows))
        .onDelete(perform: remover(rows))
    }

    /// The List's drag in Edit, as a move to the row's new place (none out of Edit: no handles).
    private func mover(_ rows: [UpNextRow]) -> ((IndexSet, Int) -> Void)? {
        guard editing else { return nil }
        return { source, destination in
            guard let from = source.first, rows.indices.contains(from) else { return }
            move(rows[from], in: rows, to: UpNextWords.movedTo(from: from, destination: destination))
        }
    }

    /// The List's delete in Edit (none out of Edit: a row's swipe is no way to lose a song by accident).
    private func remover(_ rows: [UpNextRow]) -> ((IndexSet) -> Void)? {
        guard editing else { return nil }
        return { offsets in
            guard let index = offsets.first, rows.indices.contains(index) else { return }
            remove(rows[index], at: index, in: rows)
        }
    }

    private func playRow(_ row: UpNextRow, index: Int, rows: [UpNextRow], after: UpNextRow?) -> some View {
        Button {
            //? it plays now, so it leaves the list: focus to the row after it (Playing Next's last: the list's first)
            let next = rows.indices.contains(index + 1) ? rows[index + 1] : after
            player.jump(to: row.key)
            refocus(next.map { .row($0.key) } ?? .done)
        } label: {
            HStack(spacing: 12) {
                CoverImage(id: row.track.coverArt, size: Self.rowCover)
                    .frame(width: Self.rowCover, height: Self.rowCover)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                text(row)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(UpNextWords.playNow(row.track.title))
    }

    private func editRow(_ row: UpNextRow, index: Int, rows: [UpNextRow]) -> some View {
        let title = row.track.title
        return text(row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
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
