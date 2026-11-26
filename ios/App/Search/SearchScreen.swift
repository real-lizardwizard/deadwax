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
///
/// (The redesign, slice R7 - notes/ios.md "The redesign, slice R7: Search, Get and Sources (2026-11-25)")
/// - On the phone, iSearch.dc.html: flat on the page's black under iOS's large title; (R7's review) the field the
///   look's sunken square box (iSearch's `.well.sfield`, `field`) where iOS's rounded search field was, held under the
///   bar as the list scrolls; the kinds a strip (PhoneStrip - each `search.choose`, the query narrowed, the kind in use
///   always shown); a heading's row for Top results and each section (See all at its end, in the
///   accent); each row 60 tall on a thin line - its cover 44, square (round for an artist), its title and line - ending
///   in what its tap does: a quiet bare ▶ for a song that plays (in the tap, nothing awaited), **Get** in the accent for
///   the album you don't have, › for a page.
/// - On the Mac (`desk`, from MacSearch.root()), MacSearchPage draws the toolbar, the table's header and the status bar
///   round this very list (SearchContent), each row and heading the table's (SearchTableDesk, which it hands down: a
///   row says what it is and does as a SearchTableRow, the Mac's page draws it) - and every ask, stand-down and resume
///   stays this screen's.
struct SearchScreen<Desk: View>: View {
    private let desk: (() -> Desk)?

    @Environment(SearchModel.self) private var search
    @Environment(LibraryModel.self) private var library
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.scenePhase) private var scenePhase
    /// (R7's review) The phone's field has the cursor: its well's edge in the accent.
    @FocusState private var fieldFocused: Bool

    /// (R7) The Mac's: the page drawn by `desk` (MacSearchPage).
    init(desk: @escaping () -> Desk) {
        self.desk = desk
    }

    var body: some View {
        Group {
            if let desk, Platform.mac {
                desk()
            } else {
                phone
            }
        }
        .navigationTitle(SearchWords.title)
        // (R7's review) the phone's field is its page's own (`field`); (the Mac app, slice 3) on the Mac the sidebar's,
        // these very words (MacSidebarView), and Edit > Find (⌘F) puts the cursor there
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

    /// The phone's list (iSearch.dc.html): the field held under the bar, the kinds' strip while there are words, then
    /// what is drawn - on the page's black.
    private var phone: some View {
        let state = search.state
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(ShelfAnchor.top)
                    if !state.query.isEmpty {
                        chips
                    }
                    SearchContent()
                }
                .padding(.horizontal, SearchLook.side)
                .padding(.bottom, SearchLook.bottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: navigation.searchScrollToTop) { _, _ in
                // the Search tab tapped at its root: to the top of the list
                withAnimation { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
            }
            .onChange(of: state.view) { _, _ in jump(proxy) }
            .onChange(of: state.drawn?.text) { _, _ in jump(proxy) }
            // (R7's review) the field over the list's top, where iOS's drawer was: always drawn, never scrolled away,
            // and the large title still folds into the bar as the list scrolls under it
            .safeAreaInset(edge: .top, spacing: 0) {
                field
            }
        }
        .background(DWPalette.page)
    }

    /// (R7's review) Search's field on the phone (iSearch's `.well.sfield`): the look's sunken box, square, 40 tall -
    /// the magnifying glass, the words, and ✕ while there are any - in place of iOS's rounded search field, every
    /// behaviour of that field kept: each keystroke `search.type` as the drawer's binding gave it (the typing cadence
    /// is the model's), the keyboard's Search key `search.submitted()` and the keyboard put away, no correcting and no
    /// capitals; the cursor only where a finger puts it, as before; ✕ empties the words as the drawer's clear button
    /// did. Its edge the accent's while it has the cursor (DWWell).
    private var field: some View {
        HStack(spacing: SearchLook.fieldGap) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DWPalette.t3)
                .accessibilityHidden(true)
            TextField(SearchWords.prompt,
                      text: Binding(get: { search.text }, set: { (typed: String) -> Void in search.type(typed) }),
                      prompt: Text(SearchWords.prompt).foregroundStyle(DWPalette.t3))
                .textFieldStyle(.plain)
                .font(Typeface.Look.text(.field))
                .foregroundStyle(DWPalette.fieldText)
                .focused($fieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    search.submitted()
                    fieldFocused = false
                }
                .accessibilityLabel(SearchWords.label)
            if !search.text.isEmpty {
                Button {
                    search.type("")
                } label: {
                    Image(systemName: "xmark")
                        .font(Typeface.Phone.text(.small).weight(.semibold))
                        .foregroundStyle(DWPalette.t3)
                        .frame(minWidth: SearchLook.clear)
                        .contentShape(DWTarget(face: Rectangle()))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SearchWords.clear)
            }
        }
        .padding(.horizontal, SearchLook.fieldInside)
        .lookHeight(SearchLook.field)
        .background {
            DWWell(focused: fieldFocused)
        }
        .padding(.horizontal, SearchLook.side)
        .padding(.bottom, SearchLook.fieldFoot)
        .background(DWPalette.page)
    }

    private func jump(_ proxy: ScrollViewProxy) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { proxy.scrollTo(ShelfAnchor.top, anchor: .top) }
    }

    // MARK: the chips

    /// The kinds (iSearch's .chips): the strip, each `search.choose` - the query narrowed, never the results - its
    /// sides the strip's own 16, so drawn out to the list's edges.
    private var chips: some View {
        PhoneStrip(options: SearchView.allCases, words: SearchWords.chip,
                   shown: Binding(get: { search.state.view }, set: { (view: SearchView) -> Void in search.choose(view) }),
                   spoken: SearchWords.chipsLabel)
            .padding(.horizontal, -SearchLook.side)
    }
}

extension SearchScreen where Desk == EmptyView {
    /// The iPhone's (and every one but the Mac's own): no desk.
    init() {
        desk = nil
    }
}

/// (R7) Search's list as drawn for its words - the phone's under its strip, the Mac's inside its table (MacSearchPage):
/// the hint with nothing typed; the gate words; the All view or a kind view.
struct SearchContent: View {
    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability

    var body: some View {
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

/// (R7) The list's own numbers, each where its drawing gives it.
enum SearchLook {
    /// The list's sides: the phone's 16 (iSearch's rows' padding-left), the Mac's table's cells' 10 - the notes in by
    /// that much, the rows and headings drawn out to the edges.
    static var side: CGFloat { Platform.mac ? macSide : phoneSide }
    static let phoneSide: CGFloat = 16          // drawn: iSearch .row padding-left
    static let macSide: CGFloat = 10            // drawn: Search .row > div padding-left
    /// A row's cover: 44, square (round for an artist), 12 from its words.
    static let cover: CGFloat = 44              // drawn: iSearch .cover width
    static let coverGap: CGFloat = 12           // drawn: iSearch .row gap (dw.ph .row > div padding 0 10px, less 0)
    /// A song's albums, opened under it: their covers 36, in by a row's cover and its gap.
    static let albumCover: CGFloat = 36         // own: as before R7
    /// The bare ▶'s target and glyph (dw.ph's .key.bare).
    static let play: CGFloat = 28               // drawn: dw.ph .key.bare width
    static let bottom: CGFloat = 24             // own: the list's foot, as before R7
    /// A heading's row: 6 under its words (dw.ph .row.grp padding-bottom), 12 above it past the row before (own).
    static let headingFoot: CGFloat = 6         // drawn: dw.ph .row.grp padding-bottom
    static let headingAbove: CGFloat = 12       // own: a section's room from the rows above it
    /// (R7's review) The phone's field: 40 tall, 12 in, its glyph 8 from its words, 10 above the strip; its ✕ 24 wide
    /// at least, its target the finger's 44 tall.
    static let field: Double = 40               // drawn: dw .sfield height
    static let fieldInside: CGFloat = 12        // drawn: dw .sfield padding-left
    static let fieldGap: CGFloat = 8            // drawn: dw .sfield gap
    static let fieldFoot: CGFloat = 10          // drawn: dw .sfield margin-bottom
    static let clear: CGFloat = 24              // own: the ✕'s width, 44 wide with its gap and the field's inside
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
        SearchRows(rows: shown.libraryRows, marks: marks)
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

/// (R7) A run of rows, each once - (R7's review) striped on the Mac's table by their place in it (SearchTable.striped,
/// MacSearchPage), never by their place in the run.
private struct SearchRows: View {
    let rows: [SearchRow]
    let marks: SearchMarks
    var top = false

    var body: some View {
        ForEach(SearchList.drawable(rows)) { (row: SearchRow) in
            SearchRowView(row: row, marks: marks, top: top)
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
            SearchRows(rows: shown.savedRows, marks: marks)
            switch shown.foot {
            case .searching?:
                AskingLine(personal: search.personal, musicBrainz: true)
            case .failed(let failure)?:
                //? under what's saved: MusicBrainz isn't answering, and these are earlier results
                MusicBrainzFailure(failure: failure, short: false, saved: !shown.savedRows.isEmpty) {
                    search.tryKindMusicBrainzAgain()
                }
            case .rows(let rows)?:
                SearchRows(rows: rows, marks: marks)
            case .said(let words)?:
                ShelfNote(words)
            default:
                EmptyView()
            }
            //? what landed after the asking line or the failure was drawn: below it, never pushing it down
            SearchRows(rows: shown.below, marks: marks)
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
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure = more.failure {
                Text(SearchWords.failure(failure))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch more.pages {
            case .more:
                Button {
                    if reachability.online { search.moreMusicBrainz() } else { reachability.tryNow() }
                } label: {
                    Text(more.label)
                }
                .buttonStyle(DWButtonStyle())
                .disabled(more.asking)
            case .far:
                Text(SearchMore.far)
                    .foregroundStyle(DWPalette.t2)
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
            SearchHeading(title: SearchWords.topResults)
            SearchRows(rows: top, marks: marks, top: true)
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
                    .foregroundStyle(DWPalette.t2)
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
        SearchRows(rows: section.rows, marks: marks)
        if let slot = section.slot {
            SectionSlot(kind: section.kind, slot: slot, saved: section.holdsSaved)
        }
        if studio {
            Text(SearchWords.studioNote)
                .font(Typeface.footnote)
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}

/// Top results' place for the picks still to come (SearchRows.tsx `topPlace`): one row's height, empty - hidden from
/// VoiceOver. (R7) A row's height as drawn where it stands: the phone's 60, the Mac's table's row (its desk's).
private struct TopPlace: View {
    @Environment(\.searchTable) private var table

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .lookHeight(table?.rowHeight ?? DWLook.here.tallRowHeight)
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
                .foregroundStyle(DWPalette.t2)
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
                .foregroundStyle(DWPalette.t2)
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
                    .buttonStyle(DWButtonStyle())
            case .said(let words):
                Text(words)
                    .foregroundStyle(DWPalette.t2)
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
                    .foregroundStyle(DWPalette.t2)
            case .show(let count):
                Button(SearchWords.libraryLate([.artists: count], personal: personal, text: text).button ?? "", action: show)
                    .buttonStyle(DWButtonStyle())
            case .nothing:
                Text(SearchWords.libraryLate([:], personal: personal, text: text).line)
                    .foregroundStyle(DWPalette.t2)
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
                .foregroundStyle(DWPalette.t2)
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

/// A section's heading, with See all (All's) - on the Mac without it, the toolbar's kinds being the way to one.
private struct SectionHead: View {
    let kind: SearchKind
    let seeAll: Bool

    @Environment(SearchModel.self) private var search

    var body: some View {
        if seeAll {
            SearchHeading(title: SearchWords.section(kind)) {
                // (R7's review) its target a finger's 44, reaching past the heading's 38 rather than growing it
                Button {
                    search.choose(SearchView(kind))
                } label: {
                    Text(SearchWords.seeAll)
                        .font(Typeface.Phone.text(.small).weight(.semibold))
                        .foregroundStyle(DWPalette.acc)
                        .contentShape(DWTarget(face: Rectangle()))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(SearchWords.seeAllLabel(kind))
            }
        } else {
            SearchHeading(title: SearchWords.section(kind))
        }
    }
}

/// (R7) A heading's row: on the phone dw.ph's `.row.grp` - 38 tall, its words at its foot, semibold in the heading's
/// colour, See all at its end - and on the Mac the table's group row (its desk's), See all left to the toolbar.
private struct SearchHeading<Trailing: View>: View {
    let title: String
    private let trailing: Trailing

    @Environment(\.searchTable) private var table

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        if let table, Platform.mac {
            table.heading(title)
        } else {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(title)
                    .font(Typeface.subheadline.weight(.semibold))
                    .foregroundStyle(DWPalette.head)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.top, SearchLook.headingAbove)
            .padding(.bottom, SearchLook.headingFoot)
            .lookHeight(DWLook.here.groupRowHeight)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            // (R7's review) over the row under it, where See all's target reaches past the heading's foot
            .zIndex(1)
        }
    }
}

extension SearchHeading where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
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
                .foregroundStyle(DWPalette.t2)
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
                    .foregroundStyle(DWPalette.t2)
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
            .buttonStyle(DWButtonStyle())
            .disabled(own.more == .asking)
        }
        .padding(.top, 14)
    }
}

// MARK: the rows

/// (R7) A row of Search's list as the Mac's table draws it - what it is and what it does, in values and one closure, the
/// Mac's page drawing it (SearchTableDesk), so this file names nothing of the Mac's own: its cells and buttons are
/// Core's (SearchTable), each button carried out by `act` - the very calls the phone's tap makes.
struct SearchTableRow {
    /// The name cell's picture: a library cover (round for an artist), or the Cover Art Archive's front of a release
    /// group.
    enum Picture {
        case cover(String?, round: Bool)
        case archive(String)
    }

    let id: String
    let title: String
    let cells: SearchTable.Cells
    let actions: [SearchTable.Action]
    let spoken: String
    let picture: Picture
    /// (R7's review) The line whose place on the table sets its stripe: a song's album, opened under it, its song's - nil,
    /// its own (`id`).
    var stripedAs: String? = nil
    var dimmed = false
    var busy = false
    var disabled = false
    /// A song's album, opened under it: in by a cover's width.
    var indented = false
    /// A MusicBrainz song's disclosure onto the albums it is on: whether it is open, and its toggle.
    var disclosure: (open: Bool, toggle: () -> Void)?
    let act: (SearchTable.Action) -> Void
}

/// (R7) The Mac's table's drawing of Search's list, handed down by MacSearchPage round SearchContent: each row and each
/// heading, a row's height (Top results' empty place) and a song's albums' indent. nil - the phone - draws the phone's.
struct SearchTableDesk {
    let row: (SearchTableRow) -> AnyView
    let heading: (String) -> AnyView
    let rowHeight: Double
    let indent: CGFloat
}

extension EnvironmentValues {
    /// (R7) The Mac's table, while Search's list is drawn inside it (MacSearchPage) - nil on the phone.
    @Entry var searchTable: SearchTableDesk? = nil
}

/// One row - an artist, an album or a song - as the Library's rows: its cover (round for an artist), its title, and its
/// line, the facts truncating and the place never (searchList.ts `rowLine`). Read as one: "Roads, Song · Portishead ·
/// Dummy · in your library, plays it from its album".
///
/// (R7) On the phone iSearch's `.row.tall`, flat on a thin line, ending in what its tap does (SearchTable.actions' first):
/// the quiet bare ▶, **Get** in the accent, or ›. On the Mac a row of the table (`table`, SearchTableDesk's): its cells
/// and its buttons, each one of the very actions the phone's tap takes.
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
    /// (R7) The Mac's table, drawing the rows there.
    @Environment(\.searchTable) private var table

    // Each part its own small function, every value's type spelled out: the one body this was type-checked in 366 ms
    // (7291225's review), and CI's older Swift is slower still.
    var body: some View {
        let line: SearchList.Line = SearchList.line(row, marks, top: top)
        if case .song(let song) = row {
            // a song's swipe right adds it to the queue, wherever its ••• offers Add to Queue - drawn by hand, the list
            // being a stack (AddToQueueSwipe.swift); the list's own padding (SearchScreen), the purple running out to
            // the screen's edge
            stacked(line)
                .addsToQueue(menu(song), in: .stack(inset: SearchLook.side))
        } else {
            stacked(line)
        }
    }

    @ViewBuilder private func stacked(_ line: SearchList.Line) -> some View {
        if table != nil, Platform.mac {
            content(line)
        } else {
            content(line)
                // (R7) dw.ph's .row border-bottom: the thin line under the row, the list's width
                .overlay(alignment: .bottom) {
                    DWRule(colour: DWPalette.rowRule)
                        .padding(.horizontal, -SearchLook.side)
                }
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

    /// (R7) What the row's buttons are (SearchTable.actions), its first what its tap does.
    private func actions(plays: Bool = false, opens: Bool = true) -> [SearchTable.Action] {
        SearchTable.actions(row, plays: plays, held: SearchTable.cells(row, marks).held, opens: opens)
    }

    /// A MusicBrainz album's row: the album you don't have - or, held, yours by the id bridge (busy while it asks).
    @ViewBuilder private func groupRow(_ group: ReleaseGroup, _ line: SearchList.Line) -> some View {
        let busy: Bool = search.opening == group.id
        if let table, Platform.mac {
            table.row(tableRow(line, picture: .archive(group.id), busy: busy,
                               disabled: busy || !reachability.online) { (_: SearchTable.Action) -> Void in
                search.open(group)
            })
        } else {
            Button {
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
    }

    /// A MusicBrainz artist's row: their page.
    @ViewBuilder private func mbArtistRow(_ match: MBArtistMatch, _ line: SearchList.Line) -> some View {
        if let table, Platform.mac {
            table.row(tableRow(line, picture: .cover(nil, round: true),
                               disabled: !reachability.online || match.mbid.isEmpty) { (_: SearchTable.Action) -> Void in
                search.openArtist(match)
            })
        } else {
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
    }

    /// An album a MusicBrainz song is on, as a row (Top results' song, and its named album): yours when you hold the song
    /// on it, else the album you don't have with the song marked - busy while it asks.
    @ViewBuilder private func songAlbumRow(_ song: FoundSong, _ album: SongAlbum, _ line: SearchList.Line) -> some View {
        let busy: Bool = search.opening == SearchModel.songAlbumKey(song, album)
        if let table, Platform.mac {
            table.row(tableRow(line, picture: .archive(album.id), busy: busy,
                               disabled: busy || !reachability.online) { (_: SearchTable.Action) -> Void in
                search.openSongAlbum(song, album)
            })
        } else {
            Button {
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
    }

    private func archiveFace(_ group: String, _ line: SearchList.Line, busy: Bool) -> some View {
        let large: Bool = typeSize.isAccessibilitySize
        return HStack(spacing: SearchLook.coverGap) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: group), size: ArchiveCoverSize.row)
                .frame(width: SearchLook.cover, height: SearchLook.cover)
                .clipShape(Rectangle())
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(Typeface.body)
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(large ? 3 : 1)
                SearchLineText(line: line, large: large)
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView()
                    .accessibilityHidden(true)
            } else {
                trailing(actions().first)
            }
        }
        .padding(.vertical, 8)
        .lookHeight(DWLook.here.tallRowHeight)
        .contentShape(Rectangle())
    }

    /// An artist's or an album's row: its page pushed on Search's stack.
    @ViewBuilder private func link(_ route: AppRoute, _ line: SearchList.Line, round: Bool, cover: String?,
                                   dimmed: Bool) -> some View {
        let opacity: Double = dimmed ? DWPalette.off : 1
        let value: String = dimmed ? DownloadWords.notOnDevice(Platform.device) : ""
        if let table, Platform.mac {
            table.row(tableRow(line, picture: .cover(cover, round: round), dimmed: dimmed,
                               disabled: dimmed) { (_: SearchTable.Action) -> Void in
                navigation.open(route)
            })
        } else {
            NavigationLink(value: route) {
                face(line, round: round, cover: cover, plays: false)
                    .opacity(opacity)
            }
            .buttonStyle(.plain)
            .disabled(dimmed)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken(line))
            .accessibilityValue(value)
        }
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
        let opacity: Double = dimmed ? DWPalette.off : 1
        let said: String = spoken(line) + Self.tapSaid(plays: plays, opens: opens, dimmed: dimmed)
        let value: String = dimmed ? DownloadWords.notOnDevice(Platform.device) : ""
        if let table, Platform.mac {
            // (R7) Play from its album, in the click with nothing awaited; Open its album's page
            table.row(tableRow(line, actions: actions(plays: plays && !dimmed, opens: opens),
                               picture: .cover(song.coverArt, round: false), dimmed: dimmed,
                               disabled: dimmed) { (action: SearchTable.Action) -> Void in
                switch action {
                case .play: tapped(song)
                default: openAlbum(of: song)
                }
            })
            .addToQueueAction(menu(song))
        } else {
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
    }

    private func songMenu(_ song: Song) -> some View {
        QueueMenu(request: menu(song)) {
            Image(systemName: "ellipsis")
                .font(Typeface.symbol(.body).weight(.semibold))
                .foregroundStyle(DWPalette.t3)
                .frame(minWidth: DWLook.here.target, minHeight: DWLook.here.target)
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
        } else {
            openAlbum(of: song)
        }
    }

    /// A song's album's page.
    private func openAlbum(of song: Song) {
        guard let id = song.albumId, !id.isEmpty else { return }
        navigation.open(.album(AlbumRoute(id: id, name: song.album, artist: song.artist, coverArt: song.coverArt)))
    }

    // MARK: the face

    private func spoken(_ line: SearchList.Line) -> String {
        [row.title, line.said].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
    }

    private func face(_ line: SearchList.Line, round: Bool, cover: String?, plays: Bool) -> some View {
        let large: Bool = typeSize.isAccessibilitySize
        let titleLines: Int = large ? 3 : 1
        return HStack(spacing: SearchLook.coverGap) {
            picture(round: round, cover: cover)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(Typeface.body)
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(titleLines)
                SearchLineText(line: line, large: large)
            }
            Spacer(minLength: 8)
            trailing(actions(plays: plays).first)
        }
        .padding(.vertical, 8)
        .lookHeight(DWLook.here.tallRowHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func picture(round: Bool, cover: String?) -> some View {
        if round {
            ArtistPicture(id: cover, side: SearchLook.cover, pixels: CoverSize.row)
        } else {
            LibraryCover(id: cover, pixels: CoverSize.row)
                .frame(width: SearchLook.cover, height: SearchLook.cover)
                .clipShape(Rectangle())
                .accessibilityHidden(true)
        }
    }

    /// (R7) What the row's tap does, at its end: the quiet bare ▶ for a song that plays (dw.ph's .key.bare), **Get** in
    /// the accent for the album you don't have (a flat .btn.sm.on's words - the row's tap is the Get), › for a page.
    @ViewBuilder private func trailing(_ action: SearchTable.Action?) -> some View {
        switch action {
        case .play?:
            SharpSymbol(.play)
                .font(Typeface.symbol(.footnote))
                .foregroundStyle(DWPalette.t3)
                .frame(minWidth: SearchLook.play, minHeight: SearchLook.play)
                .accessibilityHidden(true)
        case .get?:
            Text(SearchTable.Action.get.words)
                .font(Typeface.Look.text(.smallButton).weight(.semibold))
                .foregroundStyle(DWPalette.acc)
                .accessibilityHidden(true)
        case .open?:
            PhoneChevron()
        case nil:
            EmptyView()
        }
    }

    // MARK: the Mac's row (R7)

    /// The row as the Mac's table draws it (SearchTableDesk's): its cells (SearchTable.cells), its buttons (`actions`,
    /// the row's own by default) - each carried out by `act`, the very calls the phone's tap makes.
    private func tableRow(_ line: SearchList.Line, actions given: [SearchTable.Action]? = nil,
                          picture: SearchTableRow.Picture, busy: Bool = false, dimmed: Bool = false,
                          disabled: Bool = false, act: @escaping (SearchTable.Action) -> Void) -> SearchTableRow {
        SearchTableRow(id: SearchTable.lineID(row, top: top), title: row.title, cells: SearchTable.cells(row, marks),
                       actions: given ?? actions(), spoken: spoken(line), picture: picture,
                       dimmed: dimmed, busy: busy, disabled: disabled, act: act)
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
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
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
            .font(Typeface.Phone.text(.small))
            .foregroundStyle(DWPalette.t2)
        }
    }
}

/// A MusicBrainz song in a section (SearchRows.tsx `songDisclosure`): its row - its named album's cover, its title and
/// line, a chevron - a disclosure onto the albums it is on: Albums, EPs and Singles listed, the rest under one fold that
/// opens ("2 live albums and 1 compilation"), or, with nothing else to list, the fold's words as its caption and its
/// albums at once. Each album opens yours when you hold the song on it, else the album you don't have, the song marked.
/// (R7) On the Mac a row of the table (SearchTableDesk's): its triangle opens it onto its albums, its button its named
/// album's Get (or Open).
private struct SongDisclosure: View {
    let song: FoundSong
    let line: SearchList.Line
    let marks: SearchMarks

    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.searchTable) private var table

    var body: some View {
        let open: Bool = search.openSongs.contains(song.key)
        VStack(alignment: .leading, spacing: 0) {
            head(open: open)
            if open {
                if let table, Platform.mac {
                    // the table's rows, each in by the table's own indent
                    albums(indent: table.indent)
                } else {
                    albums(indent: 0)
                        .padding(.leading, SearchLook.cover + SearchLook.coverGap)
                        .padding(.bottom, 6)
                }
            }
        }
    }

    @ViewBuilder private func head(open: Bool) -> some View {
        let said: String = [song.title, line.said].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
        let named: SongAlbum? = SearchRowView.named(song, marks)
        if let table, Platform.mac {
            let row = SearchRow.mbSong(song)
            let cells: SearchTable.Cells = SearchTable.cells(row, marks)
            table.row(SearchTableRow(id: SearchTable.lineID(row, top: false), title: song.title, cells: cells,
                                     actions: named == nil ? [] : SearchTable.actions(row, plays: false, held: cells.held),
                                     spoken: said + ", " + SongSearch.disclosureHint(open: open),
                                     picture: .archive(named?.id ?? ""),
                                     disabled: !reachability.online,
                                     disclosure: (open, { search.toggleSong(song.key) })) { (_: SearchTable.Action) in
                if let named { search.openSongAlbum(song, named) }
            })
        } else {
            Button {
                search.toggleSong(song.key)
            } label: {
                phoneHead(named?.id ?? "", open: open)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(said)
            .accessibilityHint(SongSearch.disclosureHint(open: open))
        }
    }

    private func phoneHead(_ named: String, open: Bool) -> some View {
        let large: Bool = typeSize.isAccessibilitySize
        return HStack(spacing: SearchLook.coverGap) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: named), size: ArchiveCoverSize.row)
                .frame(width: SearchLook.cover, height: SearchLook.cover)
                .clipShape(Rectangle())
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(Typeface.body)
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(large ? 3 : 1)
                SearchLineText(line: line, large: large)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(Typeface.Phone.text(.small).weight(.semibold))
                .foregroundStyle(DWPalette.t3)
                .rotationEffect(.degrees(open ? 180 : 0))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .lookHeight(DWLook.here.tallRowHeight)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            DWRule(colour: DWPalette.rowRule)
                .padding(.horizontal, -SearchLook.side)
        }
    }

    /// The albums it is on - the fold's button and caption in by `indent` (the Mac's table's; the phone's list indents
    /// them all).
    @ViewBuilder private func albums(indent: CGFloat) -> some View {
        let bands: (listed: [SongAlbum], folded: [SongAlbum]) = SongSearch.bands(song)
        let foldOpen: Bool = bands.listed.isEmpty || search.openFolds.contains(song.key)
        ForEach(bands.listed) { (album: SongAlbum) in
            SongAlbumRow(song: song, album: album, marks: marks)
        }
        if !bands.folded.isEmpty {
            if bands.listed.isEmpty {
                // nothing else to list: the fold's words as its caption, its albums listed at once
                Text(SongSearch.foldLabel(bands.folded))
                    .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.leading, indent)
            } else {
                Button(SongSearch.foldLabel(bands.folded)) { search.toggleFold(song.key) }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .padding(.vertical, 6)
                    .padding(.leading, indent)
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
/// ("Live album · Bootleg · 2008 · 6:06 · in your library") - busy while it asks. (R7) On the Mac a row of the table, in
/// by a cover's width under its song (SearchTableRow's `indented`).
private struct SongAlbumRow: View {
    let song: FoundSong
    let album: SongAlbum
    let marks: SearchMarks

    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.searchTable) private var table

    var body: some View {
        let busy: Bool = search.opening == SearchModel.songAlbumKey(song, album)
        let line: String = SongSearch.albumLine(album, song, marks.index, personal: marks.personal, marks.evidence)
        let said: String = [album.title, line].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", ")
        if let table, Platform.mac {
            let row = SearchRow.songAlbum(song, album)
            let cells: SearchTable.Cells = SearchTable.cells(row, marks)
            table.row(SearchTableRow(id: SearchTable.lineID(row, top: false), title: album.title, cells: cells,
                                     actions: SearchTable.actions(row, plays: false, held: cells.held), spoken: said,
                                     picture: .archive(album.id),
                                     stripedAs: SearchTable.lineID(.mbSong(song), top: false), busy: busy,
                                     disabled: busy || !reachability.online,
                                     indented: true) { (_: SearchTable.Action) -> Void in
                search.openSongAlbum(song, album)
            })
        } else {
            Button {
                search.openSongAlbum(song, album)
            } label: {
                phoneFace(line, busy: busy)
            }
            .buttonStyle(.plain)
            .disabled(busy || !reachability.online)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(said)
            .accessibilityValue(busy ? SearchWords.loading : "")
        }
    }

    private func phoneFace(_ line: String, busy: Bool) -> some View {
        let large: Bool = typeSize.isAccessibilitySize
        return HStack(spacing: SearchLook.coverGap) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: album.id), size: ArchiveCoverSize.row)
                .frame(width: SearchLook.albumCover, height: SearchLook.albumCover)
                .clipShape(Rectangle())
            VStack(alignment: .leading, spacing: 1) {
                Text(album.title)
                    .font(Typeface.body)
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(large ? 3 : 1)
                if !line.isEmpty {
                    Text(line)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
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
}
