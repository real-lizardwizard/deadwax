import DeadwaxCore
import SwiftUI

/// Search (Phase 5, slices 1-4 - notes/ios-specs/phase5-search.md 3.1-3.6, 6.3 and 6.4; the web's app/Search.tsx and
/// SearchRows.tsx): one list, Apple Music's way - Top results, then Artists, Albums and Songs, yours first in each - from
/// Navidrome's search3, and MusicBrainz's artists, albums and songs nobody has after yours. The box is the navigation bar's (always
/// drawn, question 2), the chips under it while it has words; every rule and word is Core's (SearchState, SearchList,
/// SearchWords) and SearchModel makes the asks.
///
/// - All: the list as drawn for the words in its moments - Top results' decided picks first with a place for the rest,
///   the sections where the asking line stood once MusicBrainz answers or the cap passes, a late answer landing in its
///   section's slot or folded behind "Show 2 more albums" - frozen once drawn, its lines (whose a row is) changing in
///   place; the library's place kept at the top when it was late; Type a little more, the all-failed foot, nothing found.
/// - A kind view: that kind in full, More from your library when it is full; MusicBrainz's of the kind below - the Songs
///   view, under an artist's name alone, says a title is needed with it - (slice 4) what's saved leading them, drawn
///   as MusicBrainz's own rows are, and More from MusicBrainz under them while there is another page.
/// - A song plays from its tap when its album's songs are in hand (▶), else its album's page opens (question 10); its
///   ••• is the album page's song menu, or the song's own before its album is in hand (question 11), and a swipe right
///   adds what that ••• would (Add to Queue - SearchRowView). An artist and an
///   album open their pages; a MusicBrainz album the album you don't have - or yours, held (the id bridge); a
///   MusicBrainz artist their page; a MusicBrainz song, in its section, opens onto the albums it is on (in Top results,
///   its named album) - each album yours when you hold the song on it, else the album you don't have, the song marked.
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
        // the navigation bar's field, always drawn - (the Mac app, slice 3) on the Mac the sidebar's instead, these very
        // words (MacSidebarView), and Edit > Find (⌘F) puts the cursor there
        .searchField(text: Binding(get: { search.text }, set: { (typed: String) -> Void in search.type(typed) }),
                     prompt: SearchWords.prompt)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onSubmit(of: .search) { search.submitted() }
        .onAppear { search.shown() }
        .onChange(of: navigation.tab) { _, tab in
            // another tab: a held album's row asking the id bridge lets go, so its answer opens nothing there
            if tab == .search { search.shown() } else { search.standDown() }
        }
        .onChange(of: navigation.search) { _, _ in
            // a page pushed or popped over the list: the same
            search.standDown()
        }
        .onChange(of: navigation.nowPlayingShown) { _, shown in
            if shown { search.standDown() }
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
        if online {
            KindMusicBrainz(shown: shown, marks: marks)
        }
        if shown.nothing {
            ShelfNote(SearchWords.nothing(SearchView(shown.kind), query))
        }
    }
}

/// MusicBrainz's part of a kind view, below the library's (Search.tsx's kindView): Type a little more, or a title
/// needed; else what's saved (slice 4), then the asking line or MusicBrainz's failure with the rows that landed after
/// it below it - or MusicBrainz's rows, or why there are none - and More from MusicBrainz. Drawn only while deadwax can
/// be reached.
private struct KindMusicBrainz: View {
    let shown: KindView
    let marks: SearchMarks

    @Environment(SearchModel.self) private var search

    var body: some View {
        switch shown.foot {
        case .typeMore?:
            ShelfNote(SearchWords.typeMore)
                .padding(.top, 6)
        case .needATitle?:
            ShelfNote(SongSearch.needATitle)
                .padding(.top, 6)
        default:
            ForEach(SearchList.drawable(shown.savedRows)) { (row: SearchRow) in
                SearchRowView(row: row, marks: marks, top: false)
            }
            switch shown.foot {
            case .searching?:
                AskingLine(personal: search.personal, musicBrainz: true)
            case .failed(let failure)?:
                //? under what's saved: MusicBrainz isn't answering, and these are earlier results
                MusicBrainzFailure(failure: failure, short: false, saved: !shown.savedRows.isEmpty) {
                    search.tryKindMusicBrainzAgain()
                }
            case .rows(let rows)?:
                ForEach(SearchList.drawable(rows)) { (row: SearchRow) in
                    SearchRowView(row: row, marks: marks, top: false)
                }
            case .said(let words)?:
                ShelfNote(words)
            default:
                EmptyView()
            }
            //? what landed after the asking line or the failure was drawn: below it, never pushing it down
            ForEach(SearchList.drawable(shown.below)) { (row: SearchRow) in
                SearchRowView(row: row, marks: marks, top: false)
            }
            if let more = shown.more {
                MusicBrainzMore(more: more)
            }
        }
    }
}

/// More from MusicBrainz under a kind view's rows (slice 4): what its last page brought, its failure, and the button -
/// "Loading…" while it asks, "Try again" after a failure - or, past the furthest page, a word more is the way on.
private struct MusicBrainzMore: View {
    let more: KindView.More

    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note = more.note {
                Text(note)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure = more.failure {
                Text(SearchWords.failure(failure))
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch more.pages {
            case .more:
                Button {
                    if reachability.online { search.moreMusicBrainz() } else { reachability.tryNow() }
                } label: {
                    Text(more.label)
                }
                .buttonStyle(SecondaryPill())
                .disabled(more.asking)
            case .far:
                Text(SearchMore.far)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            case .end:
                EmptyView()
            }
        }
        .padding(.top, 14)
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
                .font(Typeface.title3.weight(.semibold))
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
                //? (slice 4) what's saved drawn above: one line saying MusicBrainz is away and these are earlier
                //? results - "What's in your library is above." only when something of the library's is
                MusicBrainzFailure(failure: failure, short: false, saved: drawn.holdsSaved,
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
                    .font(Typeface.headline)
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
            SectionSlot(kind: section.kind, slot: slot, saved: section.holdsSaved)
        }
        if studio {
            Text(SearchWords.studioNote)
                .font(Typeface.footnote)
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
            Corners.artShape
                .fill(Palette.coverEmpty)
                .frame(width: LibraryRow.cover, height: LibraryRow.cover)
            Spacer()
        }
        .padding(.vertical, 8)
        .opacity(0.6)
        .accessibilityHidden(true)
    }
}

/// A slot's one height (app.css `--app-search-slot`: a finger-tall row and a little room above and below), whatever
/// it holds - scaled with the text, so it holds at the accessibility sizes too.
enum SearchSlotMetrics {
    static let height: CGFloat = 60
}

/// A slot's frame (app.css `.app-search-slot`): one fixed height whatever it holds - the asking line, then what lands in
/// it - and one line, a line too long for it ending in an ellipsis rather than wrapping, so nothing below it moves under
/// a finger when its answer lands.
private struct SlotFrame<Content: View>: View {
    private let content: Content

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = SearchSlotMetrics.height

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
    }
}

/// A slot's asking line: the sweep and its words, on the slot's one row.
private struct SlotAsking: View {
    let words: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(words)
                .foregroundStyle(Palette.quiet)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A slot's failure on its one row (app.css `.app-search-slot.is-row`): the words, ellipsized, and Try again at its end
/// - nothing asked while deadwax can't be reached, whether it is back instead.
private struct SlotFailure: View {
    let words: String
    let tryAgain: Bool
    let retry: () -> Void

    @Environment(Reachability.self) private var reachability

    var body: some View {
        HStack(spacing: 12) {
            Text(words)
                .foregroundStyle(Palette.quiet)
                .frame(maxWidth: .infinity, alignment: .leading)
            if tryAgain {
                Button(SearchWords.tryAgain) {
                    if reachability.online { retry() } else { reachability.tryNow() }
                }
                .fixedSize()
                .disabled(reachability.probing)
            }
        }
    }
}

/// A late kind's slot in its section (SearchRows.tsx `slot`), one height whatever it holds: still asking; folded
/// behind "Show 2 more albums"; why there is nothing; its failure, with Try again unless the words were refused.
private struct SectionSlot: View {
    let kind: SearchKind
    let slot: SearchList.Drawn.Slot
    /// (Slice 4) Rows from what's saved are drawn above it: its failure says these are earlier results.
    let saved: Bool

    @Environment(SearchModel.self) private var search

    var body: some View {
        SlotFrame {
            switch slot {
            case .asking:
                SlotAsking(words: SearchWords.searching(personal: search.personal, musicBrainz: true))
            case .show(let rows):
                Button(SearchWords.fold(kind, rows.count).button) { search.showFolded(kind) }
                    .buttonStyle(SecondaryPill())
            case .said(let words):
                Text(words)
                    .foregroundStyle(Palette.quiet)
            case .failed:
                let failure = kindFailure
                SlotFailure(words: saved ? SearchWords.savedAway(failure, short: true) : SearchWords.failure(failure, short: true),
                            tryAgain: !failure.refused) {
                    search.tryMusicBrainzAgain()
                }
            }
        }
    }

    /// The slot's kind's failure as the state holds it - else (never, as the state draws it) MusicBrainz away.
    private var kindFailure: MBFailure {
        search.state.failure(of: kind) ?? MBFailure(message: SearchWords.moreUnsearched, unavailable: true)
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
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let personal = search.personal
        SlotFrame {
            switch slot {
            case .asking:
                SlotAsking(words: SearchWords.searching(personal: personal, musicBrainz: false))
            case .failed:
                SlotFailure(words: failureWords, tryAgain: true, retry: retry)
            case .skipped:
                Text(SearchWords.librarySkipped(personal: personal))
                    .foregroundStyle(Palette.quiet)
            case .show(let count):
                Button(SearchWords.libraryLate([.artists: count], personal: personal, text: text).button ?? "", action: show)
                    .buttonStyle(SecondaryPill())
            case .nothing:
                Text(SearchWords.libraryLate([:], personal: personal, text: text).line)
                    .foregroundStyle(Palette.quiet)
            }
        }
    }

    /// The library's failure in a listener's words, on the slot's one line (the web's `late.message`) - the raw detail
    /// whoever runs deadwax sees in a FailureNote not drawn here: a slot has no room for it, and the web's has none.
    private var failureWords: String {
        guard let failure else { return reachability.online ? ErrorWords.other : SearchWords.offline }
        return ErrorWords.of(failure, admin: server.access.seesDetail, retry: true).said
    }
}

/// MusicBrainz's failure, in its words (`failureWords` - `short` for a slot): a refusal's own, busy, away - under what's
/// saved (`saved`, slice 4), that these are earlier results (`savedAwayWords`); Try again unless refused. The all-failed
/// foot adds what is above it.
private struct MusicBrainzFailure: View {
    let failure: MBFailure
    let short: Bool
    let saved: Bool
    let above: String
    let retry: () -> Void

    @Environment(Reachability.self) private var reachability

    init(failure: MBFailure, short: Bool, saved: Bool = false, above: String = "", retry: @escaping () -> Void) {
        self.failure = failure
        self.short = short
        self.saved = saved
        self.above = above
        self.retry = retry
    }

    var body: some View {
        let words = saved ? SearchWords.savedAway(failure, short: short) : SearchWords.failure(failure, short: short)
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
                .font(Typeface.title3.weight(.semibold))
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
                .font(Typeface.headline)
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
        if case .song(let song) = row {
            // a song's swipe right adds it to the queue, wherever its ••• offers Add to Queue - drawn by hand, the list
            // being a stack (AddToQueueSwipe.swift); the list's own padding (SearchScreen), the purple running out to
            // the screen's edge
            stacked(line)
                .addsToQueue(menu(song), in: .stack(inset: 16))
        } else {
            stacked(line)
        }
    }

    private func stacked(_ line: SearchList.Line) -> some View {
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
                .albumRightClick(AlbumRoute(album))
        case .song(let song):
            songRow(song, line)
                .macContextMenu { QueueMenuItems(request: menu(song)) }
        case .group(let group):
            groupRow(group, line)
        case .mbArtist(let match):
            mbArtistRow(match, line)
        case .mbSong(let song):
            if top, let album = Self.named(song, marks) {
                // Top results go to the best guess: its named album, the song marked
                songAlbumRow(song, album, line)
            } else {
                // a section looks closer: the albums it is on
                SongDisclosure(song: song, line: line, marks: marks)
            }
        case .songAlbum(let song, let album):
            songAlbumRow(song, album, line)
        }
    }

    /// The album a MusicBrainz song's row names (`namedAlbum`) - nil for a song on none (never, as songs are grouped).
    static func named(_ song: FoundSong, _ marks: SearchMarks) -> SongAlbum? {
        song.albums.isEmpty ? nil : SongSearch.namedAlbum(song, marks.index, marks.evidence).album
    }

    /// A MusicBrainz album's row: the album you don't have - or, held, yours by the id bridge (busy while it asks).
    private func groupRow(_ group: ReleaseGroup, _ line: SearchList.Line) -> some View {
        let busy: Bool = search.opening == group.id
        return Button {
            search.open(group)
        } label: {
            archiveFace(group.id, line, busy: busy)
        }
        .buttonStyle(.plain)
        .disabled(busy || !reachability.online)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(line))
        .accessibilityValue(busy ? SearchWords.loading : "")
    }

    /// A MusicBrainz artist's row: their page.
    private func mbArtistRow(_ match: MBArtistMatch, _ line: SearchList.Line) -> some View {
        Button {
            search.openArtist(match)
        } label: {
            face(line, round: true, cover: nil, plays: false)
        }
        .buttonStyle(.plain)
        .disabled(!reachability.online || match.mbid.isEmpty)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(line))
    }

    /// An album a MusicBrainz song is on, as a row (Top results' song, and its named album): yours when you hold the song
    /// on it, else the album you don't have with the song marked - busy while it asks.
    private func songAlbumRow(_ song: FoundSong, _ album: SongAlbum, _ line: SearchList.Line) -> some View {
        let busy: Bool = search.opening == SearchModel.songAlbumKey(song, album)
        return Button {
            search.openSongAlbum(song, album)
        } label: {
            archiveFace(album.id, line, busy: busy)
        }
        .buttonStyle(.plain)
        .disabled(busy || !reachability.online)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(line))
        .accessibilityValue(busy ? SearchWords.loading : "")
    }

    private func archiveFace(_ group: String, _ line: SearchList.Line, busy: Bool) -> some View {
        let large: Bool = typeSize.isAccessibilitySize
        return HStack(spacing: 12) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: group), size: ArchiveCoverSize.row)
                .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                .clipShape(Corners.artShape)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .foregroundStyle(.primary)
                    .lineLimit(large ? 3 : 1)
                SearchLineText(line: line, large: large)
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
            .addToQueueAction(menu(song))
            songMenu(song)
        }
    }

    private func songMenu(_ song: Song) -> some View {
        QueueMenu(request: menu(song)) {
            Image(systemName: "ellipsis")
                .font(Typeface.symbol(.body).weight(.semibold))
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
                SearchLineText(line: line, large: large)
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
                .clipShape(Corners.artShape)
                .accessibilityHidden(true)
        }
    }

    /// ▶ for a song that plays from its tap, › for an artist (the library's or MusicBrainz's).
    @ViewBuilder private func trailing(plays: Bool) -> some View {
        if plays {
            SharpSymbol(.play)
                .font(Typeface.symbol(.caption2))
                .foregroundStyle(Palette.quiet)
                .accessibilityHidden(true)
        } else if row.kind == .artists {
            Image(systemName: "chevron.right")
                .font(Typeface.symbol(.footnote).weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

/// The line under a row's title: the facts take the ellipsis, the place is never cut - at accessibility sizes, both as
/// one, wrapping.
struct SearchLineText: View {
    let line: SearchList.Line
    let large: Bool

    var body: some View {
        if line.said.isEmpty {
            EmptyView()
        } else if large {
            Text(line.said)
                .font(Typeface.footnote)
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
            .font(Typeface.footnote)
            .foregroundStyle(Palette.quiet)
        }
    }
}

/// A MusicBrainz song in a section (SearchRows.tsx `songDisclosure`): its row - its named album's cover, its title and
/// line, a chevron - a disclosure onto the albums it is on: Albums, EPs and Singles listed, the rest under one fold that
/// opens ("2 live albums and 1 compilation"), or, with nothing else to list, the fold's words as its caption and its
/// albums at once. Each album opens yours when you hold the song on it, else the album you don't have, the song marked.
private struct SongDisclosure: View {
    let song: FoundSong
    let line: SearchList.Line
    let marks: SearchMarks

    @Environment(SearchModel.self) private var search
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let open: Bool = search.openSongs.contains(song.key)
        VStack(alignment: .leading, spacing: 0) {
            head(open: open)
            if open {
                albums
                    .padding(.leading, LibraryRow.textInset)
                    .padding(.bottom, 6)
            }
        }
    }

    private func head(open: Bool) -> some View {
        let large: Bool = typeSize.isAccessibilitySize
        let said: String = [song.title, line.said].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
        let named: String = SearchRowView.named(song, marks)?.id ?? ""
        return Button {
            search.toggleSong(song.key)
        } label: {
            HStack(spacing: 12) {
                ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: named), size: ArchiveCoverSize.row)
                    .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                    .clipShape(Corners.artShape)
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title)
                        .foregroundStyle(.primary)
                        .lineLimit(large ? 3 : 1)
                    SearchLineText(line: line, large: large)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(Typeface.symbol(.footnote).weight(.semibold))
                    .foregroundStyle(Palette.quiet)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(said)
        .accessibilityHint(SongSearch.disclosureHint(open: open))
    }

    @ViewBuilder private var albums: some View {
        let bands: (listed: [SongAlbum], folded: [SongAlbum]) = SongSearch.bands(song)
        let foldOpen: Bool = bands.listed.isEmpty || search.openFolds.contains(song.key)
        ForEach(bands.listed) { (album: SongAlbum) in
            SongAlbumRow(song: song, album: album, marks: marks)
        }
        if !bands.folded.isEmpty {
            if bands.listed.isEmpty {
                // nothing else to list: the fold's words as its caption, its albums listed at once
                Text(SongSearch.foldLabel(bands.folded))
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                Button(SongSearch.foldLabel(bands.folded)) { search.toggleFold(song.key) }
                    .font(Typeface.footnote)
                    .padding(.vertical, 8)
                    .accessibilityHint(SongSearch.foldHint(open: foldOpen))
            }
            if foldOpen {
                ForEach(bands.folded) { (album: SongAlbum) in
                    SongAlbumRow(song: song, album: album, marks: marks)
                }
            }
        }
    }
}

/// An album a MusicBrainz song is on, under the song (SearchRows.tsx `albumRow`): its cover, its title, and its line
/// ("Live album · Bootleg · 2008 · 6:06 · in your library") - busy while it asks.
private struct SongAlbumRow: View {
    let song: FoundSong
    let album: SongAlbum
    let marks: SearchMarks

    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let cover: CGFloat = 36

    var body: some View {
        let busy: Bool = search.opening == SearchModel.songAlbumKey(song, album)
        let line: String = SongSearch.albumLine(album, song, marks.index, personal: marks.personal, marks.evidence)
        let large: Bool = typeSize.isAccessibilitySize
        Button {
            search.openSongAlbum(song, album)
        } label: {
            HStack(spacing: 10) {
                ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: album.id), size: ArchiveCoverSize.row)
                    .frame(width: Self.cover, height: Self.cover)
                    .clipShape(Corners.artShape)
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.title)
                        .foregroundStyle(.primary)
                        .lineLimit(large ? 3 : 1)
                    if !line.isEmpty {
                        Text(line)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                            .lineLimit(large ? 3 : 1)
                    }
                }
                Spacer(minLength: 8)
                if busy {
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy || !reachability.online)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([album.title, line].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", "))
        .accessibilityValue(busy ? SearchWords.loading : "")
    }
}
