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
///
/// (The redesign, slice R18 - notes/ios.md "The panel review, R18: sheets, faces and banners (2026-11-26)") No List:
/// the sheet's own page (SheetPage) - the head in the small words, then the rows (SheetRows): on the phone each on its
/// hairline, the Library's playlist row (iPlaylists'), no fill; on the Mac a box of 30 pt rows. The question's two
/// answers are the look's buttons (the purple one first), New playlist's name on the look's well.
struct PlaylistPicker: View {
    let request: PlaylistPickRequest

    @Environment(PlaylistsModel.self) private var playlists
    @Environment(PlayerModel.self) private var player
    @Environment(ServerModel.self) private var server
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlaylistPickerModel
    @AccessibilityFocusState private var focus: PickerFocus?
    /// (The Mac app, slice 2) The new playlist's form has a name typed (NewPlaylistFields' `typed`).
    @State private var nameTyped = false

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
            SheetPage {
                Text(PlaylistRules.pickLine(model.pick))
                    .font(SheetLook.small)
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let failure = model.failure {
                    ErrorNote(failure)
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
                        // (the Mac app, slice 2) Escape is Cancel - but not with a new playlist's name typed, which
                        // Cancel throws away without asking
                        .escapeCloses(!(model.making && nameTyped))
                }
            }
        }
        .presentationBackground(SheetLook.ground)
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

    /// New playlist… and the playlists you can add to - only those, as before (PlaylistRules.picker: yours and
    /// editable) - each one of SheetRows' rows; New playlist's name in its row's place while it is open.
    @ViewBuilder private func listSection(_ rows: [Playlist]) -> some View {
        let busy = playlists.writes.busy
        if playlists.list != nil, rows.isEmpty, playlists.failure == nil {
            Text(PlaylistWords.noPlaylistsYet)
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
        }
        SheetRows {
            if model.making {
                NewPlaylistFields(busyOutside: busy, typed: Platform.mac ? $nameTyped : nil) { name in
                    try await model.make(name: name, playlists: playlists, player: player)
                } cancel: {
                    model.making = false
                    refocus(.first)
                }
                .padding(.vertical, SheetLook.gap)
                .sheetRow()
            } else {
                Button {
                    guard !playlists.writes.busy else { return }
                    model.making = true
                } label: {
                    PickerRow(cover: nil, name: PlaylistWords.newPlaylistRow, line: nil, symbol: "plus")
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .opacity(busy ? DWPalette.off : 1)
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
                .buttonStyle(.plain)
                .disabled(busy)
                // the one being added to stays as it is, "Adding…"; the rest wait, faded
                .opacity(busy && playlists.writes.adding(playlist.id) == nil ? DWPalette.off : 1)
            }
        }
        if playlists.list == nil {
            if let failure = playlists.failure {
                VStack(alignment: .leading, spacing: 8) {
                    ErrorNote(text: PlaylistWords.listFailed(ErrorWords.of(failure, admin: server.access.seesDetail,
                                                                           retry: true).said))
                    Button(PlaylistWords.tryAgain) { Task { await playlists.ask(fresh: true) } }
                        .buttonStyle(DWButtonStyle())
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(PlaylistWords.loading)
            }
        }
    }

    // MARK: the question

    /// Some of the songs are there already: the question in words, then its two answers - the purple one (add them
    /// again) and the other (skip those, or Cancel back to the list) - side by side, one over the other at the largest
    /// text sizes.
    private func questionSection(_ question: PlaylistPickerFlow.Asked) -> some View {
        let asked = PlaylistRules.duplicateQuestion(already: question.already, asked: question.asked, pick: model.pick,
                                                    name: question.playlist.name)
        let adding = playlists.writes.adding(question.playlist.id)
        return VStack(alignment: .leading, spacing: SheetLook.gap) {
            Text(asked.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityFocused($focus, equals: .question)
            SheetButtons { (stacked: Bool) in
                Button {
                    model.add(to: question.playlist, mode: .add, playlists: playlists, player: player,
                              admin: server.access.seesDetail)
                } label: {
                    SheetButtonWords(adding != nil && adding == asked.yes.mode ? PlaylistWords.adding : asked.yes.label)
                }
                .buttonStyle(DWButtonStyle(kind: .pri, fills: stacked))
                .disabled(playlists.writes.busy)
                Button {
                    if let mode = asked.no.mode {
                        model.add(to: question.playlist, mode: mode, playlists: playlists, player: player,
                                  admin: server.access.seesDetail)
                    } else {
                        model.back()
                    }
                } label: {
                    SheetButtonWords(adding != nil && adding == asked.no.mode ? PlaylistWords.adding : asked.no.label)
                }
                .buttonStyle(DWButtonStyle(fills: stacked))
                .disabled(playlists.writes.busy)
            }
        }
    }

    /// VoiceOver's focus to `target` once the change has been drawn - never dropped to the sheet's top.
    private func refocus(_ target: PickerFocus) {
        Task { @MainActor in focus = target }
    }
}

/// One row of the picker: the playlist's mosaic (or New playlist…'s plus on the empty cover's square), its name and its
/// count - "Adding…" while its add is out. Read as one: "Late night, 12 songs". (R18) On the phone the Library's
/// playlist row (LibraryListRow, iPlaylists' tall row on its hairline); on the Mac a box's row (`.row`) at View > Row
/// Size's height and cover - (the panel review's R19) handed in by the desktop frame (`sheetRowSize`), a sheet's window
/// being outside its environment; the sheet's own 30 and 20 where none was - the count after the name in the second
/// colour, a long name cut short with the whole of it in `.help` and VoiceOver.
private struct PickerRow: View {
    let cover: String?
    let name: String
    let line: String?
    let symbol: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.sheetRowSize) private var rowSize

    var body: some View {
        Group {
            if Platform.mac {
                HStack(spacing: 10) {
                    mark(side: rowSize?.cover ?? SheetLook.macCover)
                    Text(name)
                        .foregroundStyle(DWPalette.head)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    if let line {
                        Text(line)
                            .font(SheetLook.small)
                            .foregroundStyle(DWPalette.t2)
                            .lineLimit(1)
                    }
                }
                .font(SheetLook.words)
                .frame(minHeight: rowSize?.height ?? SheetLook.rowHeight)
                .sheetRow()
                .help(name)
            } else {
                LibraryListRow(title: name, line: line ?? "", lines: typeSize.isAccessibilitySize ? 2 : 1) {
                    mark(side: LibraryLook.rowCover)
                } trailing: {
                    EmptyView()
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, line].compactMap { $0 }.joined(separator: ", "))
    }

    /// The playlist's mosaic, or New playlist…'s plus in the accent on the empty cover's square - a picture's place.
    @ViewBuilder private func mark(side: CGFloat) -> some View {
        if let symbol {
            ZStack {
                Palette.coverEmpty
                Image(systemName: symbol)
                    .font(Typeface.symbol(size: side * 0.45, weight: .semibold))
                    .foregroundStyle(DWPalette.acc)
            }
            .frame(width: side, height: side)
            .clipShape(DWCorners.chipShape)
            .accessibilityHidden(true)
        } else {
            PlaylistCover(id: cover, side: side, pixels: CoverSize.row)
        }
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

/// New playlist's sheet (the Library's Playlists on the phone, the Mac's Playlists page - each with its own
/// NewPlaylistFields, the page's own Create): (R18) no List - the form on the sheet's own page (SheetPage), flat on the
/// phone's black, the Mac's window ground in its own window, under the sheet's bar and its title.
struct NewPlaylistSheet<Fields: View>: View {
    @ViewBuilder let fields: Fields

    var body: some View {
        NavigationStack {
            SheetPage {
                fields
            }
            .navigationTitle(PlaylistWords.newPlaylistTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationBackground(SheetLook.ground)
    }
}

/// New playlist's name (the web's NewPlaylistForm.tsx) - the picker's, in place of its row, and the Playlists screen's
/// sheet: a Name field, Create and Cancel. Create waits while the name is blank and while it is out ("Creating…");
/// refused, the form stays with why under it. The field takes focus as it opens; Return creates. `create` makes the
/// playlist and returns once it is made (the caller takes it from there) or throws why.
struct NewPlaylistFields: View {
    /// Another write is out (the picker's add): Create waits for it.
    var busyOutside = false
    /// (The Mac app, slice 2) Escape is this Cancel - the Playlists screen's sheet's, whose only Cancel it is; not the
    /// picker's, whose own Cancel closes the picker. Never with a name typed, which Cancel throws away without asking.
    var escapes = false
    /// (The Mac app, slice 2) Told whether a name is typed - the picker's on the Mac, whose own Cancel's Escape waits
    /// on it; nil on the iPhone.
    var typed: Binding<Bool>?
    let create: (String) async throws -> Void
    let cancel: () -> Void

    @Environment(ServerModel.self) private var server
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var name = ""
    @State private var busy = false
    @State private var failure: (any Error)?
    @FocusState private var focused: Bool

    private var blank: Bool { PlaylistEdit.trimmed(name).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // (R18) the name on the look's well on both devices (`.in`: the phone's square 36 at 16, the Mac's 24 at 13
            // with its corners), its prompt in the third colour, the well's edge the accent's while it has the cursor -
            // a tap on the well (or a finger's 44 round it) puts the cursor in it
            TextField(PlaylistWords.nameField, text: $name,
                      prompt: Text(PlaylistWords.nameField).foregroundStyle(DWPalette.t3))
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
                .textFieldStyle(.plain)
                .font(Typeface.Look.text(.field))
                .foregroundStyle(DWPalette.fieldText)
                .focusEffectDisabled()
                .padding(.horizontal, 8)
                .lookHeight(DWLook.here.fieldHeight)
                .background {
                    DWWell(focused: focused)
                        .contentShape(DWTarget(face: DWCorners.buttonShape))
                        .onTapGesture { focused = true }
                }
            if let failure {
                ErrorNote(failure)
            }
            // (R5) the shared buttons, the layout as it was: Create the purple one, Cancel the plain - (R5's review) one
            // over the other at the accessibility sizes, each across the row, as the other pages stack theirs, each word
            // up to three lines there - (R18) each filling the row there (a button's words fill only when it does)
            let stacked = typeSize.isAccessibilitySize
            let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout())
            layout {
                Button(action: send) {
                    words(busy ? PlaylistWords.creating : PlaylistWords.create)
                }
                .buttonStyle(DWButtonStyle(kind: .pri, fills: stacked))
                .disabled(blank || busy || busyOutside)
                if !stacked { Spacer() }
                Button(role: .cancel, action: cancel) {
                    words(PlaylistWords.cancel)
                }
                .buttonStyle(DWButtonStyle(fills: stacked))
                .escapeCloses(escapes && blank)
            }
        }
        .onAppear { focused = true }
        .onChange(of: blank, initial: true) { (_: Bool, now: Bool) -> Void in typed?.wrappedValue = !now }
        .onDisappear { typed?.wrappedValue = false }
    }

    /// (R5) A button's words: one line, three at the accessibility sizes.
    private func words(_ text: String) -> some View {
        Text(text)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
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
