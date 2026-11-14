import DeadwaxCore
import SwiftUI

/// One playlist's page (Phase 4, phase4-library.md 3.3; the web's app/PlaylistPage.tsx), laid out as an album's page:
/// Navidrome's 2x2 mosaic, the name, whose it is, why there is no Edit (when there is none), its description, the count
/// and length, Play and Shuffle; the songs not listed just now; the songs, each with its own cover; the footer. The bar's
/// ••• is the whole playlist's Play Next, Play Last and Add to a playlist….
///
/// PLAYING is PlayerModel.play(playlist:) with the songs in hand - from Play, Shuffle and a row's tap, in the tap,
/// nothing awaited first (the gesture rule): each song with its own album, at the songs level, the albums its songs are
/// on remembered first (PlaylistPlay: stubs, an album held whole kept as it is). A row's ••• is the song's own Play
/// Next, Play Last, Add to a playlist… and its download items; the bar's has no download items until a playlist
/// downloads as one (slice 3, question 7).
///
/// ASKED as it opens (PlaylistPageModel) - drawn at once from the answer kept for it (PlaylistsModel), else the hero
/// from the row that opened it - and again each time it shows, the app coming back to the front included, and when a
/// write here changed it (PlaylistsModel.lastChange); a refresh that fails keeps what is drawn and says so; a 404 says
/// it has gone; nothing drawn and the first ask failing: why, and Try again. While deadwax can't be reached nothing is
/// asked: what is in hand draws, the songs not on this phone dimmed, Play and Shuffle taking those that are. Download a
/// playlist is slice 3's.
///
/// EDIT (slice 2, phase4-library.md 2.4) - yours, editable, at most 2,000 songs, offered once this page's own ask has
/// answered and while deadwax is in reach: Edit in the bar, then the name, the description, "Shared with everyone"
/// (SHARED_NOTE under it), the songs not listed just now and what Done does to them, the songs - each with its red (-)
/// that takes it out, and the List's drag handle (Move up, Move down and Remove as VoiceOver's actions, what changed
/// said: "Roads: 3 of 12", "Roads removed") - and Delete playlist, last. All of it is saved at once with Done, as the
/// person signed in (PlaylistPageModel.done): nothing is drawn as saved before deadwax says it is. Changed in another
/// app since Edit began: nothing saved, the playlist drawn as it is now and PLAYLIST_CHANGED said at its top. Refused:
/// Edit stays open with why at the top of the form. Cancel takes Back's place, and asks first when there are changes
/// ("Discard your changes?"); Delete asks (deleteQuestion) - there is no undo - and, deleted, says so and goes back
/// while the page is still what shows. Play, Shuffle and the ••• wait while Edit is open.
struct PlaylistView: View {
    let route: PlaylistRoute

    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @Environment(PlaylistsModel.self) private var playlists
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PlaylistPageModel
    /// The hero's title has scrolled away: the bar shows it.
    @State private var titleInBar = false
    /// Cancel with changes: the question is up.
    @State private var asksDiscard = false
    /// Delete playlist: the question is up.
    @State private var asksDelete = false
    @AccessibilityFocusState private var focus: EditFocus?

    /// Where VoiceOver's focus goes after a change in Edit - never dropped to the page's top.
    enum EditFocus: Hashable {
        case row(String)
        case toggle
        case delete
        case top
    }

    /// The scroll places Done's outcomes go to.
    private enum Place: Hashable {
        case top, problem
    }

    init(route: PlaylistRoute) {
        self.route = route
        _model = State(initialValue: PlaylistPageModel(route: route))
    }

    /// Who and which playlist.
    private var taskKey: String { "\(server.person)|\(route.id)" }

    var body: some View {
        let online = reachability.online
        let songs = model.songs
        let editing = model.editing
        ScrollViewReader { proxy in
            List {
                PlaylistHero(model: model, playable: !playable.isEmpty && !editing,
                             play: { play(at: 0) }, shuffle: { play(at: nil, shuffle: true) })
                    .listRowSeparator(.hidden)
                    .id(Place.top)
                    .onAppear { setTitleInBar(false) }
                    .onDisappear { setTitleInBar(true) }

                // changed in another app while it was being edited: said where the playlist begins
                if let note = model.note, !editing {
                    ErrorNote(text: note)
                        .listRowSeparator(.hidden)
                        .accessibilityFocused($focus, equals: .top)
                }

                if editing {
                    editSections()
                } else {
                    if model.hidden > 0 {
                        QuietLine(text: PlaylistRules.hiddenWords(model.hidden))
                            .listRowSeparator(.hidden)
                    }
                    pageRows(songs, online: online)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(editing ? .active : .inactive))
            .navigationTitle(model.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(editing)
            .toolbar { toolbar(proxy) }
            .task(id: taskKey) {
                model.online = reachability.online
                await model.load(key: taskKey, client: server.client, playlists: playlists)
            }
            .task { await downloads.followProgress() }
            .refreshable {
                guard reachability.online else {
                    reachability.tryNow()
                    return
                }
                await model.load(key: taskKey, client: server.client, playlists: playlists)
            }
            .onChange(of: reachability.online) { _, online in
                model.online = online
                // back: the playlist asked of deadwax now
                guard online else { return }
                Task { await model.load(key: taskKey, client: server.client, playlists: playlists) }
            }
            .onChange(of: scenePhase) { _, phase in
                // the app back in front is the page shown again (the web's): the playlist asked again
                guard phase == .active, reachability.online else { return }
                Task { await model.load(key: taskKey, client: server.client, playlists: playlists) }
            }
            .onChange(of: playlists.lastChange) { _, change in
                // a write here changed it (an add from the picker, its own Done): asked again
                guard let change else { return }
                Task { await model.changedHere(change, client: server.client, playlists: playlists) }
            }
        }
    }

    /// The page's songs out of Edit: gone, failed, offline, loading, empty, or the rows and their footer.
    @ViewBuilder private func pageRows(_ songs: [Song], online: Bool) -> some View {
        if model.gone {
            ErrorNote(text: PlaylistWords.playlistGone)
                .listRowSeparator(.hidden)
        } else if model.answer == nil {
            if let failure = model.failure {
                OpenFailedNote(failure: failure) {
                    Task { await model.retry(client: server.client, playlists: playlists) }
                }
                .listRowSeparator(.hidden)
            } else if !online {
                QuietLine(text: PlaylistWords.offlinePage)
                    .listRowSeparator(.hidden)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(PlaylistWords.loading)
                    .listRowSeparator(.hidden)
            }
        } else {
            if online, let failure = model.failure {
                RefreshFailedNote(failure: failure)
                    .listRowSeparator(.hidden)
            }
            if songs.isEmpty {
                QuietLine(text: PlaylistWords.playlistEmpty)
                    .listRowSeparator(.hidden)
            } else {
                rows(songs, offline: !online)
                Text(PlaylistRules.songsLine(songs.count, seconds: PlaylistRules.total(songs)))
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .listRowSeparator(.hidden, edges: .bottom)
            }
        }
    }

    // MARK: the bar

    @ToolbarContentBuilder private func toolbar(_ proxy: ScrollViewProxy) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(model.name)
                .font(.headline)
                .lineLimit(1)
                .opacity(titleInBar ? 1 : 0)
                .accessibilityHidden(!titleInBar)
        }
        if model.editing {
            // Cancel in Back's place - asking first when Edit holds changes
            ToolbarItem(placement: .cancellationAction) {
                Button(PlaylistWords.cancel) {
                    guard !model.busy else { return }
                    if model.changed { asksDiscard = true } else { leaveEdit() }
                }
                .disabled(model.busy)
                .confirmationDialog(PlaylistWords.discardQuestion, isPresented: $asksDiscard, titleVisibility: .visible) {
                    Button(PlaylistWords.discard, role: .destructive) { leaveEdit() }
                    Button(PlaylistWords.keepEditing, role: .cancel) { refocus(.toggle) }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(model.saving ? PlaylistWords.saving : PlaylistWords.done) { done(proxy) }
                    .disabled(model.busy || model.needsName)
                    .accessibilityFocused($focus, equals: .toggle)
            }
        } else {
            if model.editable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(PlaylistWords.edit) { beginEdit() }
                        .disabled(!model.canBegin)
                        .accessibilityFocused($focus, equals: .toggle)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                QueueMenu(request: playlistMenu) {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(PlaylistWords.moreForPlaylist)
            }
        }
    }

    /// The songs: Navidrome's own, as they are - a song twice is two rows. `offline`: a song not on this phone is dimmed.
    @ViewBuilder private func rows(_ songs: [Song], offline: Bool) -> some View {
        let heard = player.current?.track
        // the slot on every row where any song has a state, on none where none does
        let slot = songs.contains { downloads.state($0.id) != .none }
        ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
            let state = downloads.state(song.id)
            PlaylistSongRow(song: song, current: PlayingBars.marks(song, heard: heard), playing: player.isPlaying,
                            play: { play(row: index) },
                            menu: QueueMenuRequest(pick: PlaylistPlay.pick(song: song), album: nil),
                            download: state, slot: slot, dimmed: offline && !state.isHere,
                            actions: downloads.isOpen ? downloads.choices(song: song.id) : []) { choice in
                act(choice, on: song)
            }
        }
    }

    /// The bar's •••: the whole playlist, as songs - nil (the ••• dimmed) until its songs are in, once gone, and while
    /// Edit is open.
    private var playlistMenu: QueueMenuRequest? {
        guard !model.gone, !model.editing,
              let pick = PlaylistPlay.pick(name: model.name, songs: model.songs) else { return nil }
        return QueueMenuRequest(pick: pick, album: nil, offersDownload: false)
    }

    /// What Play and Shuffle take: the songs - offline, those on this phone, in the playlist's order.
    private var playable: [Song] {
        guard !reachability.online else { return model.songs }
        return OfflineAlbum.playable(model.songs, here: downloads.isHere)
    }

    /// Play, Shuffle: the songs, from `index` (nil with Shuffle: any song first). In the tap - nothing awaited before
    /// the player is called.
    private func play(at index: Int?, shuffle: Bool = false) {
        let songs = playable
        guard !songs.isEmpty else { return }
        player.play(playlist: songs, at: index, shuffle: shuffle)
    }

    /// A row's tap: the playlist from that row - offline, from its place among the songs on this phone (a song twice
    /// is two rows, so its place is counted, not looked up by id).
    private func play(row: Int) {
        let songs = model.songs
        guard songs.indices.contains(row) else { return }
        if reachability.online {
            play(at: row)
            return
        }
        guard let start = PlaylistPlay.offlineStart(row: row, songs: songs, here: downloads.isHere) else { return }
        play(at: start)
    }

    /// A row's VoiceOver action - the song's ••• download items.
    private func act(_ choice: DownloadChoice, on song: Song) {
        switch choice {
        case .download: downloads.download(song)
        case .downloadAgain: downloads.tryAgain(song.id)
        case .remove:
            downloads.remove(song.id)
            player.say(DownloadWords.removed(song.title ?? ""))
        }
    }

    private func setTitleInBar(_ shown: Bool) {
        guard titleInBar != shown else { return }
        withAnimation(.easeInOut(duration: 0.2)) { titleInBar = shown }
    }

    // MARK: Edit

    /// Edit's form: why Done was refused (at its top, where Done scrolls to), the name, the description, sharing and its
    /// note, the songs not listed just now and what Done does to them; the songs; Delete playlist, last.
    @ViewBuilder private func editSections() -> some View {
        if let edit = model.edit {
            Section {
                if let failure = model.editFailure {
                    ErrorNote(failure)
                        .id(Place.problem)
                }
                TextField(PlaylistWords.nameField, text: nameBinding)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel(PlaylistWords.nameField)
                if model.needsName {
                    Text(PlaylistWords.needsAName)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                TextField(PlaylistWords.descriptionField, text: commentBinding, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityLabel(PlaylistWords.descriptionField)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(PlaylistWords.sharedWithEveryone, isOn: publicBinding)
                    Text(PlaylistWords.sharedNote)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(PlaylistWords.sharedNote)
                if model.hidden > 0 {
                    QuietLine(text: PlaylistRules.hiddenEditWords(model.hidden))
                }
            }
            .disabled(model.busy)

            Section {
                ForEach(Array(edit.rows.enumerated()), id: \.element.key) { index, row in
                    editRow(row, index: index, count: edit.rows.count)
                        .accessibilityFocused($focus, equals: .row(row.key))
                        .moveDisabled(model.busy)
                }
                .onMove { (source: IndexSet, destination: Int) -> Void in
                    guard let from = source.first else { return }
                    move(from: from, to: UpNextWords.movedTo(from: from, destination: destination))
                }
            } header: {
                Text(PlaylistWords.songsHeading)
                    .textCase(nil)
                    .accessibilityAddTraits(.isHeader)
            }

            Section {
                Button(role: .destructive) {
                    guard !model.busy else { return }
                    asksDelete = true
                } label: {
                    Text(model.deleting ? PlaylistWords.deleting : PlaylistWords.deletePlaylist)
                }
                .disabled(model.busy)
                .accessibilityFocused($focus, equals: .delete)
                .confirmationDialog(PlaylistRules.deleteQuestion(deleteName), isPresented: $asksDelete,
                                    titleVisibility: .visible) {
                    Button(PlaylistWords.deletePlaylist, role: .destructive) { deletePlaylist() }
                    Button(PlaylistWords.keepIt, role: .cancel) { refocus(.delete) }
                }
                if let failure = model.deleteFailure {
                    ErrorNote(failure)
                }
            }
        }
    }

    /// A row in Edit (Up Next's, UpNextScreen.editRow): its red (-), which takes it out at once - Cancel puts it back,
    /// nothing being saved before Done - and its title and artist; the List draws the drag handle. One VoiceOver
    /// element, its (-) left out: Move up, Move down (none past an end) and Remove are its actions, so a double tap on
    /// the row never takes a song out.
    private func editRow(_ row: PlaylistEditRow, index: Int, count: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(model.busy)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .foregroundStyle(.primary)
                if !row.artist.isEmpty {
                    Text(row.artist)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.title, row.artist].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityActions {
            if index > 0 {
                Button(UpNextWords.moveUp(row.title)) { move(from: index, to: index - 1) }
            }
            if index < count - 1 {
                Button(UpNextWords.moveDown(row.title)) { move(from: index, to: index + 1) }
            }
            Button(UpNextWords.remove(row.title)) { remove(at: index) }
        }
    }

    private var nameBinding: Binding<String> {
        Binding(get: { model.edit?.name ?? "" },
                set: { (typed: String) -> Void in model.edit?.name = PlaylistEdit.clamped(typed, to: PlaylistRules.nameMax) })
    }

    private var commentBinding: Binding<String> {
        Binding(get: { model.edit?.comment ?? "" },
                set: { (typed: String) -> Void in
                    model.edit?.comment = PlaylistEdit.clamped(typed, to: PlaylistRules.commentMax)
                })
    }

    private var publicBinding: Binding<Bool> {
        Binding(get: { model.edit?.isPublic ?? false }, set: { (on: Bool) -> Void in model.edit?.isPublic = on })
    }

    /// Delete's question names the playlist as typed, else as it is (the web's `edit.name.trim() || name`).
    private var deleteName: String {
        let typed = PlaylistEdit.trimmed(model.edit?.name ?? "")
        return typed.isEmpty ? model.name : typed
    }

    private func beginEdit() {
        model.beginEdit()
        guard model.editing else { return }
        refocus(.toggle)
    }

    /// Edit closed, nothing sent - the playlist asked again after a Done that failed.
    private func leaveEdit() {
        if model.leaveEdit() {
            Task { await model.load(key: taskKey, client: server.client, playlists: playlists) }
        }
        refocus(.toggle)
    }

    /// The row at `from` to `to`, said.
    private func move(from: Int, to: Int) {
        guard let rows = model.edit?.rows, rows.indices.contains(from), rows.indices.contains(to), to != from,
              !model.busy else { return }
        let row = rows[from]
        model.move(from: from, to: to)
        Notice.announce(UpNextWords.movedSaid(row.title, to: to, of: rows.count))
        refocus(.row(row.key))
    }

    /// The row at `index` taken out, said - focus to the row after it, else the one before, else Done.
    private func remove(at index: Int) {
        guard let rows = model.edit?.rows, rows.indices.contains(index), !model.busy else { return }
        let row = rows[index]
        let next = rows.indices.contains(index + 1) ? rows[index + 1] : (index > 0 ? rows[index - 1] : nil)
        model.remove(at: index)
        Notice.announce(UpNextWords.removedSaid(row.title))
        refocus(next.map { .row($0.key) } ?? .toggle)
    }

    /// Done: sent, and what came of it shown - the page at its top for a change made elsewhere, the form's top for why
    /// it was refused.
    private func done(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            let outcome = await model.done(playlists: playlists)
            switch outcome {
            case .saved:
                refocus(.toggle)
            case .unchanged:
                refocus(.toggle)
                // left after a Done that failed: what is drawn may be old - asked again before Edit is offered
                if !model.fresh { await model.load(key: taskKey, client: server.client, playlists: playlists) }
            case .changedElsewhere:
                withAnimation { proxy.scrollTo(Place.top, anchor: .top) }
                Notice.announce(PlaylistWords.playlistChanged)
                refocus(.top)
                await model.load(key: taskKey, client: server.client, playlists: playlists)
            case .gone:
                withAnimation { proxy.scrollTo(Place.top, anchor: .top) }
                Notice.announce(PlaylistWords.playlistGone)
            case .refused:
                withAnimation { proxy.scrollTo(Place.problem, anchor: .top) }
                if let failure = model.editFailure {
                    Notice.announce(ErrorWords.of(failure, admin: server.access.seesDetail).said)
                }
            case .notSent:
                break
            }
        }
    }

    /// Delete, answered: said in the notice, and back from the page while it is still what shows.
    private func deletePlaylist() {
        let name = model.name
        Task { @MainActor in
            if await model.delete(playlists: playlists) {
                player.say(PlaylistWords.deleted(name))
                navigation.leavePlaylist(route.id)
            } else if let failure = model.deleteFailure {
                Notice.announce(ErrorWords.of(failure, admin: server.access.seesDetail).said)
                refocus(.delete)
            }
        }
    }

    /// VoiceOver's focus to `target` once the change has been drawn.
    private func refocus(_ target: EditFocus) {
        Task { @MainActor in focus = target }
    }
}

/// The top of a playlist's page (PlaylistPage.tsx's hero): the mosaic at the hero's size - or the playlist mark - the
/// name (two lines, a step smaller over 60 letters), whose it is, why there is no Edit, the description, the count and
/// length, and Play and Shuffle, live once there are songs to play. Drawn at once from the row that opened the page.
private struct PlaylistHero: View {
    let model: PlaylistPageModel
    let playable: Bool
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        let playlist = model.playlist
        let songs = model.songs
        VStack(spacing: 0) {
            PlaylistCover(id: playlist?.coverArt, side: AlbumHero.coverSide, pixels: CoverSize.hero, corner: 10)
                .frame(maxWidth: AlbumHero.coverSide)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 8)

            Text(model.name)
                .font(Format.isLongTitle(model.name) ? .title3.bold() : .title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            if let playlist {
                Text(PlaylistRules.ownerLine(playlist))
                    .font(.title3)
                    .foregroundStyle(Palette.quiet)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, 2)
            }

            // why there is no Edit (somebody else's, a file's, too many songs) - known once the songs are in
            if let answer = model.answer, !model.gone,
               let words = PlaylistRules.readOnlyWords(answer.playlist, songs: answer.songs.count) {
                Text(words)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if let comment = playlist?.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            // the count holds its line while the songs come, so nothing below moves as it fills
            let line = model.answer != nil && !model.gone
                ? PlaylistRules.songsLine(songs.count, seconds: PlaylistRules.total(songs)) : ""
            Text(line.isEmpty ? " " : line)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .padding(.top, 6)
                .accessibilityHidden(line.isEmpty)

            PlayButtons(enabled: playable && !model.gone, play: play, shuffle: shuffle)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One song of a playlist (PlaylistPage.tsx's track row): the song's own cover, with the playing bars over it for the
/// song the player has (still while paused); its title; its artist and album; the download slot (as an album's rows:
/// on every row where any song has a state); its time; its ••• ("More for Roads"). A tap plays the playlist from it.
/// VoiceOver reads it as one: "Roads, Portishead · Dummy, Downloaded, 5:04" - "playing" or "paused" for the song the
/// player has - with the song's download items as its actions.
private struct PlaylistSongRow: View {
    let song: Song
    let current: Bool
    let playing: Bool
    let play: () -> Void
    let menu: QueueMenuRequest
    var download: SongDownload = .none
    var slot = false
    var dimmed = false
    var actions: [DownloadChoice] = []
    var act: (DownloadChoice) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The cover's side: as the Library's rows.
    private static let cover: CGFloat = LibraryRow.cover

    var body: some View {
        let line = PlaylistRules.songLine(song)
        HStack(spacing: 4) {
            Button(action: play) {
                HStack(spacing: 12) {
                    ZStack {
                        LibraryCover(id: song.coverArt, pixels: CoverSize.row)
                            .frame(width: Self.cover, height: Self.cover)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        if current {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.black.opacity(0.45))
                                .frame(width: Self.cover, height: Self.cover)
                            Image(systemName: "waveform")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: playing)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title ?? "")
                            .foregroundStyle(current ? Palette.accent : Color.primary)
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        if !line.isEmpty {
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(Palette.quiet)
                                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        }
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    Spacer(minLength: 8)
                    if slot { stateSlot }
                    Text(Format.trackTime(song.duration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Palette.quiet)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .opacity(dimmed ? Palette.off : 1)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken(line))
            .accessibilityActions {
                ForEach(actions, id: \.self) { choice in
                    Button(choice.label) { act(choice) }
                }
            }

            QueueMenu(request: menu) {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.quiet)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(AlbumPageLines.moreForSong(song.title ?? ""))
        }
    }

    /// The row as VoiceOver reads it: the title, playing or paused, the line, the download state, the time.
    private func spoken(_ line: String) -> String {
        var parts = [song.title ?? ""]
        if current { parts.append(PlayingBars.label(paused: !playing)) }
        if !line.isEmpty { parts.append(line) }
        let state: String? = dimmed ? DownloadWords.notOnPhone : DownloadWords.songLine(download)
        if let state { parts.append(state) }
        let time = Format.trackTime(song.duration)
        if !time.isEmpty { parts.append(time) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The one slot, as an album row's: the song's mark, or the room for one held.
    @ViewBuilder private var stateSlot: some View {
        ZStack {
            if let mark = DownloadWords.mark(download) {
                DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download), font: .caption)
            } else {
                DownloadMark(mark: .downloaded, font: .caption).hidden()
            }
        }
        .accessibilityHidden(true)
    }
}

/// A page's quiet line: a state in words, not a failure.
private struct QuietLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Palette.quiet)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}

/// "Couldn't open this playlist. <why>" and Try again - nothing in hand and the first ask failed.
private struct OpenFailedNote: View {
    let failure: any Error
    let retry: () -> Void

    @Environment(ServerModel.self) private var server

    var body: some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, retry: true)
        VStack(alignment: .leading, spacing: 8) {
            ErrorNote(text: PlaylistWords.openFailed(line.said), detail: line.detail)
            Button(PlaylistWords.tryAgain, action: retry)
        }
        .padding(.vertical, 4)
    }
}

/// "Couldn't update this playlist - showing it as it was. <why>" - a refresh that failed, what was drawn kept.
private struct RefreshFailedNote: View {
    let failure: any Error

    @Environment(ServerModel.self) private var server

    var body: some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, retry: false)
        ErrorNote(text: PlaylistWords.refreshFailed(line.said), detail: line.detail)
            .padding(.vertical, 4)
    }
}
