import DeadwaxCore
import SwiftUI

/// What opens the picker: the songs in hand, a new id each time it opens, so it starts afresh.
struct PlaylistPickRequest: Identifiable {
    let id = UUID()
    let pick: PlaylistPick

    /// nil for no songs (the web's openPicker opens nothing for none).
    init?(_ pick: PlaylistPick) {
        guard !pick.songs.isEmpty else { return nil }
        self.pick = pick
    }
}

/// Add to a playlist (Phase 4, slice 2, phase4-library.md 2.4; the web's app/PlaylistPicker.tsx): a sheet, from a song's
/// or an album's ••• (QueueMenu - the album page's bar and rows, a playlist's bar and rows) and from Now Playing's •••,
/// with the songs in hand. Its head says what it adds (`pickLine`); then New playlist… and the playlists you can add to
/// (PlaylistRules.picker: yours and editable, the one changed last on top). The list is asked afresh as it opens, what is
/// held drawing meanwhile.
///
/// A playlist's tap adds (`.ask` first): one write at a time, across every opening of the picker and both its openers
/// (PlaylistsModel.writes) - the row says "Adding…" and every row and New playlist… wait until the answer, in this
/// sheet and in one opened again meanwhile, so neither a double tap nor a second opening ever adds twice. Written: the sheet closes and the app's notice says what happened
/// (`addedWords`). Some there already and nothing written: the list gives way to the question - add them again, skip
/// those, or Cancel back to the list. Refused: why, in a listener's words, under the head, the sheet open; a playlist
/// gone asks the list again. Closing the sheet while an add is out never calls it off (a write) - the notice still
/// says how it went. New playlist… opens the name in place of its row and makes the playlist WITH the songs ("Made
/// Late night with Roads"). It plays nothing.
struct PlaylistPicker: View {
    let request: PlaylistPickRequest

    @Environment(PlaylistsModel.self) private var playlists
    @Environment(PlayerModel.self) private var player
    @Environment(ServerModel.self) private var server
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlaylistPickerModel
    @AccessibilityFocusState private var focus: PickerFocus?

    init(request: PlaylistPickRequest) {
        self.request = request
        _model = State(initialValue: PlaylistPickerModel(pick: request.pick))
    }

    private enum PickerFocus: Hashable {
        case first, question
    }

    var body: some View {
        let rows = playlists.list.map(PlaylistRules.picker) ?? []
        NavigationStack {
            List {
                Section {
                    Text(PlaylistRules.pickLine(model.pick))
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                        .lineLimit(3)
                    if let failure = model.failure {
                        ErrorNote(failure)
                    }
                }

                if let question = model.question {
                    questionSection(question)
                } else {
                    listSection(rows)
                }
            }
            .navigationTitle(PlaylistWords.addToAPlaylist)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PlaylistWords.cancel) { dismiss() }
                }
            }
        }
        .task {
            // afresh each time it opens
            await playlists.ask(fresh: true)
        }
        .onAppear { model.shown = true }
        .onDisappear { model.shown = false }
        .onChange(of: model.finished) { _, finished in
            if finished { dismiss() }
        }
        .onChange(of: model.question != nil) { _, asking in
            refocus(asking ? .question : .first)
        }
    }

    // MARK: the list

    @ViewBuilder private func listSection(_ rows: [Playlist]) -> some View {
        Section {
            if playlists.list != nil, rows.isEmpty, playlists.failure == nil {
                Text(PlaylistWords.noPlaylistsYet)
                    .foregroundStyle(Palette.quiet)
            }
            if model.making {
                NewPlaylistFields(busyOutside: playlists.writes.busy) { name in
                    try await model.make(name: name, playlists: playlists, player: player)
                } cancel: {
                    model.making = false
                    refocus(.first)
                }
            } else {
                Button {
                    guard !playlists.writes.busy else { return }
                    model.making = true
                } label: {
                    PickerRow(cover: nil, name: PlaylistWords.newPlaylistRow, line: nil, symbol: "plus")
                }
                .disabled(playlists.writes.busy)
                .accessibilityFocused($focus, equals: .first)
            }
            ForEach(rows) { playlist in
                Button {
                    model.add(to: playlist, mode: .ask, playlists: playlists, player: player, admin: server.access.seesDetail)
                } label: {
                    PickerRow(cover: playlist.coverArt, name: playlist.name,
                              line: playlists.writes.adding(playlist.id) != nil ? PlaylistWords.adding
                                  : PlaylistRules.songCount(playlist.songCount),
                              symbol: nil)
                }
                .disabled(playlists.writes.busy)
            }
            if playlists.list == nil {
                if let failure = playlists.failure {
                    VStack(alignment: .leading, spacing: 8) {
                        ErrorNote(text: PlaylistWords.listFailed(ErrorWords.of(failure, admin: server.access.seesDetail,
                                                                               retry: true).said))
                        Button(PlaylistWords.tryAgain) { Task { await playlists.ask(fresh: true) } }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(PlaylistWords.loading)
                }
            }
        }
    }

    // MARK: the question

    private func questionSection(_ question: PlaylistPickerFlow.Asked) -> some View {
        let asked = PlaylistRules.duplicateQuestion(already: question.already, asked: question.asked, pick: model.pick,
                                                    name: question.playlist.name)
        let adding = playlists.writes.adding(question.playlist.id)
        return Section {
            Text(asked.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($focus, equals: .question)
            Button {
                model.add(to: question.playlist, mode: .add, playlists: playlists, player: player,
                          admin: server.access.seesDetail)
            } label: {
                Text(adding != nil && adding == asked.yes.mode ? PlaylistWords.adding : asked.yes.label)
                    .fontWeight(.semibold)
            }
            .disabled(playlists.writes.busy)
            Button {
                if let mode = asked.no.mode {
                    model.add(to: question.playlist, mode: mode, playlists: playlists, player: player,
                              admin: server.access.seesDetail)
                } else {
                    model.back()
                }
            } label: {
                Text(adding != nil && adding == asked.no.mode ? PlaylistWords.adding : asked.no.label)
            }
            .disabled(playlists.writes.busy)
        }
    }

    /// VoiceOver's focus to `target` once the change has been drawn - never dropped to the sheet's top.
    private func refocus(_ target: PickerFocus) {
        Task { @MainActor in focus = target }
    }
}

/// One row of the picker: the playlist's mosaic (or New playlist…'s plus on the empty cover's square), its name and its
/// count - "Adding…" while its add is out. Read as one: "Late night, 12 songs".
private struct PickerRow: View {
    let cover: String?
    let name: String
    let line: String?
    let symbol: String?

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                ZStack {
                    Palette.coverEmpty
                    Image(systemName: symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
            } else {
                PlaylistCover(id: cover, side: LibraryRow.cover, pixels: CoverSize.row, corner: 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.primary)
                if let line {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
            }
            .lineLimit(2)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The picker's state, one per opening - Core's PlaylistPickerFlow: what it adds, New playlist…'s name, the question, why
/// the last add was refused. The write out is PlaylistsModel's (`writes`), shared by every opening. Its writes run in
/// tasks of their own, which the sheet closing never calls off - `shown` says whether what they answer is drawn here or
/// said in the app's notice.
@MainActor
@Observable
final class PlaylistPickerModel {
    private(set) var flow: PlaylistPickerFlow

    init(pick: PlaylistPick) {
        flow = PlaylistPickerFlow(pick: pick)
    }

    var pick: PlaylistPick { flow.pick }
    /// New playlist…'s name, open in place of its row.
    var making: Bool {
        get { flow.making }
        set { flow.making = newValue }
    }
    /// Some of the songs are in the playlist already: the question, in place of the list.
    var question: PlaylistPickerFlow.Asked? { flow.question }
    /// The last add was refused: why, under the head.
    var failure: (any Error)? { flow.failure }
    /// Done: the sheet closes.
    var finished: Bool { flow.finished }
    /// The sheet is up: an answer is drawn here, else said in the notice.
    var shown: Bool {
        get { flow.shown }
        set { flow.shown = newValue }
    }

    /// The question's Cancel: back to the list.
    func back() { flow.back() }

    /// The songs added to `playlist` - `mode` `.ask` from the list, the question's choice from it. Nothing while the
    /// picker's write is out, from this opening or another.
    func add(to playlist: Playlist, mode: PlaylistDuplicates, playlists: PlaylistsModel, player: PlayerModel, admin: Bool) {
        guard !playlists.writes.busy, !flow.pick.songs.isEmpty else { return }
        flow.sending()
        let ids = flow.pick.ids
        Task { @MainActor in
            do {
                let answer = try await playlists.add(ids, to: playlist.id, duplicates: mode)
                said(flow.answered(answer, mode: mode, to: playlist), playlists: playlists, player: player)
            } catch is PlaylistsModel.Superseded {
                return
            } catch {
                said(flow.failed(error, to: playlist, admin: admin), playlists: playlists, player: player)
            }
        }
    }

    /// New playlist… with the songs: made, said, and the sheet closed - or thrown, for the name's form to say why.
    func make(name: String, playlists: PlaylistsModel, player: PlayerModel) async throws {
        guard !playlists.writes.busy else { return }
        do {
            let made = try await playlists.create(name: name, songIDs: flow.pick.ids, picker: true)
            said(flow.made(made.playlist), playlists: playlists, player: player)
        } catch is PlaylistsModel.Superseded {
            return
        }
    }

    /// What the flow says beyond the sheet: a playlist gone, the notice, VoiceOver.
    private func said(_ said: PlaylistPickerFlow.Said, playlists: PlaylistsModel, player: PlayerModel) {
        if let gone = said.gone { playlists.gone(gone) }
        if let notice = said.notice { player.say(notice) }
        if let announce = said.announce { Notice.announce(announce) }
    }
}

/// New playlist's name (the web's NewPlaylistForm.tsx) - the picker's, in place of its row, and the Playlists screen's
/// sheet: a Name field, Create and Cancel. Create waits while the name is blank and while it is out ("Creating…");
/// refused, the form stays with why under it. The field takes focus as it opens; Return creates. `create` makes the
/// playlist and returns once it is made (the caller takes it from there) or throws why.
struct NewPlaylistFields: View {
    /// Another write is out (the picker's add): Create waits for it.
    var busyOutside = false
    let create: (String) async throws -> Void
    let cancel: () -> Void

    @Environment(ServerModel.self) private var server
    @State private var name = ""
    @State private var busy = false
    @State private var failure: (any Error)?
    @FocusState private var focused: Bool

    private var blank: Bool { PlaylistEdit.trimmed(name).isEmpty }

    var body: some View {
        Group {
            TextField(PlaylistWords.nameField, text: $name)
                .focused($focused)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(send)
                .onChange(of: name) { (was: String, typed: String) -> Void in
                    // kept within the bound as an HTML field's maxLength keeps it
                    let kept = PlaylistEdit.typed(typed, was: was, max: PlaylistRules.nameMax)
                    if kept != typed { name = kept }
                }
                .accessibilityLabel(PlaylistWords.nameField)
            if let failure {
                ErrorNote(failure)
            }
            HStack {
                Button(busy ? PlaylistWords.creating : PlaylistWords.create, action: send)
                    .buttonStyle(PrimaryFace())
                    .disabled(blank || busy || busyOutside)
                Spacer()
                Button(PlaylistWords.cancel, role: .cancel, action: cancel)
                    .buttonStyle(SecondaryPill())
            }
        }
        .onAppear { focused = true }
    }

    private func send() {
        guard !blank, !busy, !busyOutside else { return }
        busy = true
        failure = nil
        let typed = PlaylistEdit.trimmed(name)
        Task { @MainActor in
            do {
                try await create(typed)
                busy = false
            } catch {
                busy = false
                failure = error
                Notice.announce(ErrorWords.of(error, admin: server.access.seesDetail).said)
            }
        }
    }
}
