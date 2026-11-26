import DeadwaxCore
import SwiftUI

/// An artist's page on the Mac (the redesign, slice R6 - Artist.dc.html; notes/ios.md "The redesign, slice R6: an
/// artist"), drawn in ArtistView's place by MacArtist.page(for:): ArtistView keeps the page's model and every ask, wait
/// and letting go, and hands this its rows and its calls (ArtistDesk) - so the Mac draws and does nothing the phone's
/// page doesn't.
///
/// - The toolbar (.bar): Play (the accent's), Shuffle, the groove and Studio only | Everything once their discography is
///   asked (who they are known, deadwax in reach); at its end the managers' Artist images…, Move albums… and Which
///   artist is this? - each only as the phone offers it (ArtistManage.offered: its permission, deadwax in reach). Where
///   they don't fit (a window of 880) the three fold into a •••. The drawing's ‹ Artists is the window's own back; its
///   Pin is left out (no pin for an artist yet).
/// - The band (559): their round picture (88), their name (.h1), who they are on MusicBrainz ("Group · Sydney · since
///   1973"), their listeners on Last.fm, who they are chosen here - and at its end the chips: "6 in your library", "10
///   more to get" (ArtistPageFacts.chips). The drawing's description is slice A4's, left for it under the facts.
/// - The page is one lazy stack in one scroll view (R6's review): each list a section of it (MacColumnList's `flow`),
///   its rows made only as they come into view - and only then their covers asked, so Everything's hundreds ask a
///   screenful, never past the relay's 64 under way. The page hears ↑ ↓ Home End and Return for the list a click last
///   went to, and brings the row selected into its own view (`pressed`, `keep`).
/// - Top Songs (560): A1's, all ten, in a list of the Mac's own (MacColumnList: #, Title with its cover, Album) - under
///   the band when Last.fm answered in time, after the discography for an answer later than that (LastfmPage.placeOf),
///   as the phone's page has it; "From Last.fm" under it. A double-click or Return plays every top song you have from
///   that one, as TopSongRow's tap (ArtistView's playTop) - or, for one you don't have, opens the album you don't have
///   (openTop, the spinner in its row while it's asked); a right-click on one you have is the song's •••. A row whose
///   songs aren't in hand waits, doing nothing; one not on this Mac while deadwax can't be reached is dimmed.
/// - The discography (561, MacColumnList at View > Row Size's height): Album (its cover and title), Year, Songs, In your
///   library (the chip, and the album's format - Album info's Format of its songs in hand - or "2 pressings" for one of
///   theirs the library holds, "not in your library" for one nobody holds) and the buttons: Play and Open an album you
///   have, Get one nobody holds (ArtistPageFacts.offersGet - and only for someone who may get albums: else Open), Open
///   one of theirs the library holds. A double-click or Return opens the row - a double-click on its buttons is
///   theirs alone (`controls`); a right-click on an album you have is its page's •••. VoiceOver reads a row as one,
///   its buttons its actions (`voice`). While deadwax can't be reached an album with nothing on this Mac is dimmed and
///   does nothing. Over it "Albums", the phone's heading, and at its end (Last.fm, slice A2) the albums' order - a
///   pop-up, "Newest first" or "Most played" (AlbumOrderItems, the phone's items), its room held while Last.fm's answer
///   may yet offer Most played; in Most played order each row's plays ("4.1M plays") at the end of In your library, and
///   in what VoiceOver reads of it. Under it MusicBrainz's word (ArtistTheirFoot).
/// - Your most played (560; "Most played" until slice A2 - James, 26 Nov: so it never reads as the albums' order): the
///   songs of their albums you have played most (MostPlayedSongs) - each song once across its pressings, its plays its
///   most-played take's, the number its album's page shows under Plays - in the same list with Plays at its end. A
///   double-click or Return plays the list from the song (playMost); a right-click is its •••.
/// - (Last.fm, slice A2) Similar Artists, at the page's foot: the phone's tiles (SimilarArtistTile) in the Mac's faces,
///   one row that a trackpad scrolls sideways, four always in view at the narrowest page - and past four See All, the
///   phone's grid (SimilarArtistsScreen), where a mouse reaches every one. A click opens their page, or their
///   MusicBrainz page; no right-click (a tile has no •••). "From Last.fm" under it.
/// - The status bar: "16 albums", "6 in your library", "59 songs". The drawing's "MusicBrainz asked 4 minutes ago" is
///   left out (the page keeps no time for its answer).
struct MacArtistPage: View {
    let desk: ArtistDesk

    @Environment(DownloadModel.self) private var downloads
    /// (The Mac's Row Size) The rows' height, which the discography's table adds up as MacColumnList draws them.
    @Environment(\.macRowSize) private var rowSize
    /// The discography's row selected, by its key - and Top Songs' and Most played's.
    @State private var selected: String?
    @State private var selectedTop: String?
    @State private var selectedMost: String?
    /// (R6's review) The list the keys move through - the one a click last went to - and the page's width, which the
    /// lists' columns are laid over.
    @State private var keysFor: Table?
    @FocusState private var keysHere: Bool
    @State private var width: Double = 0

    /// The page's three lists, by name: their rows' keys in the page's scroll view (MacListFlow), and the keys'.
    private enum Table: String {
        case top, discography, most
    }

    /// The discography's buttons' column: a double-click there is theirs, never the row's.
    static let buttonsColumn = 4

    /// The discography's columns (Artist.dc.html's .cols): Album and In your library share what the others leave. The
    /// drawing's Type is left out - Navidrome's albums carry none - and its 250 for In your library shared, so a window
    /// of 880 keeps both readable.
    static let columns = [
        MacListColumn(title: ArtistPageFacts.Words.album, width: .flexible),
        MacListColumn(title: ArtistPageFacts.Words.year, width: .fixed(Drawn.year)),
        MacListColumn(title: ArtistPageFacts.Words.songs, width: .fixed(Drawn.songs)),
        MacListColumn(title: ArtistPageFacts.Words.inYourLibrary, width: .flexible),
        MacListColumn(title: ArtistPageFacts.Words.actions, width: .fixed(Drawn.actions)),
    ]

    /// Top Songs' columns (an album page's song rows, Album.dc.html's): the rank, the song with its cover, its album -
    /// the two sharing what the rank leaves. Most played's the same, with Plays at the end as the album page's.
    static let topColumns = [
        MacListColumn(title: MacAlbumFacts.Words.number, width: .fixed(Drawn.number)),
        MacListColumn(title: MacAlbumFacts.Words.title, width: .flexible),
        MacListColumn(title: ArtistPageFacts.Words.album, width: .flexible),
    ]
    static let mostColumns = topColumns + [MacListColumn(title: MacAlbumFacts.Words.plays, width: .fixed(Drawn.plays))]

    /// The drawing's numbers: the band 132 tall at least, its picture 88 and 18 from the words, 22 in; the page's
    /// sections 22 in, 20 under each, a section's heading 18 above its list and 8 over it; the columns' widths.
    enum Drawn {
        static let band: CGFloat = 132
        static let picture: CGFloat = 88
        static let bandGap: CGFloat = 18
        static let side: CGFloat = 22
        static let chipGap: CGFloat = 6
        static let below: CGFloat = 20
        static let headAbove: CGFloat = 18
        static let headBelow: CGFloat = 8
        static let number: Double = 46
        static let plays: Double = 70
        static let year: Double = 56
        static let songs: Double = 60
        static let actions: Double = 140
    }

    /// The toolbar as drawn, or folded.
    private enum Fit {
        case full, folded
    }

    var body: some View {
        let counts = ArtistPageFacts.counts(desk.rows, personal: desk.personal)
        MacPage {
            ViewThatFits(in: .horizontal) {
                tools(.full)
                tools(.folded)
            }
        } content: {
            ScrollViewReader { (proxy: ScrollViewProxy) in
                ScrollView(.vertical) {
                    // (R6's review) one lazy stack: the band, then each list's header and rows as lines of it
                    LazyVStack(alignment: .leading, spacing: 0) {
                        band(counts)
                        page
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onGeometryChange(for: Double.self) { (page: GeometryProxy) -> Double in
                        Double(page.size.width)
                    } action: { (now: Double) -> Void in
                        width = now
                    }
                }
                // the keys of the list a click last went to (MacListFlow), heard here - the page's own scroll view,
                // which every row is in
                .focusable()
                .focused($keysHere)
                .focusEffectDisabled()
                .listKeys { (key: ListKey) -> KeyPress.Result in pressed(key) }
                // a list's row selected by ↑ and ↓ (or a click): brought into the page's view, by its key - a row not
                // yet made included, the ForEach's own identity
                .onChange(of: selected) { (_: String?, now: String?) -> Void in bring(.discography, now, proxy) }
                .onChange(of: selectedTop) { (_: String?, now: String?) -> Void in bring(.top, now, proxy) }
                .onChange(of: selectedMost) { (_: String?, now: String?) -> Void in bring(.most, now, proxy) }
                // (the Mac's Row Size) rows taller or shorter move the one selected: brought back into view
                .onChange(of: rowSize) { (_: MacRowSize, _: MacRowSize) -> Void in
                    guard let table = keysFor else { return }
                    bring(table, selection(table), proxy)
                }
            }
        }
        // each list's selection kept while its row is listed, else none - never another row in its place
        .onChange(of: ids(.discography)) { (_: [String], now: [String]) -> Void in keep(.discography, in: now) }
        .onChange(of: ids(.top)) { (_: [String], now: [String]) -> Void in keep(.top, in: now) }
        .onChange(of: ids(.most)) { (_: [String], now: [String]) -> Void in keep(.most, in: now) }
        .macStatus(MacStatusItems.Items(leading: ArtistPageFacts.status(counts, songs: desk.songs)))
    }

    // MARK: the keys (R6's review)

    /// A list's section of the page: the page's width, its name, and a click on a row giving it the keyboard.
    private func flow(_ table: Table) -> MacListFlow {
        MacListFlow(width: width, name: table.rawValue) {
            keysFor = table
            keysHere = true
        }
    }

    /// A list's rows' keys, in the order drawn.
    private func ids(_ table: Table) -> [String] {
        switch table {
        case .top: return desk.top.map { (row: TopSongs.Row) -> String in TopLine(row: row).id }
        case .discography: return desk.rows.map(\.id)
        case .most: return desk.mostPlayed.map(\.id)
        }
    }

    private func selection(_ table: Table) -> String? {
        switch table {
        case .top: return selectedTop
        case .discography: return selected
        case .most: return selectedMost
        }
    }

    private func select(_ table: Table, _ id: String?) {
        switch table {
        case .top: selectedTop = id
        case .discography: selected = id
        case .most: selectedMost = id
        }
    }

    /// A key on the page, for the list a click last went to: ↑ ↓ Home End move its selection, Return opens its row -
    /// looked up again by its key as it opens. With no list chosen, the scroll view's own.
    private func pressed(_ key: ListKey) -> KeyPress.Result {
        guard let table = keysFor else { return .ignored }
        switch MacListKeys.pressed(key, selected: selection(table), in: ids(table)) {
        case .moved(let now):
            select(table, now)
            return .handled
        case .open(let id):
            switch table {
            case .top:
                guard let row = desk.top.first(where: { (row: TopSongs.Row) -> Bool in TopLine(row: row).id == id })
                else { return .ignored }
                openTop(row)
            case .discography:
                guard let row = desk.rows.first(where: { (row: ArtistJoin.Row) -> Bool in row.id == id })
                else { return .ignored }
                open(row)
            case .most:
                guard let row = desk.mostPlayed.first(where: { (row: MostPlayedSongs.Row) -> Bool in row.id == id })
                else { return .ignored }
                openMost(row)
            }
            return .handled
        case .ignored:
            return .ignored
        }
    }

    /// The row selected in a list, brought into the page's view by its key.
    private func bring(_ table: Table, _ id: String?, _ proxy: ScrollViewProxy) {
        guard let id else { return }
        proxy.scrollTo(MacListFlow.key(table.rawValue, id))
    }

    /// A list's selection, kept while its row is listed.
    private func keep(_ table: Table, in ids: [String]) {
        let kept = MacTable.kept(selection(table), in: ids)
        if kept != selection(table) { select(table, kept) }
    }

    // MARK: the toolbar

    @ViewBuilder private func tools(_ fit: Fit) -> some View {
        HStack(spacing: 6) {
            Button(action: desk.play) {
                HStack(spacing: 6) {
                    SharpSymbol(.play)
                    Text(PlaylistWords.play)
                }
            }
            .buttonStyle(DWButtonStyle(kind: .pri))
            .disabled(!desk.playable)
            Button(ShuffleWords.shuffle, action: desk.shuffle)
                .buttonStyle(DWButtonStyle())
                .disabled(!desk.playable)
            if let theirs = desk.theirs {
                MacGroove()
                DWSegmented(options: [true, false],
                            words: { (studio: Bool) -> String in
                                studio ? ArtistPageFacts.Words.studioOnly : ArtistPageFacts.Words.everything
                            },
                            chosen: Binding(get: { theirs.studioOnly },
                                            set: { (studio: Bool) -> Void in desk.studio(studio) }),
                            spoken: ArtistPageFacts.Words.studioLabel, large: true)
            }
            Spacer(minLength: 0)
            switch fit {
            case .full:
                if desk.offered.images {
                    Button(ArtistPageFacts.Words.images) { desk.tool(.images) }
                        .buttonStyle(DWButtonStyle())
                        // their folder known first: the sheet asks by it
                        .disabled(!desk.managing.known)
                }
                if desk.offered.move, let current = desk.managing.current {
                    Button(ArtistPageFacts.Words.moveAlbums) { desk.tool(.move) }
                        .buttonStyle(DWButtonStyle())
                        .help(ArtistManageWords.moveItem(current))
                        .accessibilityLabel(ArtistManageWords.moveItem(current))
                }
                if desk.offered.who {
                    Button(ArtistManageWords.whoItem) { desk.tool(.who) }
                        .buttonStyle(DWButtonStyle())
                }
            case .folded:
                if desk.offered.any {
                    Menu {
                        toolItems
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(DWButtonStyle())
                    .fixedSize()
                    .accessibilityLabel(ArtistManageWords.more)
                }
            }
        }
    }

    /// The folded •••: the managers' three, as the phone's page offers them.
    @ViewBuilder private var toolItems: some View {
        if desk.offered.images {
            Button(ArtistManageWords.imagesItem, systemImage: "photo.on.rectangle") { desk.tool(.images) }
                .disabled(!desk.managing.known)
        }
        if desk.offered.move, let current = desk.managing.current {
            Button(ArtistManageWords.moveItem(current), systemImage: "folder") { desk.tool(.move) }
        }
        if desk.offered.who {
            Button(ArtistManageWords.whoItem, systemImage: "person.crop.circle.badge.questionmark") { desk.tool(.who) }
        }
    }

    // MARK: the band (559)

    private func band(_ counts: ArtistPageFacts.Counts) -> some View {
        let model = desk.model
        let lastfm = desk.lastfm
        let facts = MBArtistPage.factsLine(model.facts)
        return HStack(alignment: .center, spacing: Drawn.bandGap) {
            ArtistHeroPicture(managing: desk.managing, coverArt: model.coverArt, side: Drawn.picture,
                              pixels: CoverSize.tile)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name)
                    .font(Typeface.Mac.text(.h1).weight(.bold))
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(2)
                    .help(model.name)
                    .accessibilityAddTraits(.isHeader)
                if !facts.isEmpty {
                    Text(facts)
                        .font(Typeface.Mac.text(.base))
                        .foregroundStyle(DWPalette.head)
                        .lineLimit(1)
                        .help(facts)
                }
                // (Last.fm) "2.3M listeners": its line there from the first frame whenever it can be drawn, blank until
                // (and unless) the answer says - so nothing under it moves
                if lastfm.heroLine {
                    Text(lastfm.listeners ?? " ")
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .accessibilityHidden(lastfm.listeners == nil)
                }
                if desk.byChoice {
                    Text(ArtistManageWords.chosen)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: Drawn.chipGap) {
                ForEach(ArtistPageFacts.chips(counts, mayGet: desk.mayGet)) { (chip: ArtistPageFacts.Chip) in
                    DWChip(words: chip.words, tone: chip.yours ? .good : .plain)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, Drawn.side)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: Drawn.band, alignment: .leading)
        .background(DWPalette.card)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.frame) }
    }

    // MARK: the page under the band

    @ViewBuilder private var page: some View {
        let model = desk.model
        if model.answer == nil && !desk.online && desk.rows.isEmpty {
            // nothing of theirs in hand, and deadwax out of reach: a state, not a failure - nothing was asked
            quiet(DownloadWords.onlyDownloadedPlay)
        } else if model.gone {
            ErrorNote(text: ErrorWords.artistGone)
                .padding(Drawn.side)
        } else if let failure = model.failure, model.answer == nil, desk.online {
            VStack(alignment: .leading, spacing: 8) {
                ErrorNote(failure, gone: ErrorWords.artistGone, retry: true)
                Button(LibraryWords.tryAgain, action: desk.reload)
                    .buttonStyle(DWButtonStyle())
            }
            .padding(Drawn.side)
        } else {
            if !desk.line.isEmpty || (desk.online && model.asks.someMissing) {
                HStack(spacing: 10) {
                    if !desk.line.isEmpty {
                        Text(desk.line)
                            .font(Typeface.Mac.text(.small))
                            .foregroundStyle(DWPalette.t3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if desk.online && model.asks.someMissing {
                        Button(LibraryWords.tryAgain, action: desk.tryAgain)
                            .buttonStyle(DWButtonStyle(size: .small))
                    }
                }
                .padding(.horizontal, Drawn.side)
                .padding(.top, 12)
            }
            if !desk.arrival.holding {
                if !desk.top.isEmpty && desk.arrival.place == .inPlace { topSongs }
                discography
                // an answer that came once the albums were drawn: after them, for the page's life
                if !desk.top.isEmpty && desk.arrival.place != .inPlace { topSongs }
                if !desk.mostPlayed.isEmpty { mostPlayed }
                // (A2) Similar Artists, at the foot
                if desk.similar.shows { similarArtists }
            }
            if let foot = desk.lastfm.foot { lastfmFoot(foot) }
            Color.clear
                .frame(height: Drawn.side)
                .accessibilityHidden(true)
        }
    }

    private func quiet(_ words: String) -> some View {
        Text(words)
            .font(Typeface.Mac.text(.base))
            .foregroundStyle(DWPalette.t2)
            .padding(Drawn.side)
    }

    // MARK: Top Songs and Most played (560)

    /// Top Songs: its heading, all ten in the Mac's list - its header and rows lines of the page's lazy stack, the
    /// last row's rule the list's foot - and "From Last.fm" under them.
    @ViewBuilder private var topSongs: some View {
        let lines = desk.top.map { (row: TopSongs.Row) -> TopLine in TopLine(row: row) }
        sectionHead(LastfmWords.topSongs)
        MacColumnList(columns: Self.topColumns, rows: lines, flow: flow(.top), selected: $selectedTop,
                      open: { (line: TopLine) -> Void in openTop(line.row) },
                      menu: { (line: TopLine) -> SongRightClickIfHeld in SongRightClickIfHeld(menu: line.menu) }
        ) { (line: TopLine, column: Int) in
            topCell(line.row, column)
        }
        LastfmCredit(lastfmPage: desk.model.lastfm?.url, font: Typeface.Mac.text(.small), above: Drawn.headBelow)
            .padding(.horizontal, Drawn.side)
            .padding(.bottom, Drawn.below)
    }

    /// Your most played: its heading and the songs you have played most, in the Mac's list with Plays at its end - lines
    /// of the page's lazy stack, as Top Songs'. Never drawn with no plays at all (desk.mostPlayed empty).
    @ViewBuilder private var mostPlayed: some View {
        sectionHead(ArtistPageFacts.Words.yourMostPlayed)
        MacColumnList(columns: Self.mostColumns, rows: desk.mostPlayed, flow: flow(.most), selected: $selectedMost,
                      open: { (row: MostPlayedSongs.Row) -> Void in openMost(row) },
                      menu: { (row: MostPlayedSongs.Row) -> SongRightClick in
                          SongRightClick(menu: QueueMenuRequest(pick: QueuePick.song(row.song, of: row.album),
                                                                album: row.album))
                      }
        ) { (row: MostPlayedSongs.Row, column: Int) in
            mostCell(row, column)
        }
        below
    }

    /// A section's heading (.h3): 18 above its list, 8 over it, 22 in - a row, its end where a section's own control
    /// goes (`trailing`: A2's albums order at the Albums heading's, Similar Artists' See All). A header to VoiceOver.
    private func sectionHead<Trailing: View>(_ words: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(words)
                .font(Typeface.Mac.text(.h3).weight(.semibold))
                .foregroundStyle(DWPalette.head)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, Drawn.side)
        .padding(.top, Drawn.headAbove)
        .padding(.bottom, Drawn.headBelow)
    }

    /// A heading with nothing at its end.
    private func sectionHead(_ words: String) -> some View {
        sectionHead(words) { EmptyView() }
    }

    /// The room under a section, 20: a line of its own in the page's stack.
    private var below: some View {
        Color.clear
            .frame(height: Drawn.below)
            .accessibilityHidden(true)
    }

    /// A song that plays now: deadwax in reach, or the song on this Mac.
    private func plays(_ song: Song) -> Bool {
        desk.online || downloads.isHere(song.id)
    }

    /// A top song opened - a double-click, Return, VoiceOver's action: one you have played from (every top song you
    /// have that plays now, from it), one you don't have's album asked for; one waiting, or maybe yours, does nothing.
    private func openTop(_ row: TopSongs.Row) {
        switch row.kind {
        case .have(let song, _):
            guard plays(song) else { return }
            desk.playTop(desk.top, row)
        case .missing:
            desk.openTop(row)
        case .waiting, .unknown:
            return
        }
    }

    /// A most-played song opened: the list played from it, while it plays now.
    private func openMost(_ row: MostPlayedSongs.Row) {
        guard plays(row.song) else { return }
        desk.playMost(desk.mostPlayed, row)
    }

    /// A top song dimmed: maybe yours (its album's songs not in hand), or not on this Mac, or - one you don't have -
    /// deadwax out of reach.
    private func dimmed(_ row: TopSongs.Row) -> Bool {
        switch row.kind {
        case .have(let song, _): return !plays(song)
        case .missing: return !desk.online
        case .unknown: return true
        case .waiting: return false
        }
    }

    @ViewBuilder
    private func topCell(_ row: TopSongs.Row, _ column: Int) -> some View {
        let opener = desk.model.opener
        let missing = row.kind == .missing
        Group {
            switch column {
            case 0:
                // Last.fm's place, from 1 as the drawing counts
                Text(String(row.rank + 1))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t3)
            case 1:
                HStack(spacing: 8) {
                    songCover(Self.cover(row))
                    Text(row.title)
                        .help(row.title)
                    if missing && opener.opening == TopSongOpener.key(row.top) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(SearchWords.loading)
                    }
                }
            default:
                // a song you don't have: why its album didn't open, for the visit, in its line's place
                let line = (missing ? opener.trouble(row.top) : nil) ?? row.line
                Text(line)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .help(line)
            }
        }
        .opacity(dimmed(row) ? DWPalette.off : 1)
    }

    @ViewBuilder
    private func mostCell(_ row: MostPlayedSongs.Row, _ column: Int) -> some View {
        Group {
            switch column {
            case 0:
                Text(String(row.rank + 1))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t3)
            case 1:
                HStack(spacing: 8) {
                    songCover(row.album.coverArt)
                    Text(row.title)
                        .help(row.title)
                }
            case 2:
                Text(row.line)
                    .font(Typeface.Mac.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .help(row.line)
            default:
                Text(row.playsWords)
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
                    .accessibilityLabel(ArtistPageFacts.Words.plays(row.plays))
            }
        }
        .opacity(plays(row.song) ? 1 : DWPalette.off)
    }

    /// A top song's cover: its album's, for one you have.
    private static func cover(_ row: TopSongs.Row) -> String? {
        guard case .have(_, let album) = row.kind else { return nil }
        return album.coverArt
    }

    /// A song's cover at the rows' size, square and blank for a song you don't have.
    private func songCover(_ id: String?) -> some View {
        LibraryCover(id: id, pixels: CoverSize.row)
            .frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))
            .clipShape(DWCorners.chipShape)
            .accessibilityHidden(true)
    }

    /// The foot line, for whoever runs deadwax while Last.fm is off or refused - and Server settings, to its Connections.
    private func lastfmFoot(_ words: String) -> some View {
        MacLastfmFoot(words: words)
            .padding(.horizontal, Drawn.side)
            .padding(.bottom, Drawn.below)
    }

    // MARK: the discography (561)

    /// "Albums", the table - its header and rows lines of the page's lazy stack, the last row's rule its foot - and
    /// MusicBrainz's word under it.
    @ViewBuilder private var discography: some View {
        let rows = desk.rows
        if !rows.isEmpty || desk.theirs != nil { albumsHead }
        if !rows.isEmpty {
            MacColumnList(columns: Self.columns, rows: rows, controls: [Self.buttonsColumn],
                          voice: { (row: ArtistJoin.Row) -> MacRowVoice in voice(row) }, flow: flow(.discography),
                          selected: $selected,
                          open: { (row: ArtistJoin.Row) -> Void in open(row) },
                          menu: { (row: ArtistJoin.Row) -> DiscographyRightClick in
                              DiscographyRightClick(route: Self.route(row))
                          }
            ) { (row: ArtistJoin.Row, column: Int) in
                cell(row, column)
            }
        }
        if let theirs = desk.theirs {
            ArtistTheirFoot(theirs: theirs, holding: desk.holding, rows: rows.count, font: Typeface.Mac.text(.base),
                            again: desk.theirsAgain)
                .padding(.horizontal, Drawn.side)
                .padding(.bottom, Drawn.below)
        } else if !rows.isEmpty {
            below
        }
    }

    /// "Albums" over the discography (R6's review), as the phone's Albums heading - and (A2) at its end the albums'
    /// order: a pop-up showing the order drawn, the phone's items in it, "Sort albums" to VoiceOver and the pointer.
    private var albumsHead: some View {
        sectionHead(ArtistWords.albumsHeading) {
            DWPopUp(words: desk.albumOrder.shown.words, size: .small) {
                AlbumOrderItems(choice: desk.albumOrder)
            }
            .help(LastfmWords.sortAlbums)
            .accessibilityLabel(LastfmWords.sortAlbums)
            .accessibilityValue(desk.albumOrder.shown.words)
            .albumOrderRoom(desk.albumOrder)
        }
    }

    // MARK: Similar Artists (Last.fm, slice A2)

    /// Similar Artists: its heading with See All past four, one row of the phone's tiles in the Mac's faces - a trackpad
    /// scrolls it sideways, and four are in view at the narrowest page - its room held, blank, until the tiles are drawn;
    /// "From Last.fm" under it.
    @ViewBuilder private var similarArtists: some View {
        let similar = desk.similar
        let side = CGFloat(SimilarArtists.gridMin)
        sectionHead(LastfmWords.similarArtists) {
            if similar.seesAll {
                Button(LastfmWords.seeAll, action: desk.seeAllSimilar)
                    .buttonStyle(DWButtonStyle(size: .small))
            }
        }
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: MacSimilarDrawn.gap) {
                if similar.drawn {
                    ForEach(similar.tiles) { (tile: SimilarArtists.Tile) in
                        SimilarArtistTile(tile: tile, side: side, name: MacSimilarDrawn.name, line: MacSimilarDrawn.line) {
                            desk.openSimilar(tile)
                        }
                    }
                } else {
                    SimilarArtistTile.room(side: side, lines: 1, name: MacSimilarDrawn.name, line: MacSimilarDrawn.line)
                }
            }
            .padding(.horizontal, Drawn.side)
        }
        LastfmCredit(lastfmPage: desk.model.lastfm?.url, font: Typeface.Mac.text(.small), above: Drawn.headBelow)
            .padding(.horizontal, Drawn.side)
            .padding(.bottom, Drawn.below)
    }

    /// (R6's review) A row as VoiceOver reads it: one element, its cells' words in order (ArtistPageFacts.spoken), its
    /// buttons its actions in their own words - Play and Open an album of yours, Get (or Open) one of theirs - each only
    /// as its button is drawn and does something; none while its album is asked for, or dimmed.
    private func voice(_ row: ArtistJoin.Row) -> MacRowVoice {
        var actions: [MacRowAction] = []
        let format: String
        switch row {
        case .yours(let mine):
            format = ArtistPageFacts.format(desk.model.asks.ready[mine.albumId])
            if !dimmed(row) {
                if desk.playsAlbum(mine.albumId) {
                    actions.append(MacRowAction(words: ArtistPageFacts.Words.play) { desk.playAlbum(mine.albumId) })
                }
                actions.append(MacRowAction(words: ArtistPageFacts.Words.open) { open(row) })
            }
        case .theirs(let other):
            format = ""
            if desk.theirs?.opening != other.key {
                let get = ArtistPageFacts.offersGet(other, mayGet: desk.mayGet)
                actions.append(MacRowAction(words: get ? ArtistPageFacts.Words.get : ArtistPageFacts.Words.open) {
                    open(row)
                })
            }
        }
        // (A2) in Most played order its plays last, as the cell draws them
        let spoken = ArtistPageFacts.spoken(row, personal: desk.personal, format: format)
        let label = desk.plays[row.key].map { (plays: String) -> String in "\(spoken), \(plays)" } ?? spoken
        return MacRowVoice(label: label, actions: actions)
    }

    /// An album of yours as a right-click opens its page's •••; nil for one of theirs.
    private static func route(_ row: ArtistJoin.Row) -> AlbumRoute? {
        guard case .yours(let mine) = row else { return nil }
        return AlbumRoute(id: mine.albumId, name: mine.title, coverArt: mine.coverArt)
    }

    /// An album of yours with nothing on this Mac while deadwax can't be reached: dimmed, doing nothing.
    private func dimmed(_ row: ArtistJoin.Row) -> Bool {
        guard case .yours(let mine) = row else { return false }
        return !desk.online && !downloads.album(id: mine.albumId).hasSongsHere
    }

    /// A row opened - a double-click, Return, VoiceOver's action, its Open: its album's page, or the album you don't have.
    private func open(_ row: ArtistJoin.Row) {
        guard !dimmed(row) else { return }
        switch row {
        case .yours(let mine): desk.open(mine)
        case .theirs(let other): desk.openTheirs(other)
        }
    }

    @ViewBuilder
    private func cell(_ row: ArtistJoin.Row, _ column: Int) -> some View {
        Group {
            switch column {
            case 0:
                HStack(spacing: 8) {
                    cover(row)
                        .frame(width: CGFloat(rowSize.cover), height: CGFloat(rowSize.cover))
                        .clipShape(DWCorners.chipShape)
                        .accessibilityHidden(true)
                    Text(ArtistPageFacts.title(row))
                        .help(ArtistPageFacts.title(row))
                }
            case 1:
                Text(ArtistPageFacts.year(row))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            case 2:
                Text(songs(row))
                    .font(Typeface.Mac.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            case 3:
                // (A2) in Most played order, its plays at the cell's end - kept whole while the format gives way
                if let plays = desk.plays[row.key] {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        held(row)
                        Text(plays)
                            .font(Typeface.Mac.mono(.small))
                            .foregroundStyle(DWPalette.t2)
                            .layoutPriority(1)
                            .help(plays)
                    }
                } else {
                    held(row)
                }
            default:
                buttons(row)
            }
        }
        .opacity(dimmed(row) ? DWPalette.off : 1)
    }

    @ViewBuilder private func cover(_ row: ArtistJoin.Row) -> some View {
        switch row {
        case .yours(let mine):
            LibraryCover(id: mine.coverArt, pixels: CoverSize.row)
        case .theirs(let other):
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: other.group.id),
                         size: ArchiveCoverSize.row)
        }
    }

    /// Songs: an album of yours as Navidrome counts it; nothing for one of theirs (MusicBrainz's group carries none).
    private func songs(_ row: ArtistJoin.Row) -> String {
        guard case .yours(let mine) = row else { return "" }
        let album = desk.model.answer?.album.first { (album: Album) -> Bool in album.id == mine.albumId }
        return ArtistTotals.number(album?.songCount)
    }

    /// In your library: whose it is in a chip, with its format (its songs in hand) or its pressings - or "not in your
    /// library" for one nobody holds, nothing while the library hasn't said.
    @ViewBuilder private func held(_ row: ArtistJoin.Row) -> some View {
        switch row {
        case .yours(let mine):
            let format = ArtistPageFacts.format(desk.model.asks.ready[mine.albumId])
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                DWChip(words: Whose.heldLabel(personal: desk.personal, yours: mine.yours),
                       tone: ArtistPage.marked(mine, personal: desk.personal) ? .good : .plain)
                Text(format)
                    .font(Typeface.Mac.mono(.label))
                    .foregroundStyle(DWPalette.t3)
                    .help(format)
            }
        case .theirs(let other):
            if other.held == true {
                let pressings = ArtistPageFacts.pressings(other)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    DWChip(words: Whose.heldLabel(personal: desk.personal, yours: other.yours),
                           tone: MBArtistPage.marked(other, personal: desk.personal) ? .good : .plain)
                    Text(pressings)
                        .font(Typeface.Mac.text(.small))
                        .foregroundStyle(DWPalette.t3)
                }
            } else if other.held == false {
                Text(ArtistPageFacts.Words.notInYourLibrary)
                    .foregroundStyle(DWPalette.t3)
            }
        }
    }

    /// The row's buttons: Play and Open for an album you have; Get for one nobody holds, Open for one of theirs the
    /// library holds - the spinner while the id bridge is asked for it.
    @ViewBuilder private func buttons(_ row: ArtistJoin.Row) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            switch row {
            case .yours(let mine):
                Button {
                    desk.playAlbum(mine.albumId)
                } label: {
                    HStack(spacing: 4) {
                        SharpSymbol(.play)
                        Text(ArtistPageFacts.Words.play)
                    }
                }
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(!desk.playsAlbum(mine.albumId))
                .accessibilityLabel(ArtistPageFacts.Words.playLabel(mine.title))
                Button(ArtistPageFacts.Words.open) { open(row) }
                    .buttonStyle(DWButtonStyle(size: .small))
                    .accessibilityLabel(ArtistPageFacts.Words.openLabel(mine.title))
            case .theirs(let other):
                if desk.theirs?.opening == other.key {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(SearchWords.loading)
                } else if ArtistPageFacts.offersGet(other, mayGet: desk.mayGet) {
                    Button(ArtistPageFacts.Words.get) { open(row) }
                        .buttonStyle(DWButtonStyle(kind: .on, size: .small))
                        .accessibilityLabel(ArtistPageFacts.Words.getLabel(other.title))
                } else {
                    Button(ArtistPageFacts.Words.open) { open(row) }
                        .buttonStyle(DWButtonStyle(size: .small))
                        .accessibilityLabel(ArtistPageFacts.Words.openLabel(other.title))
                }
            }
        }
        .disabled(dimmed(row))
    }
}

/// (Last.fm, slice A2) Similar Artists' row on the Mac: 16 between tiles, as the Artists grid's; the name in the
/// window's words, semibold, the line in the small ones (the Artists grid's faces).
private enum MacSimilarDrawn {
    static let gap: CGFloat = 16
    static let name = Typeface.Mac.text(.base).weight(.semibold)
    static let line = Typeface.Mac.text(.small)
}

/// (R6) A discography row's right-click (MacColumnList's `menu`): an album of yours its page's ••• (AlbumRightClick, as
/// a tile's); nothing for one of theirs.
struct DiscographyRightClick: ViewModifier {
    let route: AlbumRoute?

    @ViewBuilder func body(content: Content) -> some View {
        if let route {
            content.modifier(AlbumRightClick(route: route))
        } else {
            content
        }
    }
}

/// (R6) A top song as Top Songs' list holds it (MacColumnList's rows are keyed by text): its rank, and - for one you
/// have - its •••'s request.
private struct TopLine: Identifiable {
    let row: TopSongs.Row
    var id: String { "top:\(row.rank)" }
    var menu: QueueMenuRequest? {
        guard case .have(let song, let album) = row.kind else { return nil }
        return QueueMenuRequest(pick: QueuePick.song(song, of: album), album: album)
    }
}

/// (R6) A top song's right-click: the song's ••• for one you have (SongRightClick), nothing for the rest.
struct SongRightClickIfHeld: ViewModifier {
    let menu: QueueMenuRequest?

    @ViewBuilder func body(content: Content) -> some View {
        if let menu {
            content.modifier(SongRightClick(menu: menu))
        } else {
            content
        }
    }
}

/// (R6) The foot line on the Mac, for whoever runs deadwax while Last.fm is off or refused - and Server settings, to
/// its Connections, where LASTFM_API_KEY is.
private struct MacLastfmFoot: View {
    let words: String

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(words)
                .font(Typeface.Mac.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
            Button(LastfmWords.serverSettings) {
                navigation.open(.serverSettingsGroup(ServerSettings.connectionsGroup))
            }
            .buttonStyle(DWButtonStyle(size: .small))
        }
    }
}
