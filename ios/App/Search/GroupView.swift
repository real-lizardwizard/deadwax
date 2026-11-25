import DeadwaxCore
import SwiftUI

/// The album you don't have (Phase 5, slice 2 - phase5-search.md 3.6; the web's ReleaseGroupPage.tsx on a phone, with
/// pressings.ts' rules in Core's Pressings and GroupPage): a MusicBrainz album's page, pushed on the tab's stack from
/// Search. Top to bottom: its cover (the chosen pressing's front, else the album's - through deadwax's relay), its title,
/// its credit (a link to the library's artist when exactly one answers to its sole credited artist - question 19), the
/// meta line ("1994 · Album · not in your library", or a dashed "maybe in your library"); the pressing picker (a sheet,
/// question 17) and the chosen pressing's facts; Get the album and the store line under it (Phase 6, below); the maybe
/// said in words; then the chosen pressing's tracklist - the summary against the usual tracklist, each track with what differs marked, and
/// what it leaves out. Loading… while the pressings come, their trouble with Try again, "There are no pressings of this
/// album to get." for none.
///
/// Drawn at once from the album Search showed (`route.preview`); what it says of the library is from `/library/owned`,
/// asked again as the page shows. No description and no links out (question 20). Nothing is asked while deadwax can't be
/// reached: a list kept from earlier in the session is drawn, else the page says it loads once deadwax is back.
///
/// (Slice 3) Opened from a song (`route.song`, its recordings): its title drawn while the pressings load, the pressing
/// shown one with the song (unless one is picked - a pick then always kept, so the song never overrules it), the song's
/// tracks marked (tinted, an accent bar, and ", the song you searched for" for VoiceOver) and brought into view once, as
/// they are first drawn on the page shown (or as it shows, drawn while it wasn't), only from the top. The credit with no
/// library artist of theirs opens their MusicBrainz page.
///
/// (Phase 6, slice 2 - phase6-get-requests.md 3.4; ReleaseGroupPage.tsx's Get) Once a pressing is chosen: **Get the
/// album**, the screen's one primary button, opening the Sources sheet for that pressing (GetRelease.build - what the
/// web's Get sends); without Get albums, the web's GET_OFF in its place. Under it the store line - what the store and
/// the downloads already have of the pressing (`/download/store_state`, which searches nothing) - asked as the pressing
/// is chosen, as an album is filed (RequestsModel.filed), and as the page comes back into view (its tab current, the
/// sheet closed, the app in front), so after a Get or a cancel in Requests it says so; asked again for the same
/// pressing, the last answer stays until the new one lands, and another pressing's never stands for this one. Its
/// answer also says whose each folder is, so the meta line never disagrees with it (GroupPage `store`). While deadwax
/// can't be reached: no Get, and "Getting albums works once deadwax is back." in the line's place. A Get asked for from
/// the sheet closes it and shows Requests' root, the new row already up.
///
/// (Phase 6, slice 3 - 2.11) In the line's box: **Join this download** under a download somebody else asked for -
/// only with Get albums, as the web's page gives `onJoin` only then (without it, the box says nothing of joining) -
/// and **Add to my library** under a pressing the store holds that isn't yours, for anyone (deadwax refuses it in
/// words where it can't). After either, the store is asked again, so the line says it's yours; an Add also tells your
/// library and Search's marks, and a Join the Requests poll. The page stays where it is: only the sheet's Join hands
/// over to Requests.
struct GroupView: View {
    let route: GroupRoute

    @Environment(ServerModel.self) private var server
    @Environment(SearchModel.self) private var search
    @Environment(ArtistsModel.self) private var artists
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(RequestsModel.self) private var requests
    @Environment(GetSettingsModel.self) private var getSettings
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: GroupPageModel
    @State private var picking = false
    /// The hero's title has scrolled away: the bar shows it.
    @State private var titleInBar = false
    /// The song it was opened from has been brought into view (once).
    @State private var songShown = false
    /// (Phase 6) The store line's last answer, and the pressing it was for.
    @State private var store: StoreSaid?
    /// The Get whose Sources sheet is up.
    @State private var getting: GetRequest?
    /// One more for every Get: each sheet searches afresh.
    @State private var gets = 0
    /// A download was asked for from the sheet: Requests shows once it has gone.
    @State private var queued = false
    /// (Slice 3) One more for every Join or Add answered from the line: the store asked again.
    @State private var changed = 0

    private static let edge: CGFloat = 16

    init(route: GroupRoute) {
        self.route = route
        _model = State(initialValue: GroupPageModel(route: route))
    }

    /// The page as drawn from what is in hand (Core's GroupPage).
    private var page: GroupPage {
        GroupPage(id: route.id, answer: model.answer, preview: route.preview, index: search.ownedIndex,
                  picked: model.picked, personal: server.access.hasLibrary, editors: false,
                  fallbackTitle: route.title ?? "", song: route.song,
                  store: store.map { (said: StoreSaid) in (id: said.id, answer: said.answer) })
    }

    /// The chosen pressing as MusicBrainz sent it - nil until the pressings are in.
    private func chosen(_ page: GroupPage) -> PageRelease? {
        guard let id = page.chosenId else { return nil }
        return model.answer?.releases.first { (release: PageRelease) -> Bool in release.id == id }
    }

    /// What Get would download: the chosen pressing, built from the album's group (`getGroup`, `buildDownloadRelease`).
    private func download(_ page: GroupPage) -> GetRelease? {
        guard let chosen = chosen(page) else { return nil }
        let group = GetRelease.group(id: route.id, preview: route.preview, releases: model.answer?.releases ?? [],
                                     chosen: chosen)
        return GetRelease.build(group: group, release: chosen)
    }

    var body: some View {
        let page = self.page
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    hero(page)
                        .onAppear { titleInBar = false }
                        .onDisappear { titleInBar = true }
                    actions(page)
                    below(page)
                }
                .padding(.horizontal, Self.edge)
                .padding(.bottom, 24)
            }
            .onChange(of: page.tracks.first(where: \.song)?.key, initial: true) { _, key in
                showSong(key, proxy)
            }
            // drawn while the page wasn't shown (another tab, Now Playing over it): brought into view as it shows
            .onAppear { showSong(page.tracks.first(where: \.song)?.key, proxy) }
            .onChange(of: navigation.tab) { _, _ in showSong(page.tracks.first(where: \.song)?.key, proxy) }
            .onChange(of: navigation.nowPlayingShown) { _, _ in showSong(page.tracks.first(where: \.song)?.key, proxy) }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(page.title)
                    .font(Typeface.headline)
                    .lineLimit(1)
                    .opacity(titleInBar ? 1 : 0)
                    .accessibilityHidden(!titleInBar)
            }
        }
        .appSheet(isPresented: $picking) {
            if let view = page.view {
                PressingPickerSheet(view: view) { (id: String) -> Void in
                    // the default chosen again is the default: nothing kept of it - but on a page opened from a song a
                    // pick is always kept, so the song's own choice never comes back over it
                    model.picked = route.song.isEmpty && id == view.defaultId ? nil : id
                }
                .macSheet()
            }
        }
        // (slice 3's review) the sheet let go - swiped away, or closed: its search goes as the dismissal begins
        .appSheet(item: Binding(get: { getting }, set: { (next: GetRequest?) in
            if next == nil { getting?.search.close() }
            getting = next
        }), onDismiss: {
            // a download asked for: Requests at its root once the sheet has gone (App.tsx `gotten`)
            guard queued else { return }
            queued = false
            navigation.showRequestsRoot()
        }) { (request: GetRequest) in
            SourcesSheet(request: request) {
                // only while the sheet still shows this Get: a Join answering after it closed opens nothing
                guard getting?.id == request.id else { return }
                queued = true
                getting = nil
            }
            .macSheet()
        }
        .task(id: server.person) {
            search.refreshOwned()
            await model.load(client: server.client, online: reachability.online)
        }
        // the store line asked as the pressing is chosen, as an album is filed, and as the page shows again
        .task(id: StoreAsk(pressing: page.chosenId, filed: requests.filed, changed: changed, shown: storeShown,
                           online: reachability.online, person: server.person)) {
            await askStore(page)
        }
        // the quality floor's word, for somebody else's download in the line (useGetSettings(shown))
        .onChange(of: storeShown, initial: true) { _, shown in
            if shown { getSettings.ask() }
        }
        .onChange(of: reachability.online) { _, online in
            // back: what couldn't be asked is asked now
            guard online, model.answer == nil else { return }
            reload()
        }
    }

    private func reload() {
        Task { await model.load(client: server.client, online: reachability.online) }
    }

    /// The page is the one shown: the top of its tab's stack, the tab shown, Now Playing not over it.
    private var isShown: Bool {
        navigation.shownStack.last == .group(route) && !navigation.nowPlayingShown
    }

    /// (Phase 6) The store line may be asked: the page shown, the Sources sheet closed, the app in front.
    private var storeShown: Bool {
        isShown && getting == nil && scenePhase == .active
    }

    /// What the store line is asked again on.
    private struct StoreAsk: Equatable {
        let pressing: String?
        let filed: Int
        let changed: Int
        let shown: Bool
        let online: Bool
        let person: Int
    }

    /// The store asked what it already has of the chosen pressing - no search. A newer ask lets this one go; one that
    /// can't be made says nothing (Get asks again, and the server refuses a second copy).
    private func askStore(_ page: GroupPage) async {
        guard storeShown, reachability.online, let client = server.client, let pressing = page.chosenId,
              let release = download(page) else { return }
        guard let answer = try? await client.storeState(release), !Task.isCancelled else { return }
        store = StoreSaid(id: pressing, answer: answer)
    }

    /// Get the album: the Sources sheet for the chosen pressing.
    private func get(_ page: GroupPage) {
        guard let release = download(page), let pressing = chosen(page) else { return }
        let title = Pressings.header(model.answer?.releases ?? [], chosen: pressing, preview: route.preview).title
        gets += 1
        getting = GetRequest(id: gets, release: release,
                             subtitle: SourcesWords.subtitle(title: title, pressing: Pressings.label(pressing)),
                             search: SourcesSearch())
    }

    /// The song brought into view as its tracks are first drawn - once for the page, counted only once the page is the
    /// one shown (its tracks drawn while it wasn't are brought into view as it shows, the web's `shown`), and only from
    /// the top: a page scrolled meanwhile is left where it is. The least scroll that shows it (`nearest`).
    private func showSong(_ key: String?, _ proxy: ScrollViewProxy) {
        guard let key, !songShown, isShown else { return }
        songShown = true
        Task { @MainActor in
            // a frame for the tracklist to be laid out, and for the hero's own onAppear coming back to the page
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !titleInBar else { return }
            withAnimation { proxy.scrollTo(key, anchor: nil) }
        }
    }

    // MARK: the hero

    private func hero(_ page: GroupPage) -> some View {
        VStack(spacing: 0) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: page.chosenId, group: route.id),
                         size: ArchiveCoverSize.hero)
                .frame(maxWidth: AlbumHero.coverSide)
                .clipShape(Corners.artShape)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 8)

            Text(page.title)
                .font(page.title.count > 60 ? Typeface.title3.bold() : Typeface.title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            if !page.artist.isEmpty {
                artistLine(page)
                    .padding(.top, 2)
            }

            metaLine(page)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    /// The credit: the library's artist's page when exactly one answers to the album's sole credited artist, else (slice
    /// 3) that artist's MusicBrainz page - else words.
    @ViewBuilder private func artistLine(_ page: GroupPage) -> some View {
        if let artist = libraryArtist(page) {
            creditLink(page.artist) { navigation.open(.artist(ArtistRoute(artist))) }
        } else if let sole = soleCredit(page) {
            creditLink(page.artist) { navigation.open(.mbArtist(MBArtistRoute(mbid: sole.mbid, name: sole.name))) }
        } else {
            Text(page.artist)
                .font(Typeface.title3)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func creditLink(_ name: String, _ open: @escaping () -> Void) -> some View {
        Button(action: open) {
            Text(name)
                .font(Typeface.title3)
                .foregroundStyle(Palette.accent)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .buttonStyle(.plain)
    }

    /// The album's sole credited artist (the group's credit, else the chosen pressing's) - ReleaseGroupPage's
    /// `artistLink`: nil unless ONE artist MusicBrainz knows is credited.
    private func soleCredit(_ page: GroupPage) -> (mbid: String, name: String)? {
        let releases = model.answer?.releases ?? []
        let credited = route.preview ?? releases.first(where: { (release: PageRelease) -> Bool in release.releaseGroup != nil })?.releaseGroup
        let chosen = releases.first { (release: PageRelease) -> Bool in release.id == page.chosenId }
        let credit = (credited?.artistCredit ?? []).isEmpty ? chosen?.artistCredit : credited?.artistCredit
        return Credits.sole(credit)
    }

    /// The library's artist for the album's sole credit - their own page before a MusicBrainz one.
    private func libraryArtist(_ page: GroupPage) -> Artist? {
        guard let sole = soleCredit(page), let list = artists.list else { return nil }
        return SearchAlbums.libraryArtist(list, mbid: sole.mbid, index: search.ownedIndex, name: sole.name)
    }

    /// "1994 · Album · not in your library" - or its first parts and a dashed "maybe in your library". Its line held
    /// while it is empty, so nothing below moves as it fills.
    @ViewBuilder private func metaLine(_ page: GroupPage) -> some View {
        if page.maybe.isEmpty {
            Text(page.meta.isEmpty ? " " : page.meta)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .accessibilityHidden(page.meta.isEmpty)
        } else {
            HStack(spacing: 6) {
                if !page.meta.isEmpty {
                    Text(page.meta + " \u{00B7}")
                }
                Text(page.maybe)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(Corners.controlShape.strokeBorder(Palette.quiet,
                                                               style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .font(Typeface.footnote)
            .foregroundStyle(Palette.quiet)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: the pressing, and Get's place

    /// Where the album page has Play and Shuffle: the pressing picker and its facts, then where Phase 6's Get will go
    /// (nothing, in slice 2), then the maybe in words.
    @ViewBuilder private func actions(_ page: GroupPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let view = page.view {
                Button {
                    picking = true
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Pressings.picker)
                                .font(Typeface.caption)
                                .foregroundStyle(Palette.quiet)
                            Text(view.chosen?.label ?? "")
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(Typeface.symbol(.footnote).weight(.semibold))
                            .foregroundStyle(Palette.quiet)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(Corners.controlShape.fill(Color(white: 1, opacity: 0.06)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(Pressings.picker), \(view.chosen?.label ?? "")")
                .accessibilityHint(view.chosen?.facts ?? "")
                // the chosen pressing's facts, two lines held whatever it says, so another chosen moves nothing under it
                Text(page.facts.isEmpty ? " " : page.facts)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(2, reservesSpace: true)
                    .accessibilityHidden(true)
            }
            getAndStore(page)
            if !page.maybeNote.isEmpty {
                Text(page.maybeNote)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 18)
    }

    /// (Phase 6) Get the album and the store line under it - where a line landing late moves nothing a finger is reaching
    /// for. Nothing before a pressing is chosen: there is nothing it could get.
    @ViewBuilder private func getAndStore(_ page: GroupPage) -> some View {
        if download(page) != nil {
            let allowed = server.access.can(.request)
            if !allowed {
                Text(RequestWords.getOff)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            } else if reachability.online {
                Button {
                    get(page)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                            .font(Typeface.symbol(.body).weight(.semibold))
                            .accessibilityHidden(true)
                        Text(SourcesWords.getTheAlbum)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryFace(large: true))
                .padding(.top, 4)
            }
            if reachability.online {
                let status = StoreLine.drawn(known(page), floor: getSettings.settings?.floor, joins: allowed)
                StoreLineView(status: status, notes: known(page).map { StoreLine.notes($0) } ?? [],
                              onJoin: allowed ? { (jobId: Int) in try await join(jobId) } : nil,
                              onAdd: { try await add(page) })
                    .onChange(of: status?.title) { _, title in
                        // what the line now says, for VoiceOver - only on the page shown (the web's aria-live)
                        if let title, isShown { Notice.announce(title) }
                    }
            } else if allowed {
                ShelfNote(StoreLine.offline)
            }
        }
    }

    /// (Slice 3) Join this download, from the line: once deadwax has it (and the Requests poll told), the store asked
    /// again - the line says it's yours. (Slice 3's review) An answer that never came asks the store again too: a join
    /// that landed shows as yours, and the button goes with it.
    private func join(_ jobId: Int) async throws {
        do {
            try await requests.join(jobId)
        } catch {
            if RequestOverlays.unanswered(error) { changed += 1 }
            throw error
        }
        changed += 1
    }

    /// (Slice 3) Add to my library, from the line: the chosen pressing, as a Get would download it. Once deadwax has it,
    /// your library and Search's marks are told, and the store asked again - the line says "Already in your library".
    /// (Slice 3's review) An answer that never came does the same: an Add that landed shows as yours.
    private func add(_ page: GroupPage) async throws {
        guard let release = download(page) else { throw URLError(.badURL) }
        do {
            try await library.add(release)
        } catch {
            if RequestOverlays.unanswered(error) {
                search.refreshOwned()
                changed += 1
            }
            throw error
        }
        search.refreshOwned()
        changed += 1
    }

    /// The store line's answer for the pressing shown - another pressing's never stands for it.
    private func known(_ page: GroupPage) -> StoreStateAnswer? {
        guard let said = store, let id = page.chosenId, said.id == id else { return nil }
        return said.answer
    }

    // MARK: the tracklist

    @ViewBuilder private func below(_ page: GroupPage) -> some View {
        if let trouble = model.trouble {
            troubleNote(trouble)
        } else if model.answer == nil {
            if reachability.online {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(Pressings.loading)
                        .foregroundStyle(Palette.quiet)
                }
                .accessibilityElement(children: .combine)
                .padding(.top, 18)
            } else {
                ShelfNote(Pressings.offline)
                    .padding(.top, 10)
            }
        } else if (model.answer?.releases ?? []).isEmpty {
            ShelfNote(Pressings.none)
                .padding(.top, 10)
        } else {
            tracklist(page)
        }
    }

    private func troubleNote(_ trouble: GroupPageModel.Trouble) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch trouble {
            case .unavailable:
                ErrorNote(text: Pressings.trouble)
            case .failed(let error):
                ErrorNote(error, gone: Pressings.gone, retry: true)
            case .notAnAlbum:
                ErrorNote(text: Pressings.notAnAlbum)
            }
            if trouble.asksAgain {
                Button(Pressings.tryAgain) {
                    if reachability.online { reload() } else { reachability.tryNow() }
                }
                .disabled(reachability.probing)
            }
        }
        .padding(.top, 18)
    }

    @ViewBuilder private func tracklist(_ page: GroupPage) -> some View {
        Text(Pressings.tracklist)
            .font(Typeface.title3.weight(.semibold))
            .padding(.top, 22)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
        if let summary = page.summary, !summary.text.isEmpty {
            Text(summary.text)
                .font(Typeface.footnote)
                .foregroundStyle(summary.differs ? Palette.amber : Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
        }
        ForEach(page.tracks) { (track: PressingTrack) in
            if let heading = track.heading {
                Text(heading)
                    .font(Typeface.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.quiet)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            PressedTrackRow(number: track.number, title: track.title, length: track.length, mark: track.mark,
                            song: track.song)
                .id(track.key)
        }
        if !page.missing.isEmpty {
            Text(Pressings.notOnThisPressing)
                .font(Typeface.headline)
                .padding(.top, 20)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(page.missing.indices, id: \.self) { (at: Int) in
                PressedTrackRow(number: "\u{2013}", title: page.missing[at].title, length: page.missing[at].length,
                                mark: nil, left: true)
            }
        }
    }
}

/// (Phase 6) The store line's answer, and the pressing it was asked for.
private struct StoreSaid: Equatable {
    let id: String
    let answer: StoreStateAnswer
}

/// One track of a pressing's tracklist (ReleaseGroupPage.tsx's `app-rg-track`): its number, its title with what marks
/// it under it ("Only on this pressing"), the mark's chip ("Bonus"), its length. Read as one. The song the album was
/// opened from (slice 3, `.is-song`): tinted, an accent bar at its edge, its title in the accent - and VoiceOver hears
/// ", the song you searched for" after it.
private struct PressedTrackRow: View {
    let number: String
    let title: String
    let length: String
    let mark: PressingTrack.Mark?
    var left = false
    var song = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(Typeface.subheadline)
                    .foregroundStyle(Palette.quiet)
                    .frame(minWidth: 22, alignment: .trailing)
                    .accessibilityHidden(left)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(left ? Palette.quiet : song ? Palette.accent : .primary)
                        .fontWeight(song ? .semibold : nil)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                        .accessibilityLabel(song ? title + SongSearch.songWords : title)
                    if let mark {
                        Text(mark.note)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                }
                Spacer(minLength: 8)
                if let mark {
                    Text(mark.chip)
                        .font(Typeface.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Palette.amber)
                        .background(Corners.controlShape.fill(Palette.amberFill))
                        .overlay(Corners.controlShape.strokeBorder(Palette.amberEdge))
                }
                Text(length)
                    .font(Typeface.subheadline)
                    .foregroundStyle(Palette.quiet)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, song ? Self.bleed : 0)
            .background(alignment: .leading) {
                if song {
                    ZStack(alignment: .leading) {
                        Corners.cardShape
                            .fill(Palette.pressed)
                        Rectangle()
                            .fill(Palette.accent)
                            .frame(width: Self.bar)
                    }
                    .clipShape(Corners.cardShape)
                }
            }
            .padding(.horizontal, song ? -Self.bleed : 0)
            Divider()
        }
        .accessibilityElement(children: .combine)
    }

    /// How far the song's tint reaches past the row's text, and its accent bar's width (app.css `--app-rg-mark-bleed`,
    /// `--app-song-bar`).
    private static let bleed: CGFloat = 8
    private static let bar: CGFloat = 3
}
