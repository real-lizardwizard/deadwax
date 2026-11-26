import DeadwaxCore
import SwiftUI

/// The album you don't have (Phase 5, slice 2 - phase5-search.md 3.6; the web's ReleaseGroupPage.tsx on a phone, with
/// pressings.ts' rules in Core's Pressings and GroupPage): a MusicBrainz album's page, pushed on the tab's stack from
/// Search. Top to bottom: its cover (the chosen pressing's front, else the album's - through deadwax's relay), its title,
/// its credit (a link to the library's artist when exactly one answers to its sole credited artist - question 19), the
/// meta line ("1994 · Album · not in your library", or a dashed "maybe in your library"); Get the album, the pressing
/// picker (a sheet, question 17) and the chosen pressing's facts; the store line (Phase 6, below); the maybe said in
/// words; then the chosen pressing's tracklist - the summary against the usual tracklist, each track with what differs
/// marked, and what it leaves out. Loading… while the pressings come, their trouble with Try again, "There are no
/// pressings of this album to get." for none.
///
/// Drawn at once from the album Search showed (`route.preview`); what it says of the library is from `/library/owned`,
/// asked again as the page shows. No description and no links out (question 20). Nothing is asked while deadwax can't be
/// reached: a list kept from earlier in the session is drawn, else the page says it loads once deadwax is back.
///
/// (Slice 3) Opened from a song (`route.song`, its recordings): its title drawn while the pressings load, the pressing
/// shown one with the song (unless one is picked - a pick then always kept, so the song never overrules it), the song's
/// tracks marked (an accent bar, its title in the accent, and ", the song you searched for" for VoiceOver) and brought
/// into view once, as they are first drawn on the page shown (or as it shows, drawn while it wasn't), only from the top.
/// The credit with no library artist of theirs opens their MusicBrainz page.
///
/// (Phase 6, slice 2 - phase6-get-requests.md 3.4; ReleaseGroupPage.tsx's Get) Once a pressing is chosen: **Get the
/// album**, the screen's one primary button, opening Choose a source for that pressing (GetRelease.build - what the
/// web's Get sends); without Get albums, the web's GET_OFF in its place. The store line - what the store and the
/// downloads already have of the pressing (`/download/store_state`, which searches nothing) - asked as the pressing is
/// chosen, as an album is filed (RequestsModel.filed), and as the page comes back into view (its tab current, the sheet
/// closed, the app in front), so after a Get or a cancel in Requests it says so; asked again for the same pressing, the
/// last answer stays until the new one lands, and another pressing's never stands for this one. Its answer also says
/// whose each folder is, so the meta line never disagrees with it (GroupPage `store`). While deadwax can't be reached:
/// no Get, and "Getting albums works once deadwax is back." in the line's place. A Get asked for from Choose a source
/// closes it and shows Requests' root, the new row already up.
///
/// (Phase 6, slice 3 - 2.11) In the line's box: **Join this download** under a download somebody else asked for -
/// only with Get albums, as the web's page gives `onJoin` only then (without it, the box says nothing of joining) -
/// and **Add to my library** under a pressing the store holds that isn't yours, for anyone (deadwax refuses it in
/// words where it can't). After either, the store is asked again, so the line says it's yours; an Add also tells your
/// library and Search's marks, and a Join the Requests poll. The page stays where it is: only Choose a source's Join
/// hands over to Requests.
///
/// (The redesign, slice R7 - notes/ios.md "The redesign, slice R7: Search, Get and Sources (2026-11-25)")
/// - On the phone, iGet.dc.html: flat and square on the page's black - the cover 184, the title, the artist in the
///   accent, the meta line; **Get the album** the purple button, the width of the page; the pressing a flat row of
///   its own (Pressing, its label, the pop-up's caret) opening today's picker; the facts line in the readout face with
///   how many pressings there are; the store line; the Tracklist heading with its songs and minutes, the tracks on thin
///   lines. Choose a source is the sheet, as before.
/// - On the Mac (`desk`, from MacSearch.page(for:)), MacGetPage draws the page in its place, handed this page's own
///   model and actions (GroupDesk): every load, ask, pick and announcement stays this page's. Its Get the album opens
///   the side panel's Sources tab beside the page (AppNavigation.getSources), never the sheet; the tab closes when the
///   page leaves the front.
struct GroupView<Desk: View>: View {
    let route: GroupRoute
    private let desk: ((GroupDesk) -> Desk)?

    @Environment(ServerModel.self) private var server
    @Environment(SearchModel.self) private var search
    @Environment(ArtistsModel.self) private var artists
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(RequestsModel.self) private var requests
    @Environment(GetSettingsModel.self) private var getSettings
    @Environment(LibraryModel.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    /// (R7's review) The facts line's lines: two held, and as many as it takes at the accessibility sizes.
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model: GroupPageModel
    @State private var picking = false
    /// The hero's title has scrolled away: the bar shows it.
    @State private var titleInBar = false
    /// The song it was opened from has been brought into view (once).
    @State private var songShown = false
    /// (Phase 6) The store line's last answer, and the pressing it was for.
    @State private var store: StoreSaid?
    /// The Get whose Sources sheet is up (the phone's).
    @State private var getting: GetRequest?
    /// A download was asked for from the sheet: Requests shows once it has gone.
    @State private var queued = false
    /// (Slice 3) One more for every Join or Add answered from the line: the store asked again.
    @State private var changed = 0

    /// (R7) The Mac's: the page drawn by `desk` (MacGetPage).
    init(route: GroupRoute, desk: @escaping (GroupDesk) -> Desk) {
        self.route = route
        self.desk = desk
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
        Group {
            if let desk, Platform.mac {
                desk(GroupDesk(model: model, page: page, route: route, pressings: model.answer?.releases.count ?? 0,
                               canGet: download(page) != nil, allowed: server.access.can(.request),
                               online: reachability.online, compared: page.view?.base != nil,
                               get: { get(page) }, pick: { picking = true }, artist: artistOpen(page),
                               getOff: getOff(page), storeLine: storeLine(page), reload: { reload() }))
            } else {
                phone(page)
            }
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
        // (slice 3's review) the sheet let go - swiped away, or closed: its search goes as the dismissal begins. (R7) The
        // phone's alone: the Mac's Get is the side panel's Sources tab, and never sets `getting`
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
        // (R7's review) another pressing chosen while the Mac's dock has this page's Get: that Get ends (its cards were
        // for the pressing it asked), never left to download one the page no longer shows
        .onChange(of: page.chosenId) { _, chosen in
            navigation.pressingChosen(chosen, on: route)
        }
        // the quality floor's word, for somebody else's download in the line (useGetSettings(shown))
        .onChange(of: storeShown, initial: true) { _, shown in
            if shown { getSettings.ask() }
        }
        .onChange(of: storeStatus(page)?.title) { _, title in
            // what the line now says, for VoiceOver - only on the page shown (the web's aria-live)
            if let title, isShown { Notice.announce(title) }
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

    /// Get the album: Choose a source for the chosen pressing - the sheet on the phone; (R7) on the Mac the side
    /// panel's Sources tab beside this page, which closes when the page leaves the front.
    private func get(_ page: GroupPage) {
        guard let release = download(page), let pressing = chosen(page) else { return }
        let title = Pressings.header(model.answer?.releases ?? [], chosen: pressing, preview: route.preview).title
        // (R7's review) a number no Get has had in this run of the app: another album's page starts no count again, so
        // the dock's tab (keyed on it) is always a page afresh for a new Get
        let request = GetRequest(id: GetRequest.numbered(), release: release,
                                 subtitle: SourcesWords.subtitle(title: title, pressing: Pressings.label(pressing)),
                                 search: SourcesSearch())
        if Platform.mac {
            navigation.getSources(request, from: route)
        } else {
            getting = request
        }
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

    // MARK: the credit, and the store line - both devices'

    /// The credit's link: the library's artist's page when exactly one answers to the album's sole credited artist,
    /// else (slice 3) that artist's MusicBrainz page - else nil, the credit words alone.
    private func artistOpen(_ page: GroupPage) -> (() -> Void)? {
        if let artist = libraryArtist(page) {
            return { navigation.open(.artist(ArtistRoute(artist))) }
        }
        if let sole = soleCredit(page) {
            return { navigation.open(.mbArtist(MBArtistRoute(mbid: sole.mbid, name: sole.name))) }
        }
        return nil
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

    /// What the store line says for the pressing shown - nil before there is a pressing to get, or anything to say.
    private func storeStatus(_ page: GroupPage) -> StoreStatus? {
        guard download(page) != nil else { return nil }
        return StoreLine.drawn(known(page), floor: getSettings.settings?.floor, joins: server.access.can(.request))
    }

    /// Without Get albums, the web's GET_OFF in Get's place - once a pressing is chosen, online or not.
    private func getOff(_ page: GroupPage) -> Bool {
        download(page) != nil && !server.access.can(.request)
    }

    /// (Phase 6) The store line under Get the album and the pressing - where a line landing late moves nothing a finger
    /// is reaching for - or, while deadwax can't be reached, why there is no Get. Nothing before a pressing is chosen:
    /// there is nothing it could get.
    private func storeLine(_ page: GroupPage) -> GroupStoreLine {
        guard download(page) != nil else { return .nothing }
        let allowed = server.access.can(.request)
        if reachability.online {
            let status = StoreLine.drawn(known(page), floor: getSettings.settings?.floor, joins: allowed)
            return .line(StoreLineView(status: status, notes: known(page).map { StoreLine.notes($0) } ?? [],
                                       onJoin: allowed ? { (jobId: Int) in try await join(jobId) } : nil,
                                       onAdd: { try await add(page) }))
        }
        return allowed ? .offline : .nothing
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

    // MARK: the phone's page (iGet.dc.html)

    private func phone(_ page: GroupPage) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    hero(page)
                        .onAppear { titleInBar = false }
                        .onDisappear { titleInBar = true }
                    actions(page)
                    below(page)
                }
                .padding(.bottom, GroupPageLook.bottom)
            }
            .onChange(of: page.tracks.first(where: \.song)?.key, initial: true) { _, key in
                showSong(key, proxy)
            }
            // drawn while the page wasn't shown (another tab, Now Playing over it): brought into view as it shows
            .onAppear { showSong(page.tracks.first(where: \.song)?.key, proxy) }
            .onChange(of: navigation.tab) { _, _ in showSong(page.tracks.first(where: \.song)?.key, proxy) }
            .onChange(of: navigation.nowPlayingShown) { _, _ in showSong(page.tracks.first(where: \.song)?.key, proxy) }
        }
        // (R7) the page's own black (`.dw.ph`), as an album's page is
        .background(DWPalette.page)
    }

    private func hero(_ page: GroupPage) -> some View {
        VStack(spacing: 0) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: page.chosenId, group: route.id),
                         size: ArchiveCoverSize.hero)
                .frame(maxWidth: GroupPageLook.cover)
                .clipShape(Rectangle())
                .padding(.top, GroupPageLook.heroTop)

            Text(page.title)
                .font(page.title.count > 60 ? Typeface.title3.bold() : Typeface.title2.bold())
                .foregroundStyle(DWPalette.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, GroupPageLook.titleAbove)
                .accessibilityAddTraits(.isHeader)

            if !page.artist.isEmpty {
                artistLine(page)
                    .padding(.top, GroupPageLook.artistAbove)
            }

            metaLine(page)
                .padding(.top, GroupPageLook.metaAbove)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, GroupPageLook.side)
    }

    /// The credit: a link in the accent to the library's artist, or their MusicBrainz page - else words.
    @ViewBuilder private func artistLine(_ page: GroupPage) -> some View {
        if let open = artistOpen(page) {
            Button(action: open) {
                Text(page.artist)
                    .font(Typeface.title3)
                    .foregroundStyle(DWPalette.acc)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .buttonStyle(.plain)
        } else {
            Text(page.artist)
                .font(Typeface.title3)
                .foregroundStyle(DWPalette.t2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    /// "1994 · Album · not in your library" - or its first parts and a dashed "maybe in your library". Its line held
    /// while it is empty, so nothing below moves as it fills.
    @ViewBuilder private func metaLine(_ page: GroupPage) -> some View {
        if page.maybe.isEmpty {
            Text(page.meta.isEmpty ? " " : page.meta)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
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
                    // a mark, not a face: the maybe's dashed edge, square
                    .overlay(Rectangle().strokeBorder(DWPalette.t2, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .font(Typeface.Phone.text(.small))
            .foregroundStyle(DWPalette.t2)
            .accessibilityElement(children: .combine)
        }
    }

    /// Get the album, then the pressing's row, then its facts in the readout face; the store line and the maybe in
    /// words under them.
    @ViewBuilder private func actions(_ page: GroupPage) -> some View {
        VStack(alignment: .leading, spacing: GroupPageLook.actionsGap) {
            if download(page) != nil, server.access.can(.request), reachability.online {
                Button {
                    get(page)
                } label: {
                    Text(SourcesWords.getTheAlbum)
                }
                .buttonStyle(DWButtonStyle(kind: .pri, size: .large, fills: true))
            }
            if let view = page.view {
                pressingRow(view, facts: factsLine(page))
            }
        }
        .padding(.top, GroupPageLook.actionsAbove)
        .padding(.horizontal, GroupPageLook.side)
        if page.view != nil {
            // the chosen pressing's facts and how many there are, two lines held whatever it says, so another chosen
            // moves nothing under it - (R7's review) and at the accessibility sizes as many as it takes, two still held
            let facts = factsLine(page)
            Text(facts.isEmpty ? " " : facts)
                .font(Typeface.Phone.mono(.extraSmall))
                .foregroundStyle(DWPalette.t3)
                .multilineTextAlignment(.center)
                .modifier(FactsLines(lifted: typeSize.isAccessibilitySize))
                .frame(maxWidth: .infinity)
                .padding(.top, GroupPageLook.factsAbove)
                .padding(.bottom, GroupPageLook.factsBelow)
                .padding(.horizontal, GroupPageLook.side)
                .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: GroupPageLook.actionsGap) {
            if getOff(page) {
                quiet(RequestWords.getOff)
            }
            switch storeLine(page) {
            case .line(let line):
                line
            case .offline:
                ShelfNote(StoreLine.offline)
            case .nothing:
                EmptyView()
            }
            if !page.maybeNote.isEmpty {
                quiet(page.maybeNote)
            }
        }
        .padding(.horizontal, GroupPageLook.side)
    }

    /// The chosen pressing's facts and how many pressings there are (GetPageWords.factsLine): the line under the pressing,
    /// and its row's hint for VoiceOver.
    private func factsLine(_ page: GroupPage) -> String {
        GetPageWords.factsLine(page.facts, pressings: model.answer?.releases.count ?? 0)
    }

    /// The pressing's row (iGet's `.btn` 44 tall, flat): Pressing in the second colour, the chosen one's label and the
    /// pop-up's caret in the accent - (R7's review) a flat button's words (dw.ph's `.btn` colour) - today's picker as it
    /// opens. Its hint is the facts line, the pressings' count with it (the line itself is hidden from VoiceOver).
    private func pressingRow(_ view: PressingsView, facts: String) -> some View {
        Button {
            picking = true
        } label: {
            HStack(spacing: GroupPageLook.pressingGap) {
                Text(Pressings.picker)
                    .foregroundStyle(DWPalette.t2)
                Text(view.chosen?.label ?? "")
                    .foregroundStyle(DWPalette.acc)
                    .lineLimit(1)
                Spacer(minLength: GroupPageLook.pressingGap)
                DWCaret(colour: DWPalette.acc)
            }
            .font(Typeface.Look.text(.button))
            .lookHeight(GroupPageLook.pressing)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Pressings.picker), \(view.chosen?.label ?? "")")
        .accessibilityHint(facts)
        .accessibilityAddTraits(.isButton)
    }

    private func quiet(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Phone.text(.small))
            .foregroundStyle(DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: the tracklist

    @ViewBuilder private func below(_ page: GroupPage) -> some View {
        if let trouble = model.trouble {
            GroupTrouble(trouble: trouble, reload: { reload() })
                .padding(.top, GroupPageLook.noteAbove)
                .padding(.horizontal, GroupPageLook.side)
        } else if model.answer == nil {
            Group {
                if reachability.online {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(Pressings.loading)
                            .foregroundStyle(DWPalette.t2)
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.top, GroupPageLook.noteAbove)
                } else {
                    ShelfNote(Pressings.offline)
                }
            }
            .padding(.horizontal, GroupPageLook.side)
        } else if (model.answer?.releases ?? []).isEmpty {
            ShelfNote(Pressings.none)
                .padding(.horizontal, GroupPageLook.side)
        } else {
            tracklist(page)
        }
    }

    @ViewBuilder private func tracklist(_ page: GroupPage) -> some View {
        heading(Pressings.tracklist, count: GetPageWords.songsLine(page.tracks))
        if let summary = page.summary, !summary.text.isEmpty {
            Text(summary.text)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(summary.differs ? DWPalette.amberText : DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, GroupPageLook.side)
                .padding(.vertical, GroupPageLook.summaryRoom)
        }
        ForEach(page.tracks) { (track: PressingTrack) in
            if let heading = track.heading {
                DiscHeadingRow(heading: heading)
            }
            PressedTrackRow(number: track.number, title: track.title, length: track.length, mark: track.mark,
                            song: track.song)
                .id(track.key)
        }
        if !page.missing.isEmpty {
            heading(Pressings.notOnThisPressing, count: "")
            ForEach(page.missing.indices, id: \.self) { (at: Int) in
                PressedTrackRow(number: "\u{2013}", title: page.missing[at].title, length: page.missing[at].length,
                                mark: nil, left: true)
            }
        }
    }

    /// A heading's row (dw.ph's `.row.grp`): its words at the foot of a 38 row, in the heading colour, and the count in
    /// the readout face at its end.
    private func heading(_ words: String, count: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(words)
                .font(Typeface.subheadline.weight(.semibold))
                .foregroundStyle(DWPalette.head)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if !count.isEmpty {
                Text(count)
                    .font(Typeface.Phone.mono(.extraSmall))
                    .foregroundStyle(DWPalette.t3)
            }
        }
        .padding(.horizontal, GroupPageLook.side)
        .padding(.bottom, GroupPageLook.headingFoot)
        .lookHeight(DWLook.here.groupRowHeight)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .combine)
    }
}

extension GroupView where Desk == EmptyView {
    /// The iPhone's page (and every one but the Mac's own): no desk.
    init(route: GroupRoute) {
        self.route = route
        desk = nil
        _model = State(initialValue: GroupPageModel(route: route))
    }
}

/// (R7) What the Mac's Get page (MacGetPage) is handed by GroupView: the page's own model and its actions - so every
/// load, ask, pick and announcement stays GroupView's, and the Mac draws.
struct GroupDesk {
    let model: GroupPageModel
    let page: GroupPage
    let route: GroupRoute
    /// How many pressings the album has - the toolbar's chip.
    let pressings: Int
    /// A pressing is chosen: Get the album has something to get.
    let canGet: Bool
    /// Get albums: without it, GET_OFF in Get's place.
    let allowed: Bool
    let online: Bool
    /// There is a usual tracklist to say each track against.
    let compared: Bool
    /// Get the album - the side panel's Sources tab; Pressing ▾ - today's picker.
    let get: () -> Void
    let pick: () -> Void
    /// The credit's page - nil for words alone.
    let artist: (() -> Void)?
    /// Without Get albums: GET_OFF in Get's place.
    let getOff: Bool
    /// The store line, or why there is none.
    let storeLine: GroupStoreLine
    /// Try again: the pressings asked again.
    let reload: () -> Void
}

/// The store line as the page stands: the line, "Getting albums works once deadwax is back.", or nothing before a
/// pressing is chosen.
enum GroupStoreLine {
    case line(StoreLineView)
    case offline
    case nothing
}

/// The pressings' trouble in a listener's words, with Try again where asking again can help - both devices'.
struct GroupTrouble: View {
    let trouble: GroupPageModel.Trouble
    let reload: () -> Void

    @Environment(Reachability.self) private var reachability

    var body: some View {
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
                .buttonStyle(DWButtonStyle())
                .disabled(reachability.probing)
            }
        }
    }
}

/// (R7) iGet.dc.html's own numbers, each where the drawing gives it.
enum GroupPageLook {
    /// The hero: the cover 184, 6 under the bar; the title 14 under it, the artist 2, the meta line 6; 16 in.
    static let cover: CGFloat = 184             // drawn: iGet .cover width
    static let heroTop: CGFloat = 6             // drawn: iGet hero padding-top
    static let side: CGFloat = 16               // drawn: iGet hero padding-left
    static let titleAbove: CGFloat = 14         // drawn: iGet title margin-top
    static let artistAbove: CGFloat = 2         // drawn: iGet artist margin-top
    static let metaAbove: CGFloat = 6           // drawn: iGet meta margin-top
    /// Get the album and the pressing: 14 under the hero, 10 apart; the pressing's row 44, its words 8 apart.
    static let actionsAbove: CGFloat = 14       // drawn: iGet actions padding-top
    static let actionsGap: CGFloat = 10         // drawn: iGet actions gap
    static let pressing: Double = 44            // drawn: iGet pressing .btn height
    static let pressingGap: CGFloat = 8         // drawn: iGet .btn gap (dw.css .btn gap 8px)
    /// The facts line: 8 above, 4 below.
    static let factsAbove: CGFloat = 8          // drawn: iGet facts padding-top
    static let factsBelow: CGFloat = 4          // drawn: iGet facts padding-bottom
    /// A heading's words 6 above its foot (dw.ph's .row.grp padding-bottom); the summary's room; a note's.
    static let headingFoot: CGFloat = 6         // drawn: iGet .row.grp padding-bottom
    static let summaryRoom: CGFloat = 6         // own: the summary line's room above and below
    static let noteAbove: CGFloat = 18          // own: a note under the actions, as before R7
    static let bottom: CGFloat = 24             // own: the page's foot, as before R7
    /// A track's row: its number from 16 in, 30 for it and 10 after it, as an album's songs (AlbumPageLook).
    static let numberWidth: CGFloat = 30        // drawn: iGet .row number width 46, less its padding-left 16
    static let numberGap: CGFloat = 10          // drawn: iGet .row title's padding-left (dw.css .row > div 0 10px)
    /// The song searched for: the accent's bar at the row's edge.
    static let bar: CGFloat = 3                 // own: app.css --app-song-bar, as before R7
}

/// (R7's review) The facts line's lines: two held whatever it says, so another pressing chosen moves nothing under it -
/// two at most up to the largest standard size, and at the accessibility sizes (`lifted`) as many as its words take,
/// never cut short.
private struct FactsLines: ViewModifier {
    let lifted: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if lifted {
            content.lineLimit(2...)
        } else {
            content.lineLimit(2, reservesSpace: true)
        }
    }
}

/// (Phase 6) The store line's answer, and the pressing it was asked for.
private struct StoreSaid: Equatable {
    let id: String
    let answer: StoreStateAnswer
}

/// One track of a pressing's tracklist (ReleaseGroupPage.tsx's `app-rg-track`; R7, iGet's `.row`): its number in the
/// readout face, its title with what marks it under it ("Only on this pressing"), the mark's chip ("Bonus"), its length.
/// Read as one, on a thin line. The song the album was opened from (slice 3, `.is-song`): an accent bar at its edge, its
/// title in the accent - and VoiceOver hears ", the song you searched for" after it.
private struct PressedTrackRow: View {
    let number: String
    let title: String
    let length: String
    let mark: PressingTrack.Mark?
    var left = false
    var song = false

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The number's width and the gap after it, scaled as the number's words are (mono .small scales with footnote).
    @ScaledMetric(relativeTo: .footnote) private var numberWidth: CGFloat = GroupPageLook.numberWidth
    @ScaledMetric(relativeTo: .footnote) private var numberGap: CGFloat = GroupPageLook.numberGap

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(number)
                .font(Typeface.Phone.mono(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize()
                .frame(minWidth: numberWidth, alignment: .leading)
                .padding(.trailing, numberGap)
                .accessibilityHidden(left)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typeface.body)
                    .foregroundStyle(left ? DWPalette.t2 : song ? DWPalette.acc : DWPalette.text)
                    .fontWeight(song ? .semibold : nil)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                    .accessibilityLabel(song ? title + SongSearch.songWords : title)
                if let mark {
                    Text(mark.note)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                }
            }
            Spacer(minLength: 8)
            if let mark {
                DWChip(words: mark.chip, tone: .caution)
                    .padding(.trailing, 8)
            }
            Text(length)
                .font(Typeface.Phone.mono(.small))
                .foregroundStyle(DWPalette.t3)
        }
        .padding(.horizontal, GroupPageLook.side)
        .padding(.vertical, 6)
        .lookHeight(DWLook.here.rowHeight)
        .background(alignment: .leading) {
            if song {
                // a mark, not a face: the accent's bar at the row's edge
                Rectangle()
                    .fill(DWPalette.acc)
                    .frame(width: GroupPageLook.bar)
            }
        }
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
        .accessibilityElement(children: .combine)
    }
}
