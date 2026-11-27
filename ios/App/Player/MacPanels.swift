import DeadwaxCore
import SwiftUI

/// The desktop frame's side panel (the Mac app, slice 3 - the Mac app's plan 1.2; the web's app/SidePanel.tsx) - since
/// the Mac redesign's R3 (notes/ios.md "The redesign, slice R3: the side panel's tabs; the Now Playing sheet") a dock
/// of folder tabs (MacFolderTabs, dw.css's .tabs): Queue, Lyrics, Info and EQ, and Sources while a Get page is open,
/// one at a time (AppNavigation.macPanel, MacDock.toggled) - the bar's Lyrics and Queue, the •••'s Info and EQ, View's
/// four (⌥⌘U, ⌥⌘L, ⌘I, ⌥⌘E) and a tab clicked open and switch it. MacLook.panelWidth (400) wide: a column of its own
/// beside the page in a window 1280 wide or more, a drawer over the page's right edge below that (MacFrame.panelStyle).
/// Never modal: the page, the sidebar and the bar take their clicks while it shows.
///
/// Each tab's page: the Queue (UpNextScreen), Lyrics (LyricsPanel), Info about the row selected on the page in front,
/// else the song playing (DockInfo), the EQ the EQ page of the output now on the dock's own stack (DockEQ), a shared
/// file's preview over it, and Sources (R7's) the Get the album you don't have asked for (MacSourcesTab). (R3's review) A
/// tab with nothing to be about - the Queue with nothing queued, Info with nothing selected and nothing playing - says
/// "Nothing playing" in its page's place (MacDock.empty, DockEmpty).
///
/// (The panel review's R16 - notes/ios.md "The panel review, R16: the Mac's dock tabs (2026-11-26)"; James, 26 Nov:
/// "on mac, if i go to "info" next to the play bar, everything is still rounded") No tab's page has a system bar, a
/// title or a Done: it starts right under the folder tabs, its own controls in a DockHeader, a page pushed inside it
/// with DockBack in place of the system's back. The panel closes with Escape - this view's own key (DockEscapeKey),
/// through MacFrame.escape, the main window's one owner, as DockDone's key had it - with the tab's View key, or a click
/// on the open tab. A page that has an Escape of its own for now says so (`dockHoldsEscape`), and the panel's key stands
/// aside while it does: the Queue's Done in Edit, and Sources' Close until R19 makes it the dock's.
struct MacPanel: View {
    let tab: MacDock.Tab

    @Environment(AppNavigation.self) private var navigation
    @Environment(PlayerModel.self) private var player
    @Environment(MacSelection.self) private var selection: MacSelection?
    /// (R16) The pages in it holding Escape for now.
    @State private var holds = DockEscapeHolds()

    var body: some View {
        VStack(spacing: 0) {
            MacFolderTabs(tabs: MacDock.tabs(getOpen: navigation.macGetOpen), words: MacDock.Words.tab,
                          chosen: Binding(get: { tab }, set: { (chosen: MacDock.Tab) -> Void in navigation.showPanel(chosen) }),
                          spoken: MacDock.Words.spoken)
            //? one tab's page at a time, and only the one showing: the tab chosen is the page drawn - or its words, with
            //? nothing for it to be about
            Group {
                if let words = MacDock.empty(tab, playing: player.current != nil, selected: selection?.subject != nil) {
                    DockEmpty(words: words)
                } else {
                    page
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        //? (R16) Escape: the panel put away, unless a page in it holds its own for now
        .background { DockEscapeKey(held: holds.any) }
        .environment(holds)
        .environment(\.inSidePanel, true)
        .frame(width: CGFloat(MacLook.panelWidth))
        .frame(maxHeight: .infinity)
        .background(DWPalette.panel)
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .upNext:
            UpNextScreen()
        case .lyrics:
            LyricsPanel()
        case .info:
            DockInfo()
        case .eq:
            DockEQ()
        case .sources:
            //? (R7) the Get the album you don't have asked for on the Mac, beside its page - (R16) its Close Escape's
            //? own until R19 draws it in a DockHeader
            MacSourcesTab()
                .dockHoldsEscape()
        }
    }
}

/// (R16) The panel's Escape: a button the dock holds but never shows (none of its own words, nothing to see, nothing
/// VoiceOver reads, never a Tab stop - RowSizeAlternateKey's way), pressed by Escape whenever MacFrame.escape says
/// Escape is the panel's - after a field with the cursor, before the page's own (a playlist's Edit) - and no page in
/// the dock holds Escape itself. The panel put away, as DockDone did.
private struct DockEscapeKey: View {
    let held: Bool

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button(action: { navigation.closePanel() }) {
            DWPalette.panel
        }
        .escapeCloses(!held && MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == .panel)
        .focusable(false)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// (R16) The pages in the dock holding Escape themselves for now (`dockHoldsEscape`), each by its own token: handed down
/// the dock in the environment - never a preference, which a NavigationStack between the page and the dock may not pass
/// up - and let go as a page goes.
@MainActor @Observable
final class DockEscapeHolds {
    private var holders: Set<UUID> = []

    /// Some page holds Escape: the panel's key stands aside.
    var any: Bool { !holders.isEmpty }

    func hold(_ holder: UUID, _ held: Bool) {
        if held { holders.insert(holder) } else { holders.remove(holder) }
    }
}

private struct DockHoldsEscape: ViewModifier {
    let held: Bool

    @Environment(DockEscapeHolds.self) private var holds: DockEscapeHolds?
    @State private var holder = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { holds?.hold(holder, held) }
            .onChange(of: held) { (_: Bool, now: Bool) -> Void in holds?.hold(holder, now) }
            .onDisappear { holds?.hold(holder, false) }
    }
}

/// (R3's review) A tab with nothing to be about (MacDock.empty): its words - Lyrics' own "Nothing playing" (LyricsPanel's
/// note) - quiet and centred, so it is never a blank page. (R16) In the dock's own type, under the folder tabs that name
/// it: no title of its own, no Done.
private struct DockEmpty: View {
    let words: String

    var body: some View {
        Text(words)
            .font(DockType.words)
            .foregroundStyle(DWPalette.t3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DockLook.side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EnvironmentValues {
    /// (The Mac app, slice 3) A page drawn in the desktop frame's side panel: its Done puts the panel away
    /// (AppNavigation.closePanel). False everywhere else, where Done dismisses its sheet as before.
    @Entry var inSidePanel = false
}

/// (R3) The dock's Done - (R16) left only on the pages the EQ pushes on its stack (EQDoneButton), which keep the system's
/// bar until R17 gives them DockBack: the panel put away. No key of its own now: Escape is the panel's (DockEscapeKey).
struct DockDone: View {
    let words: String

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button(words) { navigation.closePanel() }
    }
}

// MARK: the dock's pieces (R16)

/// (R16) The dock's type, in the Mac's sizes (dw.css's, Typeface.Mac) - named here so that the dock's pages drawn in
/// files both devices share (InfoView, AlbumInfoView, UpNextScreen, LyricsView) draw their Mac halves in it without
/// naming the Mac's own type there.
enum DockType {
    /// An album's or an artist's name beside its picture (18, bold - the drawings' 18/700).
    static var title: Font { Typeface.Mac.text(.h3).weight(.bold) }
    /// The window's words (13): a row's title, a line of lyrics, the artist in the accent.
    static var words: Font { Typeface.Mac.text(.base) }
    /// .btn's 12.5: a way back.
    static var control: Font { Typeface.Mac.text(.control) }
    /// .s (12): a fact's label, a line under a name.
    static var small: Font { Typeface.Mac.text(.small) }
    /// .xs (11.5): a note.
    static var label: Font { Typeface.Mac.text(.label) }
    /// .navh and a group's legend (11.5, semibold).
    static var heading: Font { Typeface.Mac.text(.label).weight(.semibold) }
    /// .mono.xs (Courier Prime, 11.5): a fact that is a number, a time, a path or a format.
    static var readout: Font { Typeface.Mac.mono(.label) }
    /// .mono.s (Courier Prime, 12): a song's length, a lyric's time.
    static var smallReadout: Font { Typeface.Mac.mono(.small) }
}

/// (R16) The dock's sizes, each a drawing's: Albums.dc.html's and Artists.dc.html's panels (16 in, 14 between, the
/// cover 112, the artist 96), Album.dc.html's header (10 above, 12 in, 2 below, 6 between) and its rows (8 in from the
/// panel's sides, the song playing 44 tall with a 30 cover), `.kv`'s label (84) and Playlist.dc.html's header (12 above,
/// 14 in, 10 below).
enum DockLook {
    static let side: CGFloat = 16
    static let gap: CGFloat = 14
    static let cover: CGFloat = 112
    static let picture: CGFloat = 96
    static let headerTop: CGFloat = 10
    static let headerSide: CGFloat = 12
    static let headerFoot: CGFloat = 2
    static let headerGap: CGFloat = 6
    static let rowInset: CGFloat = 8
    static let rowSide: CGFloat = 10
    static let playingRow: CGFloat = 44
    static let playingCover: CGFloat = 30
    static let factLabel: CGFloat = 76
    static let factGap: CGFloat = 8
    static let factRows: CGFloat = 5
    static let lyricsHeader = EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)
    static let lengthWidth: CGFloat = 58
    static let numberWidth: CGFloat = 36
}

/// (R16) DockHeader - the row at the top of a dock tab's page holding that tab's own controls (Album.dc.html's panel:
/// the Queue's Shuffle, Repeat, History and Clear): `leading` at the left, `trailing` at the right, 6 apart, 10 under
/// the folder tabs and 12 in from the panel's sides. Every Button in it is a `.btn.sm` (DWButtonStyle(size: .small) is
/// the row's style); one may take its own kind - `DWButtonStyle(kind: .on, size: .small)` for a toggle that is on - or
/// its own style altogether. It draws no ground: the panel's shows through.
///
///     DockHeader {
///         Button(UpNextWords.shuffle, action: toggleShuffle)
///     } trailing: {
///         Button(SourcesWords.again) { search() }
///     }
///
/// `DockHeader { … }` alone puts its controls at the left; `DockHeader(trailing: { … })` at the right. A header that
/// may not fit the panel's 400 at its widest is the caller's to fold (ViewThatFits over two DockHeaders, the lesser
/// controls in a ••• in the second - the Queue's).
struct DockHeader<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DockLook.headerGap) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .buttonStyle(DWButtonStyle(size: .small))
        .padding(EdgeInsets(top: DockLook.headerTop, leading: DockLook.headerSide, bottom: DockLook.headerFoot,
                            trailing: DockLook.headerSide))
        .frame(maxWidth: .infinity)
    }
}

extension DockHeader where Trailing == EmptyView {
    init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading, trailing: { EmptyView() })
    }
}

extension DockHeader where Leading == EmptyView {
    init(@ViewBuilder trailing: () -> Trailing) {
        self.init(leading: { EmptyView() }, trailing: trailing)
    }
}

/// (R16) DockBack - a page pushed inside a dock tab's stack goes back with `‹ <where you came from>` in the accent's
/// words, never the system's back: "‹ Info" over Info's Album info, "‹ EQ" over an EQ page (R17's). Read as iOS reads
/// its own back button ("Info, Back", MacDock.Words.back). Drawn for a pushed page by `.dockBack(words)`, which hides
/// the stack's bar on that page and puts this at its top, its click the page's own dismiss (the stack popped).
struct DockBack: View {
    /// The page it goes back to ("Info").
    let words: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(Image(systemName: "chevron.left")) \(words)")
                .font(DockType.control.weight(.medium))
                .foregroundStyle(DWPalette.acc)
                .lineLimit(1)
                .frame(height: CGFloat(DWLook.here.buttonHeight))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(MacDock.Words.back(to: words))
        .accessibilityLabel(MacDock.Words.back(to: words))
    }
}

extension View {
    /// (R16) A page pushed on a dock tab's stack: the stack's bar hidden on it, and DockBack (`‹ words`) in a row at its
    /// top, a click going back - the page's own dismiss. `words` nil: nothing changes, so a page both devices push says
    /// `.dockBack(inSidePanel ? InfoWords.title : nil)` and keeps the system's bar and Back on the phone.
    func dockBack(_ words: String?) -> some View {
        modifier(DockBackTop(words: words))
    }

    /// (R16) This page in the dock holds Escape itself while `held` - a Done of its own pressed by it (the Queue's in
    /// Edit), a Close (Sources', until R19) - so the panel's own key stands aside: never two buttons for one key.
    func dockHoldsEscape(_ held: Bool = true) -> some View {
        modifier(DockHoldsEscape(held: held))
    }

    /// (R16) A row of a List in a dock tab (Album.dc.html's panel's `.list .row`): on the panel's ground, 8 in from its
    /// sides, its own rowline under it (none for a heading, a note or the song playing: `rule: false`), and none of the
    /// List's separators or insets.
    func dockListRow(rule: Bool = true) -> some View {
        modifier(DockListRow(rule: rule))
    }

    /// (R16) As tall as View ▸ Row Size's rows (30, 40 or 52 - MacRowSize), exactly: a dock row's words, never two lines.
    func dockRowHeight() -> some View {
        modifier(DockRowHeight())
    }
}

private struct DockBackTop: ViewModifier {
    let words: String?

    @Environment(\.dismiss) private var dismiss

    @ViewBuilder func body(content: Content) -> some View {
        if let words {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack(spacing: 0) {
                        DockBack(words: words) { dismiss() }
                        Spacer(minLength: 0)
                    }
                    .padding(EdgeInsets(top: DockLook.headerTop, leading: DockLook.headerSide,
                                        bottom: DockLook.headerFoot, trailing: DockLook.headerSide))
                    .background(DWPalette.panel)
                }
        } else {
            content
        }
    }
}

private struct DockListRow: ViewModifier {
    let rule: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if rule { DWRule(colour: DWPalette.rowline) }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DockLook.rowInset, bottom: 0, trailing: DockLook.rowInset))
            .listRowSeparator(.hidden)
            .listRowBackground(DWPalette.panel)
    }
}

private struct DockRowHeight: ViewModifier {
    @Environment(\.macRowSize) private var rowSize

    func body(content: Content) -> some View {
        content.frame(height: CGFloat(rowSize.rowHeight))
    }
}

/// (R16) A `.group` in a dock tab (dw.css's: a legend over a box of rows - MacGroupBox), its rows 5 apart, with the 8 of
/// room above it its legend stands in.
struct DockGroup<Content: View>: View {
    let legend: String
    @ViewBuilder let content: Content

    var body: some View {
        MacGroupBox(legend: legend) {
            VStack(alignment: .leading, spacing: DockLook.factRows) {
                content
            }
        }
        .padding(.top, DockLook.factGap)
    }
}

/// (R16) A fact in a dock tab's group (`.kv`, Albums.dc.html's Properties): its label in the second colour, 84 wide
/// (wrapping inside that), its value beside it on the label's baseline - in Courier Prime where it is a number, a time,
/// a path or a format (`mono`), selectable, to copy - and an optional note under the value. Every line wraps: nothing
/// is cut short. One element for VoiceOver: the label, the value, the note.
struct DockFact: View {
    let label: String
    let value: String
    var mono = false
    var note: String? = nil
    var noteMono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DockLook.factGap) {
            Text(label)
                .font(DockType.small)
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: DockLook.factLabel, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(mono ? DockType.readout : DockType.small)
                    .foregroundStyle(DWPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let note, !note.isEmpty {
                    Text(note)
                        .font(noteMono ? DockType.readout : DockType.label)
                        .foregroundStyle(DWPalette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// (R16) A song of an album in a dock tab's box (Albums.dc.html's panel's tracklist): its number and its length in
/// Courier Prime, its title between them on one line - cut short with its whole in `.help` - on its first baseline
/// (Courier Prime's line is shorter than Libre Franklin's: centred, it would sit higher), as tall as View ▸ Row Size's
/// rows, its rowline under it. One element for VoiceOver.
struct DockSongRow: View {
    let number: String
    let title: String
    let length: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(number)
                .font(DockType.smallReadout)
                .foregroundStyle(DWPalette.t2)
                .frame(width: DockLook.numberWidth, alignment: .leading)
            Text(title)
                .font(DockType.words)
                .foregroundStyle(DWPalette.head)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(title)
            Text(length)
                .font(DockType.smallReadout)
                .foregroundStyle(DWPalette.t2)
                .frame(width: DockLook.lengthWidth, alignment: .trailing)
        }
        .padding(.horizontal, DockLook.rowSide)
        .dockRowHeight()
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowline) }
        .accessibilityElement(children: .combine)
    }
}

/// (R16) A song's row in the dock's Queue (Album.dc.html's panel's list): its title in the heading's colour and its line
/// ("Artist · Album") in the second colour - under the title where View ▸ Row Size leaves room for two lines (Medium and
/// Large), after it on the one line where it doesn't (Small), each cut short with the whole in `.help` - then its mark
/// (the caller's: the song's download) and its length in Courier Prime at the right, 58 wide - on the title's baseline
/// beside one line, centred on two (iQueue's rule); as tall as Row Size's rows.
struct DockQueueRow<Mark: View>: View {
    let title: String
    /// "" for none (an album's rows under its heading are their titles).
    let line: String
    let length: String
    @ViewBuilder let mark: Mark

    @Environment(\.macRowSize) private var rowSize

    var body: some View {
        let two = !line.isEmpty && rowSize != .small
        HStack(alignment: two ? .center : .firstTextBaseline, spacing: DockLook.factGap) {
            Group {
                if two {
                    VStack(alignment: .leading, spacing: 1) {
                        titleText
                        lineText
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: DockLook.headerGap) {
                        titleText
                            .layoutPriority(1)
                        if !line.isEmpty { lineText }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            mark
            Text(length)
                .font(DockType.smallReadout)
                .foregroundStyle(DWPalette.t2)
                .frame(width: DockLook.lengthWidth, alignment: .trailing)
        }
        .padding(.horizontal, DockLook.rowSide)
        .dockRowHeight()
        .contentShape(Rectangle())
    }

    private var titleText: some View {
        Text(title)
            .font(DockType.words)
            .foregroundStyle(DWPalette.head)
            .lineLimit(1)
            .help(title)
    }

    private var lineText: some View {
        Text(line)
            .font(DockType.small)
            .foregroundStyle(DWPalette.t2)
            .lineLimit(1)
            .help(line)
    }
}

// MARK: the tabs

/// (R3) The dock's Info (James, 24 Nov, section 7's answer 2: "Selection, else playing"): about the row selected on the
/// page in front - an album's Album info, an artist's - else the song playing's Info (InfoView), its heading saying
/// which (MacDock.infoSubject, MacDock.Words.heading). The selection is MacSelection's, the page in front's alone (R2's
/// lists say theirs), so a row on a page gone from the screen is never what it shows.
private struct DockInfo: View {
    @Environment(PlayerModel.self) private var player
    @Environment(MacSelection.self) private var selection: MacSelection?

    var body: some View {
        let selected = selection?.subject
        let subject = MacDock.infoSubject(selected: selected.map(Self.kind), playing: player.current != nil)
        VStack(spacing: 0) {
            if let heading = MacDock.Words.heading(subject) {
                // .navh: the heading the dock's pages draw over what they hold
                Text(heading)
                    .font(DockType.heading)
                    .foregroundStyle(DWPalette.label)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DockLook.headerSide)
                    .padding(.top, DockLook.headerTop)
                    .accessibilityAddTraits(.isHeader)
            }
            switch selected {
            case .album(let album)?:
                DockAlbumInfo(album: album)
                    .id(album.id)
            case .artist(let artist)?:
                DockArtistInfo(artist: artist)
                    .id(artist.id)
            case nil:
                InfoView()
            }
        }
    }

    private static func kind(_ subject: MacSelection.Subject) -> MacDock.Selected {
        switch subject {
        case .album: return .album
        case .artist: return .artist
        }
    }
}

/// The album selected: its Album info (AlbumInfoList) - (R16) Albums.dc.html's panel, its Play, Shuffle, Add to Queue
/// and Edit among it - from what its row knew: a stub, so its own lines wait for the album's answer, which it asks
/// itself.
private struct DockAlbumInfo: View {
    let album: AlbumRoute

    var body: some View {
        AlbumInfoList(album: Album(id: album.id, name: album.name, artist: album.artist, artistId: album.artistId,
                                   coverArt: album.coverArt, year: album.year, genre: album.genre,
                                   musicBrainzId: album.musicBrainzId, partial: true))
    }
}

/// The artist selected (R16: Artists.dc.html's panel): their round picture (96), their name (18, bold), their albums'
/// count where Navidrome counts them, Go to artist (the drawing's Open artist) at the right - and A4's About under them,
/// the very words the artist page draws (AboutModel, AboutBlock's question from what the row knows: Navidrome's id and
/// its MusicBrainz id, the session's answer drawn at once when the page asked it). The drawing's Play and Shuffle are
/// left out: the row holds none of the artist's songs, and a play is never made with an answer awaited. Its chips ("3 in
/// your library") are the artist page's counts, which the row hasn't either.
private struct DockArtistInfo: View {
    let artist: ArtistRoute

    @Environment(AppNavigation.self) private var navigation
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @State private var about = AboutModel()

    var body: some View {
        let name = artist.preview?.name ?? ""
        let count = ArtistWords.albumCountLine(artist.preview?.albumCount, place: "")
        ScrollView {
            VStack(alignment: .leading, spacing: DockLook.gap) {
                HStack(alignment: .top, spacing: DockLook.gap) {
                    ArtistPicture(id: artist.preview?.coverArt, side: DockLook.picture, pixels: CoverSize.tile)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(DockType.title)
                            .foregroundStyle(DWPalette.text)
                            .lineLimit(2)
                            .help(name)
                        if !count.isEmpty {
                            Text(count)
                                .font(DockType.small)
                                .foregroundStyle(DWPalette.t2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: DockLook.headerGap) {
                    Spacer(minLength: 0)
                    Button(MacDock.Words.goToArtist) { navigation.open(.artist(artist)) }
                        .buttonStyle(DWButtonStyle())
                }
                if let drawn = about.drawn(for: page) {
                    AboutBlockView(drawn: drawn, faces: Self.faces) { (words: AboutWordsElement) in
                        words
                    }
                }
            }
            .padding(DockLook.side)
        }
        .task(id: "\(page)|\(question.token)|\(reachability.online)") {
            about.ask(page: page, person: server.person, question: question, client: server.client,
                      online: reachability.online)
        }
    }

    /// What About is asked for: the artist the row is - their name is in hand, so their answer is.
    private var question: AboutBlock.Question {
        AboutBlock.artist(answered: true, gone: false, navidromeId: artist.id, mbid: artist.preview?.musicBrainzId,
                          indexKnown: true, waited: true, factsSettled: true)
    }

    private var page: String { "dock|\(artist.id)" }

    /// About's faces in the dock: the subtitle and the link small (12), the paragraph the window's words (13), the
    /// panel's own width.
    private static let faces = AboutFaces(subtitle: DockType.small, words: DockType.words, credit: DockType.small,
                                          gap: AboutDrawn.gap, target: 0, measure: nil)
}

/// (R3) The EQ in the dock (check 535): the EQ page of the output now, on the dock's own stack (EQSheetStack, as the
/// sheet's), its pages pushed on it. (R3's review) The Mac's one EQ: a file shared to deadwax, dropped on the window or
/// chosen in File > Import EQ File… shows this tab (SharedEQFile) and its preview comes up over it as the EQ sheet's did -
/// once the tab has been up a moment (one presented as it is drawn isn't shown), over the page as it stands, Cancel's
/// answer if it is put away; Import… on the page keeps its own (EQImportRows). (R16) Its root's bar hidden, as every
/// tab's is: the pages pushed on it keep the system's bar, and DockDone, until R17 gives them DockBack.
private struct DockEQ: View {
    @Environment(AppNavigation.self) private var navigation
    @State private var stack = EQSheetStack()
    /// Up long enough for a sheet over it (EQSheet's wait).
    @State private var ready = false

    var body: some View {
        NavigationStack(path: $stack.path) {
            EQScreen(opened: .now)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: EQRoute.self) { (route: EQRoute) in
                    EQDestination(route: route)
                }
        }
        .environment(stack)
        .appSheet(isPresented: Binding<Bool>(get: {
            ready && navigation.eqImport != nil && navigation.eqImportPage == nil
        }, set: { (up: Bool) -> Void in
            // put away: Cancel's answer
            if !up { navigation.importAnswered() }
        })) {
            EQImportSheetContent()
                .macSheet()
        }
        .task { () async -> Void in
            try? await Task.sleep(for: .milliseconds(400))
            ready = true
        }
    }
}

/// Lyrics in the side panel (the web's LyricsPanel.tsx): the song playing's lines, lit and followed as on Now Playing's
/// face (LyricsView, its rules Core's); the spinner while they are asked with none in hand; a failure in a listener's
/// words with Try again; "No lyrics for this song."; "Nothing playing" with nothing queued - the panel stays when the
/// queue ends, as the web's does (MacFrame.afterQueueEnds). Lyrics are on (LyricsModel.showing) while it shows, so the
/// song's are asked as it opens and the next song's ahead, and off again as it goes.
///
/// (R16; Playlist.dc.html's panel) No bar: a header with the song's title and artist, and the green "synced" chip while
/// its lines are synced - no Follow button, as the lines follow the song on their own (LyricsView) - over the lines, 40
/// tall with their times in Courier Prime, the lit one on the purple ground (LyricsView's `docked`). Try again is a
/// DW button.
struct LyricsPanel: View {
    @Environment(PlayerModel.self) private var player
    @Environment(LyricsModel.self) private var lyrics

    var body: some View {
        VStack(spacing: 0) {
            if let track = player.current?.track {
                header(track)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            lyrics.showing = true
            lyrics.opened()
        }
        .onDisappear { lyrics.showing = false }
    }

    /// The song's title and artist, cut short with their whole in `.help`, and "synced" while its lines are - one
    /// element for VoiceOver.
    private func header(_ track: QueueTrack) -> some View {
        let synced = lyrics.face == .synced && lyrics.shown?.synced == true
        return HStack(spacing: DockLook.factGap) {
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(DockType.words.weight(.semibold))
                    .foregroundStyle(DWPalette.text)
                    .lineLimit(1)
                    .help(track.title)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(DockType.small)
                        .foregroundStyle(DWPalette.t2)
                        .lineLimit(1)
                        .help(track.artist)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if synced {
                DWChip(words: MacDock.Words.synced, tone: .good)
            }
        }
        .padding(DockLook.lyricsHeader)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.line) }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        if let track = player.current?.track {
            switch lyrics.face {
            case .synced, .plain:
                if let shown = lyrics.shown {
                    // made afresh for each song: a new song's lines start at their top
                    LyricsView(lyrics: shown, covered: false, docked: true)
                        .id(track.id)
                }
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel(LyricsWords.loading)
            case .failed(let tryAgain):
                if let failure = lyrics.failure {
                    VStack(spacing: 12) {
                        ErrorNote(failure, gone: LyricsWords.songGone, failed: LyricsWords.failed, retry: true)
                        if tryAgain {
                            Button(LibraryWords.tryAgain) { lyrics.retry() }
                                .buttonStyle(DWButtonStyle())
                        }
                    }
                    .padding(.horizontal, DockLook.side)
                }
            case .cover:
                note(lyrics.have == .notKept ? LyricsWords.label(.notKept, device: Platform.device) : LyricsWords.noLyrics)
            }
        } else {
            note(LyricsWords.nothingPlaying)
        }
    }

    private func note(_ words: String) -> some View {
        Text(words)
            .font(DockType.words)
            .foregroundStyle(DWPalette.t3)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DockLook.side)
    }
}
