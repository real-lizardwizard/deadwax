import DeadwaxCore
import SwiftUI

/// One playlist's page (Phase 4, phase4-library.md 3.3; the web's app/PlaylistPage.tsx), laid out as an album's page:
/// Navidrome's 2x2 mosaic, the name, whose it is, why there is no Edit (when there is none), its description, the count
/// and length, Play and Shuffle; the songs not listed just now; the songs (each with its own cover until R5, its album
/// under its title since); the footer. The bar's ••• is the whole playlist's Add to Queue and Add to a playlist….
///
/// PLAYING is PlayerModel.play(playlist:) with the songs in hand - from Play, Shuffle and a row's tap, in the tap,
/// nothing awaited first (the gesture rule): each song with its own album, at the songs level, the albums its songs are
/// on remembered first (PlaylistPlay: stubs, an album held whole kept as it is). A row's ••• is the song's own Add to
/// Queue, Add to a playlist… and its download items (and a row's swipe right, Add to Queue); the bar's has the
/// playlist's own, as one (slice 3, question 7) - Download, Download Again, Remove Download - headed with its state
/// since R5, when the control that sat beside it left the bar; for a playlist gone or with no songs, the download items
/// alone, so a download of it here can still be removed.
///
/// ASKED as it opens (PlaylistPageModel) - drawn at once from the answer kept for it (PlaylistsModel), else the hero
/// from the row that opened it - and again each time it shows, the app coming back to the front included, and when a
/// write here changed it (PlaylistsModel.lastChange); a refresh that fails keeps what is drawn and says so; a 404 says
/// it has gone; nothing drawn and the first ask failing: why, and Try again. While deadwax can't be reached nothing is
/// asked: what is in hand draws, the songs not on this phone dimmed, Play and Shuffle taking those that are.
///
/// DOWNLOAD (slice 3, phase4-library.md 2.5): the control in the bar beside the •••, the hero's download line once it
/// is downloaded; a downloaded playlist draws first from the answer this phone keeps (`stored`, so it opens with no
/// connection after a launch), and each answer the page is given - or its 404 - is told to the downloads (`heard`),
/// which keep it in step.
///
/// EDIT (slice 2, phase4-library.md 2.4) - yours, editable, at most 2,000 songs, offered once this page's own ask has
/// answered and while deadwax is in reach: Edit in the bar, then the name, the description, "Shared with everyone"
/// (SHARED_NOTE under it), the songs not listed just now and what Done does to them, the songs - each with its red (-)
/// that takes it out, and the List's drag handle (Move up, Move down and Remove as VoiceOver's actions, what changed
/// said: "Roads: 3 of 12", "Roads removed") - and Delete playlist, last. All of it is saved at once with Done, as the
/// person signed in (PlaylistPageModel.done): nothing is drawn as saved before deadwax says it is. Changed in another
/// app since Edit began: nothing saved, the playlist drawn as it is now and PLAYLIST_CHANGED said at its top. Refused:
/// Edit stays open with why at the top of the form, the page scrolled to it. Cancel takes Back's place, and asks first
/// when there are changes ("Discard your changes?"); the tab tapped again goes back no further than this page while Edit
/// is open (AppNavigation.editing). Delete asks (deleteQuestion) - there is no undo - and, deleted (or answered gone),
/// says so and goes back while the page is still what shows. The hero stays; Play, Shuffle, the pull and the ••• wait
/// while Edit is open.
///
/// PULL TO SHUFFLE (2026-11-15, James: "also let's add pull to shuffle to the album and playlists pages"; notes/ios.md
/// "Pull to shuffle on an album's and a playlist's page"): the Library's pull (ShufflePull, `pullsToShuffle`,
/// PullShuffleGraphic) on the page's List, its graphic above the hero; let go armed, it is the hero's Shuffle - the
/// same songs, each with its own album, from the same call, in the lift. Offline only the songs on this phone, or
/// "Nothing on this phone to shuffle"; with no songs to draw (loading, failed, gone, empty) nothing is drawn and
/// nothing plays (ShuffleCan.page). The pull never refreshes now, as the Library's doesn't: the page is asked as it
/// shows, as before, and the bar's •••'s Refresh asks now (offline, whether deadwax is back).
///
/// THE REDESIGN, SLICE R5 (iPlaylist.dc.html, Playlist.dc.html; notes/ios.md "The redesign, slice R5: an album,
/// Playlists, a playlist"):
/// - On the phone the bar holds iOS's back, Edit (as before) and the •••, iOS's own menu: Add to Queue, Add to a
///   playlist…, the playlist's Download items headed with its control's words - the control left the bar - and Refresh.
///   The hero and the rows are iPlaylist's: the cover 150, the name, whose and how long, the shared Play and Shuffle,
///   the rows 60 tall with each song's album under its title. The pull and the rows' swipe stay.
/// - On the Mac (`desk`, from MacAlbum.page(for:)), MacPlaylistPage draws the playlist in the List's place while Edit
///   isn't open, handed this page's own model and actions (PlaylistDesk); Edit - the order, the name, Delete playlist -
///   is this page's form on both. On the iPhone there is no desk (`init(route:)`).
struct PlaylistView<Desk: View>: View {
    let route: PlaylistRoute
    /// (R5) The Mac's playlist page, drawn in the List's place out of Edit - none on the iPhone.
    private let desk: ((PlaylistDesk) -> Desk)?

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
    /// The page's pull to shuffle.
    @State private var pull = ShufflePull()
    /// On screen - the page on top of its tab: it pulls only then.
    @State private var shown = false
    @AccessibilityFocusState private var focus: EditFocus?
    /// (R1c's review) Which of Edit's fields has the cursor - each field's own `.focused`: the phone draws each on the
    /// look's well (DWWellField), its edge the accent's while it has the cursor. On the Mac nothing reads it.
    @FocusState private var typing: EditField?

    /// Edit's two fields.
    private enum EditField: Hashable {
        case name, description
    }

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

    /// (R5) The Mac's: the playlist drawn by `desk` (MacPlaylistPage) out of Edit.
    init(route: PlaylistRoute, desk: @escaping (PlaylistDesk) -> Desk) {
        self.route = route
        self.desk = desk
        _model = State(initialValue: PlaylistPageModel(route: route))
    }

    /// Who and which playlist.
    private var taskKey: String { "\(server.person)|\(route.id)" }

    var body: some View {
        let online = reachability.online
        let songs = model.songs
        let editing = model.editing
        let playable = self.playable
        let can = pullCan(playable)
        ScrollViewReader { proxy in
            Group {
                if let desk, Platform.mac, !editing {
                    desk(PlaylistDesk(model: model, playable: playable, offline: !online, menu: playlistMenu,
                                      edit: model.editable ? { beginEdit() } : nil, canEdit: model.canBegin,
                                      play: { play(at: 0) }, shuffle: { play(at: nil, shuffle: true) },
                                      playRow: { (row: Int) -> Void in play(row: row) },
                                      row: { (song: Song) -> QueueMenuRequest in rowMenu(song) },
                                      retry: { Task { await model.retry(client: server.client, playlists: playlists) } }))
                } else {
                    page(proxy, online: online, songs: songs, editing: editing, can: can, playable: playable)
                }
            }
            // (the Mac app, slice 2) ⌘R: the •••'s Refresh, while the page shows; nothing on the iPhone
            .refreshCommand { refresh() }
            .environment(\.editMode, .constant(editing ? .active : .inactive))
            .navigationTitle(model.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(editing)
            .toolbar { toolbar(proxy) }
            .task(id: taskKey) {
                model.online = reachability.online
                // (slice 3) a downloaded playlist drawn from this phone, and kept in step by what the page is answered
                let downloads = downloads
                model.stored = { (id: String) -> PlaylistWithSongs? in downloads.keptPlaylist(id) }
                let id = route.id
                model.heard = { (answer: PlaylistWithSongs?) -> Void in
                    if let answer { downloads.playlistAnswered(answer) } else { downloads.playlistGone(id) }
                }
                await model.load(key: taskKey, client: server.client, playlists: playlists)
            }
            .task { await downloads.followProgress() }
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
            .onChange(of: model.refusals) { _, _ in
                // Done refused, Edit open: to why, at the form's top - once the row saying it has been drawn
                Task { @MainActor in
                    withAnimation { proxy.scrollTo(Place.problem, anchor: .top) }
                }
            }
            .onChange(of: model.editing) { _, editing in
                navigation.editing(route.id, editing)
            }
            // (the Mac app, slice 2) Edit's changes aren't lost by closing the window: ⌘W and the close button are off
            // while Cancel would ask
            .keepsWindowOpen(model.editing && model.changed)
            .onAppear { shown = true }
            .onDisappear {
                shown = false
                // popped, not covered: a tab tapped again needn't stop at it any more
                navigation.pageGone(route.id)
            }
        }
    }

    /// The phone's page (and the Mac's in Edit): the List of the hero, the notes, Edit's form or the songs.
    private func page(_ proxy: ScrollViewProxy, online: Bool, songs: [Song], editing: Bool, can: ShuffleCan,
                      playable: [Song]) -> some View {
            List {
                PlaylistHero(model: model, download: model.gone ? nil : downloads.playlistState(route.id),
                             smart: downloads.playlistIsSmart(route.id, answer: model.answer),
                             playable: !playable.isEmpty && !editing,
                             play: { play(at: 0) }, shuffle: { play(at: nil, shuffle: true) })
                    .overlay(alignment: .top) {
                        // the pull's graphic, in the room the pull opens above the hero, as the Library's above its
                        // first row: its foot at the hero's top
                        PullShuffleGraphic(state: pull, can: can, of: .page)
                            .fixedSize(horizontal: false, vertical: true)
                            .alignmentGuide(.top) { (drawn: ViewDimensions) -> CGFloat in drawn[.bottom] }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
            // the pull shuffles the playlist (never refreshes), while the page is the one on top and Edit isn't open
            .pullsToShuffle(PullShuffling(state: pull, can: can, on: shown && !editing, start: pulled))
            // (R5) the page's ground - (R1c's review) on the phone `.dw.ph`'s black, iPlaylist's, so the mini player and
            // the tab bar sit on it with no seam; the Mac's (Edit, drawn here) --bg, as R5 drew it
            .scrollContentBackground(.hidden)
            .background(Platform.mac ? DWPalette.bg : DWPalette.page)
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
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t3)
                    .listRowSeparator(.hidden, edges: .bottom)
                    .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: the bar

    @ToolbarContentBuilder private func toolbar(_ proxy: ScrollViewProxy) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(model.name)
                .font(Typeface.headline)
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
                // (the Mac app, slice 2) Escape is Cancel: it leaves Edit, or asks first with something changed - (slice
                // 3's review) only when it is the page's: a field with the cursor, then a side panel's Done, come first
                .escapeCloses(MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == .page)
                .confirmationDialog(PlaylistWords.discardQuestion, isPresented: $asksDiscard, titleVisibility: .visible) {
                    Button(PlaylistWords.discard, role: .destructive) { leaveEdit() }
                    Button(PlaylistWords.keepEditing, role: .cancel) { refocus(.toggle) }
                        .returnCancels()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(model.saving ? PlaylistWords.saving : PlaylistWords.done) { done(proxy) }
                    .disabled(model.busy || model.needsName)
                    .accessibilityFocused($focus, equals: .toggle)
            }
        } else if desk == nil || !Platform.mac {
            // (R5, iPlaylist's top row) Edit, then the ••• - iOS's own menu, holding Download in the control's place
            if model.editable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(PlaylistWords.edit) { beginEdit() }
                        .disabled(!model.canBegin)
                        .accessibilityFocused($focus, equals: .toggle)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let menu = playlistMenu {
                    QueueMenu(request: menu) {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel(PlaylistWords.moreForPlaylist)
                } else {
                    // (R5's review) gone, or with no songs to queue: the ••• keeps the playlist's download items -
                    // Remove Download while a download of it is here - as the bar's control beside it did
                    Menu {
                        PlaylistDownloadMenuSection(answer: model.gone ? nil : model.answer, id: route.id, titled: true)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuOrder(.fixed)
                    .disabled(downloads.playlistState(route.id) == nil || !downloads.isOpen)
                    .accessibilityLabel(PlaylistWords.moreForPlaylist)
                }
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
                            menu: rowMenu(song),
                            download: state, slot: slot, dimmed: offline && !state.isHere,
                            actions: downloads.isOpen ? downloads.choices(song: song.id) : []) { choice in
                act(choice, on: song)
            }
            // (R5) iPlaylist's .row.tall: edge to edge, on the row's rule
            .listRowInsets(EdgeInsets())
            .listRowSeparatorTint(DWPalette.rowRule)
            .listRowBackground(Color.clear)
        }
    }

    /// A song's own •••: the one song, with its own album - its row's on the phone, its right-click on the Mac.
    private func rowMenu(_ song: Song) -> QueueMenuRequest {
        QueueMenuRequest(pick: PlaylistPlay.pick(song: song), album: nil)
    }

    /// The bar's •••: the whole playlist, as songs, with the playlist's own download items (slice 3) - nil (the •••
    /// dimmed) until its songs are in, once gone, and while Edit is open.
    private var playlistMenu: QueueMenuRequest? {
        guard !model.gone, !model.editing,
              var request = QueueMenuRequest.playlist(model.answer, name: model.name, songs: model.songs) else { return nil }
        request.refresh = { refresh() }
        return request
    }

    /// What the pull can do (ShuffleCan.page): the playlist's songs, as the hero's Shuffle takes them (`playable`) - while
    /// deadwax can't be reached, only those on this phone; nothing while there are no songs to draw.
    private func pullCan(_ playable: [Song]) -> ShuffleCan {
        ShuffleCan.page(songs: model.songs.count, phoneOnly: !reachability.online, onPhone: playable.count)
    }

    /// The pull let go armed: the hero's Shuffle, in the lift - nothing awaited first. Should the songs on this phone have
    /// gone since it armed (a removal), said, as the Library's pull says it.
    private func pulled() {
        if playable.isEmpty, !reachability.online {
            player.say(PullShuffleWords.nothingHere(Platform.device))
            return
        }
        play(at: nil, shuffle: true)
    }

    /// The •••'s Refresh (the pull was this until it shuffled): the playlist asked again now - or, while deadwax can't be
    /// reached, whether it is back.
    private func refresh() {
        guard reachability.online else {
            reachability.tryNow()
            return
        }
        Task { await model.load(key: taskKey, client: server.client, playlists: playlists) }
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
            player.say(DownloadWords.removed(song.title ?? "", device: Platform.device))
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
                    .focused($typing, equals: .name)
                    .accessibilityLabel(PlaylistWords.nameField)
                    .onChange(of: model.edit?.name) { (was: String?, typed: String?) -> Void in
                        guard let was, let typed else { return }
                        let kept = PlaylistEdit.typed(typed, was: was, max: PlaylistRules.nameMax)
                        if kept != typed { model.edit?.name = kept }
                    }
                    // (R1c's review) on the phone a box, as every place you type is: the look's well
                    .modifier(DWWellField(focus: $typing, field: .name))
                if model.needsName {
                    Text(PlaylistWords.needsAName)
                        .font(Typeface.footnote)
                        .foregroundStyle(.red)
                }
                TextField(PlaylistWords.descriptionField, text: commentBinding, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($typing, equals: .description)
                    .accessibilityLabel(PlaylistWords.descriptionField)
                    .onChange(of: model.edit?.comment) { (was: String?, typed: String?) -> Void in
                        guard let was, let typed else { return }
                        let kept = PlaylistEdit.typed(typed, was: was, max: PlaylistRules.commentMax)
                        if kept != typed { model.edit?.comment = kept }
                    }
                    .modifier(DWWellField(focus: $typing, field: .description, lines: true))
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(PlaylistWords.sharedWithEveryone, isOn: publicBinding)
                    Text(PlaylistWords.sharedNote)
                        .font(Typeface.footnote)
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
                Group {
                    Text(PlaylistWords.songsHeading)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
                .font(Typeface.footnote)
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
                        .returnCancels()
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
                    .font(Typeface.symbol(.title3))
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
                        .font(Typeface.footnote)
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

    /// The name as typed, taken as it is: the field's onChange then puts it back within its bound (PlaylistEdit.typed)
    /// as a change of its own, so the field shows what was kept - a setter refusing the text would change nothing, and
    /// the field would go on showing what the model never took.
    private var nameBinding: Binding<String> {
        Binding(get: { model.edit?.name ?? "" }, set: { (typed: String) -> Void in model.edit?.name = typed })
    }

    private var commentBinding: Binding<String> {
        Binding(get: { model.edit?.comment ?? "" }, set: { (typed: String) -> Void in model.edit?.comment = typed })
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
                // (scrolled to why by the page's onChange of `refusals`, once its row is drawn)
                if let failure = model.editFailure {
                    Notice.announce(ErrorWords.of(failure, admin: server.access.seesDetail).said)
                }
            case .notSent:
                break
            }
        }
    }

    /// Delete, answered: said in the notice, and back from the page while it is still what shows - a 404 (gone in
    /// another app already) as a delete.
    private func deletePlaylist() {
        let name = model.name
        Task { @MainActor in
            switch await model.delete(playlists: playlists) {
            case .deleted:
                player.say(PlaylistWords.deleted(name))
                navigation.leavePlaylist(route.id)
            case .gone:
                player.say(PlaylistWords.playlistGone)
                navigation.leavePlaylist(route.id)
            case .refused:
                if let failure = model.deleteFailure {
                    Notice.announce(ErrorWords.of(failure, admin: server.access.seesDetail).said)
                }
                refocus(.delete)
            case .notSent:
                break
            }
        }
    }

    /// VoiceOver's focus to `target` once the change has been drawn.
    private func refocus(_ target: EditFocus) {
        Task { @MainActor in focus = target }
    }
}

extension PlaylistView where Desk == EmptyView {
    /// The iPhone's page (and every one but the Mac's own): no desk.
    init(route: PlaylistRoute) {
        self.route = route
        desk = nil
        _model = State(initialValue: PlaylistPageModel(route: route))
    }
}

/// (R5) What the Mac's playlist page (MacPlaylistPage) is handed by PlaylistView: the page's own model and its actions -
/// every ask, write, Edit and leaving stays PlaylistView's, and the Mac draws.
struct PlaylistDesk {
    let model: PlaylistPageModel
    /// What Play and Shuffle take: the songs - offline, those on this Mac.
    let playable: [Song]
    /// deadwax out of reach: the songs not on this Mac are dimmed.
    let offline: Bool
    /// The playlist's own ••• (Add to Queue, Add to a playlist…, its Download items, Refresh) - nil until its songs are
    /// in, once gone, and while Edit is open.
    let menu: QueueMenuRequest?
    /// Edit - the order, the name, the description, sharing, Delete playlist: PlaylistView's own form - for a playlist
    /// that is yours to edit; nil otherwise.
    let edit: (() -> Void)?
    /// Edit can open now (PlaylistPageModel.canBegin: this page's own ask answered, deadwax in reach) - dimmed till then,
    /// as the phone's.
    let canEdit: Bool
    /// Play from the first song, Shuffle, a row's double-click or Return - PlaylistView's own calls, in the tap.
    let play: () -> Void
    let shuffle: () -> Void
    let playRow: (Int) -> Void
    /// A song's own •••, its right-click.
    let row: (Song) -> QueueMenuRequest
    /// Nothing drawn and the first ask failed: asked again.
    let retry: () -> Void
}

/// The top of a playlist's page (PlaylistPage.tsx's hero): the mosaic at the hero's size - or the playlist mark - the
/// name (two lines, a step smaller over 60 letters), whose it is, why there is no Edit, the description, the count and
/// length, and Play and Shuffle, live once there are songs to play. Drawn at once from the row that opened the page.
private struct PlaylistHero: View {
    let model: PlaylistPageModel
    /// (slice 3) The playlist's download, once downloaded - its line under the count.
    let download: AlbumDownload?
    /// (slice 3's review) A smart playlist: no Download, and the line says why - or, downloaded, that it is kept as it
    /// was.
    let smart: Bool
    let playable: Bool
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        let playlist = model.playlist
        let songs = model.songs
        VStack(spacing: 0) {
            // (R5, iPlaylist.dc.html) the cover 150, square and flat
            PlaylistCover(id: playlist?.coverArt, side: AlbumPageLook.playlistCover, pixels: CoverSize.hero)
                .frame(width: AlbumPageLook.playlistCover, height: AlbumPageLook.playlistCover)
                .padding(.top, AlbumPageLook.heroTop)

            Text(model.name)
                .font(Format.isLongTitle(model.name) ? Typeface.title3.bold() : Typeface.title2.bold())
                .foregroundStyle(DWPalette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, AlbumPageLook.playlistTitleAbove)
                .accessibilityAddTraits(.isHeader)

            if let playlist {
                Text(PlaylistRules.ownerLine(playlist))
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.top, AlbumPageLook.metaAbove)
            }

            // why there is no Edit (somebody else's, a file's, too many songs) - known once the songs are in
            if let answer = model.answer, !model.gone,
               let words = PlaylistRules.readOnlyWords(answer.playlist, songs: answer.songs.count) {
                Text(words)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AlbumPageLook.metaAbove)
            }

            if let comment = playlist?.comment, !comment.isEmpty {
                Text(comment)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AlbumPageLook.metaAbove)
            }

            // the count holds its line while the songs come, so nothing below moves as it fills
            let line = model.answer != nil && !model.gone
                ? PlaylistRules.songsLine(songs.count, seconds: PlaylistRules.total(songs)) : ""
            Text(line.isEmpty ? " " : line)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t3)
                .padding(.top, AlbumPageLook.metaAbove)
                .accessibilityHidden(line.isEmpty)

            // (slice 3) downloaded: the album's line, its own - and, all here, that it plays with no connection (a smart
            // one's, that it stays as it was); a smart one not downloaded: why there is no Download
            if let download, let words = PlaylistDownloadWords.heroLine(download, smart: smart, device: Platform.device) {
                DownloadLine(download: download, line: words)
                    .padding(.top, AlbumPageLook.chipsAbove)
                    .transition(.opacity)
            } else if !model.gone, let words = PlaylistDownloadWords.heroLine(download, smart: smart, device: Platform.device) {
                Text(words)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AlbumPageLook.metaAbove)
            }

            AlbumPlayPair(enabled: playable && !model.gone, play: play, shuffle: shuffle)
        }
        .padding(.horizontal, AlbumPageLook.heroSide)
        .frame(maxWidth: .infinity)
    }
}

/// One song of a playlist (PlaylistPage.tsx's track row): its title; its artist and album; the download slot (as an
/// album's rows: on every row where any song has a state); its time; its ••• ("More for Roads"). A tap plays the
/// playlist from it. VoiceOver reads it as one: "Roads, Portishead · Dummy, Downloaded, 5:04" - "playing" or "paused"
/// for the song the player has - with the song's download items as its actions, and Add to Queue. Swiped right, the
/// List's own leading swipe action adds the song to the queue, wherever its ••• offers Add to Queue
/// (AddToQueueSwipe.swift).
///
/// (R5, iPlaylist.dc.html's .row.tall) 60 tall at least, on the row's rule: the title and its line under it 16 in, the
/// time in the mono face, the ••• in the third colour - no cover of its own, as drawn; the song the player has is its
/// title in the accent with the playing bars before it. One VoiceOver element, the •••'s items its actions (TrackRow's).
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

    var body: some View {
        let line = PlaylistRules.songLine(song)
        HStack(spacing: 0) {
            Button(action: play) {
                // (25 Nov) beside the title alone, the length sits on its baseline: Courier Prime's line is shorter
                // than Libre Franklin's, so centred it would sit higher. Beside two lines it is centred, as drawn.
                HStack(alignment: line.isEmpty ? .firstTextBaseline : .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: AlbumPageLook.chipGap) {
                            if current {
                                Image(systemName: "waveform")
                                    .font(Typeface.symbol(.footnote).weight(.semibold))
                                    .foregroundStyle(DWPalette.acc)
                                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: playing)
                            }
                            Text(song.title ?? "")
                                .font(Typeface.body)
                                .foregroundStyle(current ? DWPalette.acc : DWPalette.text)
                                .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        }
                        if !line.isEmpty {
                            Text(line)
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.t3)
                                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        }
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                    Spacer(minLength: 8)
                    if slot {
                        stateSlot
                            .padding(.trailing, AlbumPageLook.chipGap)
                    }
                    Text(Format.trackTime(song.duration))
                        .font(Typeface.Phone.mono(.small))
                        .foregroundStyle(DWPalette.t3)
                        .padding(.trailing, AlbumPageLook.timeTrail)
                }
                .padding(.leading, AlbumPageLook.rowSide)
                .padding(.vertical, 6)
                .lookHeight(DWLook.here.tallRowHeight)
                .contentShape(Rectangle())
                .opacity(dimmed ? DWPalette.off : 1)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)

            QueueMenu(request: menu) {
                Image(systemName: "ellipsis")
                    .font(Typeface.symbol(.body).weight(.semibold))
                    .foregroundStyle(DWPalette.t3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            // the glyph's own edge 16 from the right (.row's •••): 12 of its 44 target lie beyond it
            .padding(.trailing, AlbumPageLook.moreTrail - 12)
        }
        // (R5, wave B's rule) one element: its tap plays, the •••'s items its actions
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(line))
        .accessibilityAddTraits(dimmed ? [] : .isButton)
        .accessibilityAction {
            if !dimmed { play() }
        }
        .accessibilityActions {
            ForEach(actions, id: \.self) { choice in
                Button(choice.label) { act(choice) }
            }
        }
        .addToQueueAction(menu)
        .addToPlaylistAction(menu)
        .addsToQueue(menu, in: .list)
        // (the Mac app, slice 2) the row's ••• on a right-click; nothing on the iPhone
        .macContextMenu { QueueMenuItems(request: menu) }
    }

    /// The row as VoiceOver reads it: the title, playing or paused, the line, the download state, the time.
    private func spoken(_ line: String) -> String {
        var parts = [song.title ?? ""]
        if current { parts.append(PlayingBars.label(paused: !playing)) }
        if !line.isEmpty { parts.append(line) }
        let state: String? = dimmed ? DownloadWords.notOnDevice(Platform.device) : DownloadWords.songLine(download, device: Platform.device)
        if let state { parts.append(state) }
        let time = Format.trackTime(song.duration)
        if !time.isEmpty { parts.append(time) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The one slot, as an album row's: the song's mark, or the room for one held.
    @ViewBuilder private var stateSlot: some View {
        ZStack {
            if let mark = DownloadWords.mark(download) {
                DownloadMark(mark: mark, fraction: DownloadWords.Mark.fraction(download), font: Typeface.symbol(.caption))
            } else {
                DownloadMark(mark: .downloaded, font: Typeface.symbol(.caption)).hidden()
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
            .font(Typeface.callout)
            .foregroundStyle(Palette.quiet)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}

/// "Couldn't open this playlist. <why>" and Try again - nothing in hand and the first ask failed.
struct OpenFailedNote: View {
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
struct RefreshFailedNote: View {
    let failure: any Error

    @Environment(ServerModel.self) private var server

    var body: some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, retry: false)
        ErrorNote(text: PlaylistWords.refreshFailed(line.said), detail: line.detail)
            .padding(.vertical, 4)
    }
}
