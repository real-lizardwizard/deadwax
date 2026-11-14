import DeadwaxCore
import SwiftUI

/// Search (Phase 5, slices 1 and 2 - notes/ios-specs/phase5-search.md 3.1-3.6; the web's app/Search.tsx and
/// SearchRows.tsx): one list, Apple Music's way - Top results, then Artists, Albums and Songs, yours first in each - from
/// Navidrome's search3, and MusicBrainz's albums you don't have after yours. The box is the navigation bar's (always
/// drawn, question 2), the chips under it while it has words; every rule and word is Core's (SearchState, SearchList,
/// SearchWords) and SearchModel makes the asks.
///
/// - All: the list as drawn for the words in its moments - Top results' decided picks first with a place for the rest,
///   the sections where the asking line stood once MusicBrainz answers or the cap passes, a late answer landing in its
///   section's slot or folded behind "Show 2 more albums" - frozen once drawn, its lines (whose a row is) changing in
///   place; the library's place kept at the top when it was late; Type a little more, the all-failed foot, nothing found.
/// - A kind view: that kind in full, More from your library when it is full; the Albums view MusicBrainz's albums below.
/// - A song plays from its tap when its album's songs are in hand (▶), else its album's page opens (question 10); its
///   ••• is the album page's song menu, or the song's own before its album is in hand (question 11). An artist and an
///   album open their pages; a MusicBrainz album the album you don't have - or yours, held (the id bridge).
/// - While deadwax can't be reached (question 5) nothing is asked: a list drawn for the words stays without
///   MusicBrainz's part, songs not on this phone dimmed; for new words, "Search works once deadwax is back."
/// - Navidrome known not to be there: the Library's gate words above the list, nothing asked of it.
struct SearchScreen: View {
    @Environment(SearchModel.self) private var search
    @Environment(ArtistsModel.self) private var artists
    @Environment(LibraryModel.self) private var library
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let state = search.state
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(ShelfAnchor.top)
                    if !state.query.isEmpty {
                        chips
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: navigation.searchScrollToTop) { _, _ in
                // the Search tab tapped at its root: to the top of the list
                withAnimation { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
            }
            .onChange(of: state.view) { _, _ in jump(proxy) }
            .onChange(of: state.drawn?.text) { _, _ in jump(proxy) }
        }
        .navigationTitle(SearchWords.title)
        .searchable(text: Binding(get: { search.text }, set: { (typed: String) -> Void in search.type(typed) }),
                    placement: .navigationBarDrawer(displayMode: .always), prompt: Text(SearchWords.prompt))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit(of: .search) { search.submitted() }
        .onAppear { search.shown() }
        .onChange(of: navigation.tab) { _, tab in
            if tab == .search { search.shown() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, navigation.tab == .search { search.shown() }
        }
        .onChange(of: reachability.online) { _, online in
            guard online else { return }
            search.shown()
            search.resumed()
        }
        .onChange(of: library.generations[.yours]) { _, _ in
            // your albums let go (an Add, a Remove, a star seen elsewhere): asked again, so whose a row is follows
            search.shown()
        }
        .onChange(of: search.navidromeAway == nil) { _, there in
            // Navidrome found again: what was skipped while it wasn't, asked
            if there { search.resumed() }
        }
    }

    private func jump(_ proxy: ScrollViewProxy) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
    }

    // MARK: the chips

    private var chips: some View {
        Picker(SearchWords.chipsLabel, selection: Binding(get: { search.state.view },
                                                          set: { (view: SearchView) -> Void in search.choose(view) })) {
            ForEach(SearchView.allCases) { (view: SearchView) in
                Text(SearchWords.chip(view)).tag(view)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(SearchWords.chipsLabel)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: what is drawn

    @ViewBuilder private var content: some View {
        let state = search.state
        let personal = search.personal
        if state.query.isEmpty {
            ShelfNote(SearchWords.hint(personal: personal))
        } else {
            if let closed = search.navidromeAway {
                SearchGateNote(closed: closed)
            }
            if let wanted = state.view.kind {
                kindView(wanted)
            } else {
                allView
            }
        }
    }

    /// The All view: the list drawn - kept while new words are asked - or the asking line before one is.
    @ViewBuilder private var allView: some View {
        let state = search.state
        let online = reachability.online
        if let drawn = state.drawn, online || drawn.text.utf16.elementsEqual(state.query.utf16) {
            DrawnList(drawn: drawn)
        } else if !online {
            ShelfNote(SearchWords.offline)
        } else {
            AskingLine(personal: search.personal, musicBrainz: state.drawnMusicBrainz(state.query))
        }
    }

    /// A kind view (Search.tsx `kindView`): its heading, the library's late place, the asking line, its library's
    /// failure, its rows (the chip's own search3, its order) and More from your library - then, the Albums view,
    /// MusicBrainz's albums below them - and "No albums for …" when nothing at all was found.
    @ViewBuilder private func kindView(_ kind: SearchKind) -> some View {
        let online = reachability.online
        if let shown = search.kindView, online || shown.own != nil {
            KindViewDrawn(shown: shown, online: online)
        } else if !online {
            ShelfNote(SearchWords.offline)
        } else if search.navidromeAway == nil {
            AskingLine(personal: search.personal)
        }
    }
}

/// A kind view as Core's `kindView` says it stands.
private struct KindViewDrawn: View {
    let shown: KindView
    let online: Bool

    @Environment(SearchModel.self) private var search

    var body: some View {
        let personal = search.personal
        let marks = search.marks
        let query = search.state.query
        SectionHead(kind: shown.kind, seeAll: false)
        if online, let late = shown.lateSlot {
            LibraryLateSlot(slot: late, text: query, failure: search.kindFailure,
                            show: { search.showKindLibrary() }, retry: { search.tryKindAgain() })
        }
        if shown.searching {
            AskingLine(personal: personal, musicBrainz: shown.searchingMusicBrainz)
        }
        if shown.libraryFailed {
            FailureNote(failure: search.kindFailure) { search.tryKindAgain() }
        }
        ForEach(SearchList.drawable(shown.libraryRows)) { (row: SearchRow) in
            SearchRowView(row: row, marks: marks, top: false)
        }
        if let own = shown.own, own.state == .answered, own.full || own.more != .idle {
            MoreButton(own: own, personal: personal)
        }
        if online, let foot = shown.foot {
            KindFoot(foot: foot, marks: marks)
        }
        if shown.nothing {
            ShelfNote(SearchWords.nothing(SearchView(shown.kind), query))
        }
    }
}

/// MusicBrainz's part of a kind view, below the library's.
private struct KindFoot: View {
    let foot: KindView.Foot
    let marks: SearchMarks

    @Environment(SearchModel.self) private var search

    var body: some View {
        switch foot {
        case .typeMore:
            ShelfNote(SearchWords.typeMore)
                .padding(.top, 6)
        case .searching:
            AskingLine(personal: search.personal, musicBrainz: true)
        case .failed(let failure):
            MusicBrainzFailure(failure: failure, short: false) { search.tryKindMusicBrainzAgain() }
        case .rows(let rows):
            ForEach(SearchList.drawable(rows)) { (row: SearchRow) in
                SearchRowView(row: row, marks: marks, top: false)
            }
        case .said(let words):
            ShelfNote(words)
        }
    }
}

/// The list as drawn for some words (Search.tsx `allView`): the library's place kept at the top, its failure, Top
/// results with a place kept for the picks still to come, the asking line where the sections will go - or each
/// section's rows with See all, a late kind's slot and the studio line - then Type a little more, the all-failed foot,
/// or "No results for …". Each row's line read from the marks as they are now. While deadwax can't be reached,
/// nothing of MusicBrainz's: its rows, slots and words left out, a section only of them gone.
private struct DrawnList: View {
    let drawn: SearchList.Drawn

    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let marks = search.marks
        let online = reachability.online
        let personal = search.personal
        let top: [SearchRow] = online ? drawn.top : drawn.top.filter { (row: SearchRow) -> Bool in !row.isMusicBrainz }
        let sections: [SearchList.Drawn.Section]? = online ? drawn.sections : drawn.sections.map(Self.offline)
        if online, let late = search.state.libraryLateSlot {
            LibraryLateSlot(slot: late, text: drawn.text, failure: search.failure,
                            show: { search.showLibrary() }, retry: { search.tryAgain() })
        }
        if drawn.failed {
            FailureNote(failure: search.failure) { search.tryAgain() }
        }
        if !top.isEmpty || (online && drawn.topPlace) {
            Text(SearchWords.topResults)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(SearchList.drawable(top)) { (row: SearchRow) in
                SearchRowView(row: row, marks: marks, top: true)
            }
            if online && drawn.topPlace {
                TopPlace()
            }
        }
        if let sections {
            ForEach(sections) { (section: SearchList.Drawn.Section) in
                DrawnSection(section: section, studio: online && section.kind == .albums && drawn.studio, marks: marks)
            }
            if online && !drawn.musicBrainz {
                ShelfNote(SearchWords.typeMore)
                    .padding(.top, 10)
            }
            if online, let failure = drawn.allFailed {
                MusicBrainzFailure(failure: failure, short: false,
                                   above: drawn.holdsLibrary ? SearchWords.libraryAbove(personal: personal) : "") {
                    search.tryMusicBrainzAgain()
                }
                .padding(.top, 10)
            }
        } else if online {
            // where the sections will go: one asking line
            AskingLine(personal: personal, musicBrainz: true)
        }
        if drawn.nothing {
            VStack(alignment: .leading, spacing: 6) {
                Text(SearchWords.nothing(.all, drawn.text))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SearchWords.checkSpelling)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        }
    }

    /// The sections as drawn offline: MusicBrainz's rows and its slots left out, a section left with none of the
    /// library's gone.
    private static func offline(_ sections: [SearchList.Drawn.Section]) -> [SearchList.Drawn.Section] {
        sections.compactMap { (section: SearchList.Drawn.Section) -> SearchList.Drawn.Section? in
            let rows = section.rows.filter { (row: SearchRow) -> Bool in !row.isMusicBrainz }
            return rows.isEmpty ? nil : SearchList.Drawn.Section(kind: section.kind, rows: rows)
        }
    }
}

/// One section as drawn: its heading with See all, its rows, a late kind's slot, and - Albums, when the studio clause
/// asked them - the studio line.
private struct DrawnSection: View {
    let section: SearchList.Drawn.Section
    let studio: Bool
    let marks: SearchMarks

    var body: some View {
        SectionHead(kind: section.kind, seeAll: true)
        ForEach(SearchList.drawable(section.rows)) { (row: SearchRow) in
            SearchRowView(row: row, marks: marks, top: false)
        }
        if let slot = section.slot {
            SectionSlot(kind: section.kind, slot: slot)
        }
        if studio {
            Text(SearchWords.studioNote)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}

/// Top results' place for the picks still to come (SearchRows.tsx `topPlace`): one row's height, empty - hidden from
/// VoiceOver.
private struct TopPlace: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Palette.coverEmpty)
                .frame(width: LibraryRow.cover, height: LibraryRow.cover)
            Spacer()
        }
        .padding(.vertical, 8)
        .opacity(0.6)
        .accessibilityHidden(true)
    }
}

/// A late kind's slot in its section (SearchRows.tsx `slot`), one height whatever it holds: still asking; folded
/// behind "Show 2 more albums"; why there is nothing; its failure, with Try again unless the words were refused.
private struct SectionSlot: View {
    let kind: SearchKind
    let slot: SearchList.Drawn.Slot

    @Environment(SearchModel.self) private var search

    var body: some View {
        Group {
            switch slot {
            case .asking:
                AskingLine(personal: search.personal, musicBrainz: true)
            case .show(let rows):
                Button(SearchWords.fold(kind, rows.count).button) { search.showFolded(kind) }
                    .buttonStyle(SecondaryPill())
                    .padding(.top, 8)
            case .said(let words):
                ShelfNote(words)
            case .failed:
                MusicBrainzFailure(failure: albumsFailure, short: true) { search.tryMusicBrainzAgain() }
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    /// The albums' failure as the state holds it - else (never, as the state draws it) MusicBrainz away.
    private var albumsFailure: MBFailure {
        if case .failed(_, _, let failure) = search.state.albums { return failure }
        return MBFailure(message: SearchWords.moreUnsearched, unavailable: true)
    }
}

/// The library's place kept at the top of a list drawn without it (Search.tsx's `lateSlot`), as it stands: asking;
/// its failure and Try again; not searched (Navidrome away); "Show 3 from your library"; or that it found nothing.
private struct LibraryLateSlot: View {
    let slot: SearchState.LateSlot
    let text: String
    let failure: (any Error)?
    let show: () -> Void
    let retry: () -> Void

    @Environment(SearchModel.self) private var search

    var body: some View {
        let personal = search.personal
        Group {
            switch slot {
            case .asking:
                AskingLine(personal: personal)
            case .failed:
                FailureNote(failure: failure, retry: retry)
            case .skipped:
                ShelfNote(SearchWords.librarySkipped(personal: personal))
            case .show(let count):
                Button(SearchWords.libraryLate([.artists: count], personal: personal, text: text).button ?? "", action: show)
                    .buttonStyle(SecondaryPill())
                    .padding(.top, 8)
            case .nothing:
                ShelfNote(SearchWords.libraryLate([:], personal: personal, text: text).line)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }
}

/// MusicBrainz's failure, in its words (`failureWords` - `short` for a slot): a refusal's own, busy, away; Try again
/// unless refused. The all-failed foot adds what is above it.
private struct MusicBrainzFailure: View {
    let failure: MBFailure
    let short: Bool
    let above: String
    let retry: () -> Void

    @Environment(Reachability.self) private var reachability

    init(failure: MBFailure, short: Bool, above: String = "", retry: @escaping () -> Void) {
        self.failure = failure
        self.short = short
        self.above = above
        self.retry = retry
    }

    var body: some View {
        let words = SearchWords.failure(failure, short: short)
        VStack(alignment: .leading, spacing: 8) {
            Text(above.isEmpty ? words : "\(words) \(above)")
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
            if !failure.refused {
                Button(SearchWords.tryAgain) {
                    if reachability.online { retry() } else { reachability.tryNow() }
                }
                .disabled(reachability.probing)
            }
        }
        .padding(.vertical, 6)
    }
}

/// A section's heading, with See all (All's).
private struct SectionHead: View {
    let kind: SearchKind
    let seeAll: Bool

    @Environment(SearchModel.self) private var search

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(SearchWords.section(kind))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if seeAll {
                Button(SearchWords.seeAll) { search.choose(SearchView(kind)) }
                    .accessibilityLabel(SearchWords.seeAllLabel(kind))
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 2)
    }
}

/// The asking line: the library's words while only it is asked, "Searching…" once MusicBrainz is in it.
private struct AskingLine: View {
    let personal: Bool
    var musicBrainz = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(SearchWords.searching(personal: personal, musicBrainz: musicBrainz))
                .foregroundStyle(Palette.quiet)
        }
        .accessibilityElement(children: .combine)
        .padding(.top, 12)
    }
}

/// A failure's words, and Try again (nothing asked while deadwax can't be reached - whether it is back, instead).
private struct FailureNote: View {
    let failure: (any Error)?
    let retry: () -> Void

    @Environment(Reachability.self) private var reachability

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let failure {
                ErrorNote(failure, retry: true)
            } else {
                // never drawn without its failure in hand (SearchModel keeps it with the list); said plainly if it is
                ErrorNote(text: reachability.online ? ErrorWords.other : SearchWords.offline)
            }
            Button(SearchWords.tryAgain) {
                if reachability.online { retry() } else { reachability.tryNow() }
            }
            .disabled(reachability.probing)
        }
        .padding(.vertical, 8)
    }
}

/// Navidrome known not to be there: the Library's gate words, above the list (the web's NeedsNavidrome), with its Try
/// again.
private struct SearchGateNote: View {
    let closed: NavidromeGate.Closed

    @Environment(LibraryModel.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(closed.title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(closed.lines, id: \.self) { (line: String) in
                Text(line)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if closed.tryAgain {
                Button(NavidromeGate.tryAgain) {
                    Task { await library.checkNavidrome() }
                }
                .disabled(library.checkingNavidrome)
            }
        }
        .padding(.vertical, 8)
    }
}

/// A kind view's More from your library: Loading… while it asks, Try again after a failure.
private struct MoreButton: View {
    let own: KindLibrary
    let personal: Bool

    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if own.more == .failed, let failure = search.moreFailure {
                ErrorNote(failure, retry: true)
            }
            Button {
                if reachability.online { search.more() } else { reachability.tryNow() }
            } label: {
                switch own.more {
                case .asking: Text(SearchWords.loading)
                case .failed: Text(SearchWords.tryAgain)
                case .idle: Text(SearchWords.moreFromLibrary(personal: personal))
                }
            }
            .buttonStyle(SecondaryPill())
            .disabled(own.more == .asking)
        }
        .padding(.top, 14)
    }
}

// MARK: the rows

/// One row - an artist, an album or a song - as the Library's rows: its cover (round for an artist), its title, and its
/// line, the facts truncating and the place never (searchList.ts `rowLine`). Read as one: "Roads, Song · Portishead ·
/// Dummy · in your library, plays it from its album".
struct SearchRowView: View {
    let row: SearchRow
    let marks: SearchMarks
    let top: Bool

    @Environment(SearchModel.self) private var search
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize

    // Each part its own small function, every value's type spelled out: the one body this was type-checked in 366 ms
    // (7291225's review), and CI's older Swift is slower still.
    var body: some View {
        let line: SearchList.Line = SearchList.line(row, marks, top: top)
        VStack(spacing: 0) {
            content(line)
            Divider().padding(.leading, LibraryRow.textInset)
        }
    }

    @ViewBuilder private func content(_ line: SearchList.Line) -> some View {
        switch row {
        case .artist(let artist):
            link(AppRoute.artist(ArtistRoute(artist)), line, round: true, cover: artist.coverArt,
                 dimmed: dims(artist: artist.id))
        case .album(let album):
            link(AppRoute.album(AlbumRoute(album)), line, round: false, cover: album.coverArt,
                 dimmed: dims(album: album.id))
        case .song(let song):
            songRow(song, line)
        case .group(let group):
            groupRow(group, line)
        case .mbArtist:
            // a MusicBrainz artist (Top results' family, an album's credited artist the library hasn't): their page is
            // slice 3's (question 9) - drawn, opening nothing yet (question 14)
            face(line, round: true, cover: nil, plays: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(spoken(line))
        }
    }

    /// A MusicBrainz album's row: the album you don't have - or, held, yours by the id bridge (busy while it asks).
    private func groupRow(_ group: ReleaseGroup, _ line: SearchList.Line) -> some View {
        let busy: Bool = search.opening == group.id
        return Button {
            search.open(group)
        } label: {
            groupFace(group, line, busy: busy)
        }
        .buttonStyle(.plain)
        .disabled(busy || !reachability.online)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(line))
        .accessibilityValue(busy ? SearchWords.loading : "")
    }

    private func groupFace(_ group: ReleaseGroup, _ line: SearchList.Line, busy: Bool) -> some View {
        let large: Bool = typeSize.isAccessibilitySize
        return HStack(spacing: 12) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: group.id), size: ArchiveCoverSize.row)
                .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .foregroundStyle(.primary)
                    .lineLimit(large ? 3 : 1)
                lineText(line, large: large)
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView()
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// An artist's or an album's row: its page pushed on Search's stack.
    private func link(_ route: AppRoute, _ line: SearchList.Line, round: Bool, cover: String?,
                      dimmed: Bool) -> some View {
        let opacity: Double = dimmed ? Palette.off : 1
        let value: String = dimmed ? DownloadWords.notOnPhone : ""
        return NavigationLink(value: route) {
            face(line, round: round, cover: cover, plays: false)
                .opacity(opacity)
        }
        .buttonStyle(.plain)
        .disabled(dimmed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(line))
        .accessibilityValue(value)
    }

    // MARK: offline

    /// Offline, an album with nothing on this phone (the Library's Albums).
    private func dims(album id: String) -> Bool {
        if reachability.online { return false }
        let download: AlbumDownload = downloads.album(id: id)
        return !download.hasSongsHere
    }

    /// Offline, an artist with no album on this phone (ArtistsScreen's `artistsHere`).
    private func dims(artist id: String) -> Bool {
        if reachability.online { return false }
        let here: Bool = downloads.downloadedAlbums.contains { (album: IndexAlbum) -> Bool in
            album.artistId == id && downloads.album(id: album.id).hasSongsHere
        }
        return !here
    }

    /// Offline, a song not on this phone.
    private func dims(song id: String) -> Bool {
        if reachability.online { return false }
        return !downloads.isHere(id)
    }

    // MARK: a song's

    /// The album a song plays from: asked for so its tap plays - or, while deadwax can't be reached, its copy on this
    /// phone.
    private func album(of song: Song) -> Album? {
        guard let id = song.albumId, !id.isEmpty else { return nil }
        if let ready = search.state.ready[id] { return ready }
        return reachability.online ? nil : downloads.keptAlbum(id)
    }

    /// What a song's tap plays: its album's songs (those on this phone, offline), with it among them.
    private func playable(_ song: Song) -> (album: Album, songs: [Song], at: Int)? {
        guard let album = album(of: song), let songs = album.song else { return nil }
        let shown: [Song] = reachability.online ? songs : OfflineAlbum.playable(songs, here: downloads.isHere)
        guard let at = shown.firstIndex(where: { (each: Song) -> Bool in each.id == song.id }) else { return nil }
        return (album, shown, at)
    }

    /// What VoiceOver adds of a song's tap - only where the tap does it (a dimmed row does nothing).
    private static func tapSaid(plays: Bool, opens: Bool, dimmed: Bool) -> String {
        if dimmed { return "" }
        if plays { return SearchWords.playsSaid }
        return opens ? SearchWords.opensSaid : ""
    }

    @ViewBuilder private func songRow(_ song: Song, _ line: SearchList.Line) -> some View {
        let plays: Bool = playable(song) != nil
        let dimmed: Bool = dims(song: song.id)
        let opens: Bool = !(song.albumId ?? "").isEmpty
        let opacity: Double = dimmed ? Palette.off : 1
        let said: String = spoken(line) + Self.tapSaid(plays: plays, opens: opens, dimmed: dimmed)
        let value: String = dimmed ? DownloadWords.notOnPhone : ""
        HStack(spacing: 4) {
            Button {
                tapped(song)
            } label: {
                face(line, round: false, cover: song.coverArt, plays: plays && !dimmed)
                    .opacity(opacity)
            }
            .buttonStyle(.plain)
            .disabled(dimmed || (!plays && !opens))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(said)
            .accessibilityValue(value)
            songMenu(song)
        }
    }

    private func songMenu(_ song: Song) -> some View {
        QueueMenu(request: menu(song)) {
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

    /// The song's ••• - as its album's when that album is in hand, else the song alone (Songs' row).
    private func menu(_ song: Song) -> QueueMenuRequest {
        if let album = album(of: song) {
            return QueueMenuRequest(pick: QueuePick.song(song, of: album), album: album)
        }
        return QueueMenuRequest(pick: PlaylistPlay.pick(song: song), album: nil)
    }

    /// A song's tap: its album played from it, in the tap with nothing awaited - or, with its album not in hand, the
    /// album's page (question 10).
    private func tapped(_ song: Song) {
        if let plays = playable(song) {
            player.play(songs: plays.songs, album: plays.album, at: plays.at)
        } else if let id = song.albumId, !id.isEmpty {
            navigation.open(.album(AlbumRoute(id: id, name: song.album, artist: song.artist, coverArt: song.coverArt)))
        }
    }

    // MARK: the face

    private func spoken(_ line: SearchList.Line) -> String {
        [row.title, line.said].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
    }

    private func face(_ line: SearchList.Line, round: Bool, cover: String?, plays: Bool) -> some View {
        let large: Bool = typeSize.isAccessibilitySize
        let titleLines: Int = large ? 3 : 1
        return HStack(spacing: 12) {
            picture(round: round, cover: cover)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .foregroundStyle(.primary)
                    .lineLimit(titleLines)
                lineText(line, large: large)
            }
            Spacer(minLength: 8)
            trailing(plays: plays)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func picture(round: Bool, cover: String?) -> some View {
        if round {
            ArtistPicture(id: cover, side: LibraryRow.cover, pixels: CoverSize.row)
        } else {
            LibraryCover(id: cover, pixels: CoverSize.row)
                .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    /// The line under the title: the facts take the ellipsis, the place is never cut - at accessibility sizes, both
    /// as one, wrapping.
    @ViewBuilder private func lineText(_ line: SearchList.Line, large: Bool) -> some View {
        if line.said.isEmpty {
            EmptyView()
        } else if large {
            Text(line.said)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .lineLimit(2)
        } else {
            let place: String = line.line.isEmpty ? line.place : " \u{00B7} " + line.place
            HStack(spacing: 0) {
                if !line.line.isEmpty {
                    Text(line.line)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if !line.place.isEmpty {
                    Text(place)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.quiet)
        }
    }

    /// ▶ for a song that plays from its tap, › for an artist.
    @ViewBuilder private func trailing(plays: Bool) -> some View {
        if plays {
            Image(systemName: "play.fill")
                .font(.caption2)
                .foregroundStyle(Palette.quiet)
                .accessibilityHidden(true)
        } else if case .artist = row {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}
