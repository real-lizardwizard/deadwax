import DeadwaxCore
import SwiftUI

/// Info (ui/src/app/InfoSheet.tsx, D8), for the song playing: on the phone a tab of Now Playing's sheet, in the Mac's
/// side panel the dock's Info tab.
///
/// About, for everyone: The song (its title, artist, "Track 4 of 10 · 7:05 · played 12 times", the disc line,
/// "Written by …"), The album (its cover, "1973 · Harvest · FLAC · 10 songs", "This pressing: …" - going to the
/// album when the queue knows its id), The artist (the name, Phase 1), Sound (Format, Gapless On, Normalization in
/// a listener's words, as the queue settled the entry's level), and last, for an admin, On the server - the
/// album's folder, to copy. Every line is Core's: AboutCard.about on the queue's entry and the album it was played
/// from, LevelWords.soundRows.
///
/// Debug, an admin's alone (InfoTab.tabs): The file, Sent to this device (Sent as, Normalization in Debug's words,
/// Gapless, then the engine's own rows, read again each second while it shows) and Fields from Navidrome, on the
/// album answer as Navidrome sent it - asked again only for an album the queue was played from, "Not known"
/// otherwise, as the web's is with no album in hand. A tab strip only where there is a choice; the role going
/// while Debug shows draws About, and coming back opens on About. Each tab opens at its top.
///
/// Phase 2 (phase2-downloads.md 4.4): Sound gains "Plays from" after the web's three rows - this phone, and how its copy
/// was checked, or streamed (what is heard: with Debug's "Stream even when downloaded" on, streamed) - and Debug's Sent
/// to this device gains "On this phone", the check and STREAMINFO's facts in Debug's words.
///
/// The EQ (eq.md 3.1, app 0.5): Sound gains "EQ" after Plays from while it is on - "Bass Boost on James's AirPods Pro,
/// preamp -6.1 dB" - and Debug's Sent to this device gains "EQ" after the engine's rows: what its unit does with the
/// sound now.
///
/// Album info (notes/ios.md "Album info"): The album gains an "Album info" row under its card while the queue knows the
/// album's id - everything known of the album, pushed here (AlbumInfoList, by value: AlbumInfoPush), its Back to Info
/// and Info's own Done. It stays on the album it was opened for when the song changes; Back is Info for the song playing.
///
/// (The redesign, slice R3b - notes/ios.md "The redesign, slice R3b: the Queue, Info and the EQ inside"; iInfo.dc.html)
/// On the phone, in the sheet (`sheet`), iInfo: the song's row (its cover, title, artist in the accent, "Album · Year"),
/// then This song and The album as groups of kv rows (AboutCard.facts - Played "19 times · today", the day only where the
/// song's answer has a date; Sound's rows in This song, its Format first), Album info the album's last row, and Go to
/// album and Go to artist under them. An admin's About or Debug is a segmented control under the song's row, the choice
/// the sheet's (`picked`), so the strip's taps keep it; Debug's sections are groups too.
///
/// (The panel review's R16 - notes/ios.md "The panel review, R16: the Mac's dock tabs (2026-11-26)"; Albums.dc.html's
/// panel, for a song) In the Mac's dock no bar, no title, no Done - Escape is the panel's (MacPanel): the song's cover
/// (112, a cover's corners) beside its title (18, bold), its artist in the accent, "Album · Year" and its facts in Courier
/// Prime ("FLAC 16/44.1 · 24 MB · 921 kbps"); an admin's About or Debug in the look's segmented control; About's Go to
/// album (the primary), Go to artist and Album info as a row of the look's buttons; then the same facts as the phone's
/// in `.group`s - Properties (the song's, Sound's, Plays from and the EQ), The album - each a `.kv` of DockFact, a
/// number, a time or a path in Courier Prime; Debug's sections as groups too. Album info is pushed with `‹ Info`
/// (DockBack) in the bar's place.
struct InfoView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(EQModel.self) private var eq
    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(AppNavigation.self) private var navigation
    /// (The Mac app, slice 3) Drawn in the desktop frame's side panel - (R16) Album info pushed with `‹ Info` there.
    @Environment(\.inSidePanel) private var inSidePanel
    @Environment(\.dynamicTypeSize) private var typeSize
    /// (R3b) In Now Playing's sheet: its top (`‹ Now Playing`, the strip) - nil in the Mac's side panel.
    private let sheet: SheetTop?
    /// (R3b) About or Debug, the sheet's when it hands one over (kept while another tab shows), else this page's own.
    private let handed: Binding<InfoTab>?
    @State private var own: InfoTab = .about
    @State private var said: InfoAsk.Said?
    @State private var raw: (albumID: String, answer: RawJSON?)?
    /// Debug's second hand: the engine's rows are read again as it moves.
    @State private var tick = 0
    /// (R3b) The day Played's words are said against: moved at midnight and whenever Info comes up.
    @State private var now = ArtistTotals.now()

    /// (R3b) The phone's: the song's row's cover (iInfo's 64), its gap, the page's sides, the room above the two ways on
    /// (18) and between them (8), and under the page (34, the drawing's foot).
    private static let songCover: CGFloat = 64
    private static let songGap: CGFloat = 12
    private static let side: CGFloat = 16
    private static let goesAbove: CGFloat = 18
    private static let goesGap: CGFloat = 8
    private static let foot: CGFloat = 34

    init(sheet: SheetTop? = nil, picked: Binding<InfoTab>? = nil) {
        self.sheet = sheet
        handed = picked
    }

    /// About or Debug, wherever it is kept.
    private var picked: Binding<InfoTab> { handed ?? $own }

    var body: some View {
        let admin = server.access.isAdmin
        let tabs = InfoTab.tabs(admin: admin)
        let tab = InfoTab.shown(picked.wrappedValue, admin: admin)
        NavigationStack {
            page(tabs: tabs, tab: tab, admin: admin)
                //? by value, on the stack's root rather than the List (drawn afresh for each song): the page stays on the
                //? album it was opened for when the song changes under it
                .navigationDestination(for: AlbumInfoPush.self) { push in
                    AlbumInfoList(album: push.album)
                        //? (R16) in the Mac's dock, `‹ Info` in the bar's place; the phone's bar and Back as they were
                        .dockBack(inSidePanel ? InfoWords.title : nil)
                }
        }
        .task(id: player.current?.track.id) { await askDetails() }
        .task(id: rawAsk(tab)) { await askRaw(tab) }
        .task(id: tab) { await ticking(tab) }
        .onChange(of: admin) { _, now in
            //? the role gone: About, and the Debug chosen before forgotten when it comes back
            if !now { picked.wrappedValue = .about }
        }
        //? (R3b) "today" moves at midnight, and with the clock or the zone changed
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = ArtistTotals.now()
        }
        .onAppear { now = ArtistTotals.now() }
    }

    /// The page: the phone's in the sheet, under its top; the Mac's in the side panel, with no bar (R16).
    @ViewBuilder
    private func page(tabs: [InfoTab], tab: InfoTab, admin: Bool) -> some View {
        if let sheet {
            phonePage(tabs: tabs, tab: tab, admin: admin)
                .sheetTop(sheet) {}
        } else {
            macPage(tabs: tabs, tab: tab, admin: admin)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: the phone's page (R3b)

    @ViewBuilder
    private func phonePage(tabs: [InfoTab], tab: InfoTab, admin: Bool) -> some View {
        if let entry = player.current {
            let facts = aboutFacts(entry, folders: admin)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    songRow(entry, facts: facts)
                    if tabs.count > 1 {
                        DWSegmented(options: tabs, words: { (each: InfoTab) -> String in each.label }, chosen: picked,
                                    spoken: InfoWords.title, large: true)
                            .padding(.top, Self.songGap)
                    }
                    switch tab {
                    case .about: phoneAbout(entry, facts: facts)
                    case .debug: phoneDebug(entry)
                    }
                }
                .padding(.horizontal, Self.side)
                .padding(.top, CGFloat(PhoneLook.topGap) / 2)
                .padding(.bottom, Self.foot)
            }
            .scrollContentBackground(.hidden)
            //? each tab, and each song, from its top
            .id("\(tab.rawValue)|\(entry.key)")
        } else {
            Spacer()
        }
    }

    /// The song's row (iInfo's top): its cover, its title, its artist in the accent and "Wilco (The Album) · 2009" -
    /// one element, as About's song card was; every line wraps, as they did.
    private func songRow(_ entry: QueueEntry, facts: AboutFacts) -> some View {
        let track = entry.track
        return HStack(spacing: Self.songGap) {
            CoverImage(id: track.coverArt, size: Self.songCover)
                .frame(width: Self.songCover, height: Self.songCover)
                .clipShape(Corners.artShape)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(Typeface.Phone.text(.row).weight(.semibold))
                    .foregroundStyle(DWPalette.text)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.acc)
                }
                if !facts.line.isEmpty {
                    Text(facts.line)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// iInfo's About: This song, The album, and the two ways on.
    @ViewBuilder
    private func phoneAbout(_ entry: QueueEntry, facts: AboutFacts) -> some View {
        let track = entry.track
        let song = player.song(for: entry) ?? Song(queued: track)
        let sound = LevelWords.soundRows(song: song, level: track.level, key: entry.key, decisions: player.levelDecisions,
                                         live: track.albumId.flatMap { player.loudness(albumID: $0) })
        //? Sound's Format first, as iInfo's This song has it, then the song's facts, then the rest of how it sounds
        let format = sound.prefix(1).map { InfoRow(label: $0.label, value: $0.value, mono: true) }
        let rest = sound.dropFirst().map { InfoRow(label: $0.label, value: $0.value) }
        PhoneGroup(legend: AboutFactWords.thisSong) {
            ForEach(format + facts.song + rest, id: \.label) { (row: InfoRow) in
                InfoKV(row: row)
            }
            InfoKV(row: InfoRow(label: DownloadWords.playsFrom, value: playsFrom(track.id)))
            // the EQ, only while it is on - a view of its own, so the EQ's changes redraw it alone
            InfoEQRow()
        }

        let card = AboutCard.about(track: AboutTrack(entry: track), album: playedAbout(track), details: saidDetails(track)).album
        let id = card?.id.flatMap { $0.isEmpty ? nil : $0 }
        if !facts.album.isEmpty || id != nil {
            PhoneGroup(legend: AboutFactWords.theAlbum) {
                ForEach(facts.album, id: \.label) { (row: InfoRow) in
                    InfoKV(row: row)
                }
                if let id, let card {
                    //? the album as it was played from - or, for a playlist's songs, a stub Album info asks the whole of
                    let album = player.playedAlbum(id: id)
                        ?? Album(id: id, name: card.title, artist: track.artist, coverArt: card.coverArt, partial: true)
                    NavigationLink(value: AlbumInfoPush(album: album)) {
                        PhoneGo {
                            Text(AlbumInfoWords.title)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            PhoneChevron()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        goes(entry, card: card, artistID: facts.artistID ?? song.artistId.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// Go to album and Go to artist (iInfo's two under the cards): each only where there is somewhere to go, side by side
    /// and filling - stacked at the accessibility sizes, each one's words in three lines at most.
    @ViewBuilder
    private func goes(_ entry: QueueEntry, card: About.AlbumCard?, artistID: String?) -> some View {
        let track = entry.track
        let route = card.flatMap { PlayedAlbum.route(id: $0.id, track: track, player: player) }
        if route != nil || artistID != nil {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Self.goesGap))
                                                      : AnyLayout(HStackLayout(spacing: Self.goesGap))
            layout {
                if let route {
                    Button {
                        navigation.openAlbum(route)
                    } label: {
                        InfoButtonWords(words: AboutFactWords.goToAlbum)
                    }
                    .buttonStyle(DWButtonStyle(fills: true))
                }
                if let artistID {
                    Button {
                        goToArtist(artistID, name: track.artist)
                    } label: {
                        InfoButtonWords(words: AboutFactWords.goToArtist)
                    }
                    .buttonStyle(DWButtonStyle(fills: true))
                }
            }
            .padding(.top, Self.goesAbove)
        }
    }

    /// Go to artist: Now Playing put down, the artist's page pushed on the tab shown - never twice over itself, as Go to
    /// album's own (AppNavigation.openAlbum).
    private func goToArtist(_ id: String, name: String) {
        navigation.nowPlayingShown = false
        if case .artist(let shown)? = navigation.shownStack.last, shown.id == id { return }
        navigation.open(.artist(ArtistRoute(id: id, preview: Artist(id: id, name: name))))
    }

    /// iInfo's Debug: its sections as groups, each row its label, its value and its note.
    @ViewBuilder
    private func phoneDebug(_ entry: QueueEntry) -> some View {
        ForEach(Array(debugSections(entry).enumerated()), id: \.offset) { _, section in
            PhoneGroup(legend: section.title) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    InfoDebugRow(row: row)
                }
            }
        }
    }

    // MARK: About

    /// The album the queue was played from, as About reads it.
    private func playedAbout(_ track: QueueTrack) -> AboutAlbum? {
        track.albumId.flatMap { player.playedAlbum(id: $0) }.map(AboutAlbum.init(album:))
    }

    /// What has been said of the song playing.
    private func saidDetails(_ track: QueueTrack) -> AboutDetails? {
        said.flatMap { $0.songID == track.id ? $0.details : nil }
    }

    /// (R3b) The facts as rows (AboutCard.facts), against the day `now` says - (R3b's review) the file's size and bit
    /// rate from the song as the player has it (Navidrome's song; nil for a queue put back, which says none).
    private func aboutFacts(_ entry: QueueEntry, folders: Bool) -> AboutFacts {
        let track = entry.track
        let song = player.song(for: entry)
        return AboutCard.facts(track: AboutTrack(entry: track), album: playedAbout(track), details: saidDetails(track),
                               folders: folders, size: song?.size, bitRate: song?.bitRate, now: now)
    }

    // MARK: the Mac's page (R16)

    @ViewBuilder
    private func macPage(tabs: [InfoTab], tab: InfoTab, admin: Bool) -> some View {
        if let entry = player.current {
            let facts = aboutFacts(entry, folders: admin)
            ScrollView {
                VStack(alignment: .leading, spacing: DockLook.gap) {
                    macSong(entry, facts: facts)
                    if tabs.count > 1 {
                        DWSegmented(options: tabs, words: { (each: InfoTab) -> String in each.label }, chosen: picked,
                                    spoken: InfoWords.title)
                    }
                    switch tab {
                    case .about: macAbout(entry, facts: facts)
                    case .debug: macDebug(entry)
                    }
                }
                .padding(DockLook.side)
            }
            .scrollContentBackground(.hidden)
            //? each tab, and each song, from its top
            .id("\(tab.rawValue)|\(entry.key)")
        } else {
            Spacer()
        }
    }

    /// The song's head (Albums.dc.html's, for a song): its cover, its title, its artist in the accent, "Album · Year" and
    /// its facts in Courier Prime - one element, every line wrapping.
    private func macSong(_ entry: QueueEntry, facts: AboutFacts) -> some View {
        let track = entry.track
        let song = player.song(for: entry) ?? Song(queued: track)
        let format = soundRows(entry).first?.value
        let readout = MacDock.Words.facts([format, AboutCard.sizeLine(size: song.size, bitRate: song.bitRate)])
        return HStack(alignment: .top, spacing: DockLook.gap) {
            CoverImage(id: track.coverArt, size: DockLook.cover)
                .frame(width: DockLook.cover, height: DockLook.cover)
                .clipShape(DWCorners.chipShape)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(DockType.title)
                    .foregroundStyle(DWPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(DockType.words)
                        .foregroundStyle(DWPalette.acc)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !facts.line.isEmpty {
                    Text(facts.line)
                        .font(DockType.small)
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                if !readout.isEmpty {
                    Text(readout)
                        .font(DockType.readout)
                        .foregroundStyle(DWPalette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// Sound's rows for the queue's entry (LevelWords.soundRows): Format, Gapless, Normalization.
    private func soundRows(_ entry: QueueEntry) -> [InfoRow] {
        let track = entry.track
        let song = player.song(for: entry) ?? Song(queued: track)
        return LevelWords.soundRows(song: song, level: track.level, key: entry.key, decisions: player.levelDecisions,
                                    live: track.albumId.flatMap { player.loudness(albumID: $0) })
            .map { InfoRow(label: $0.label, value: $0.value) }
    }

    /// The Mac's About: Info's ways on as a row of the look's buttons - Go to album the primary, Go to artist, Album info
    /// at the right - each only where there is somewhere to go; then Properties (the song's facts, Sound's, Plays from
    /// and the EQ while it is on) and The album, as groups.
    @ViewBuilder
    private func macAbout(_ entry: QueueEntry, facts: AboutFacts) -> some View {
        let track = entry.track
        let song = player.song(for: entry) ?? Song(queued: track)
        let card = AboutCard.about(track: AboutTrack(entry: track), album: playedAbout(track), details: saidDetails(track)).album
        let route = card.flatMap { PlayedAlbum.route(id: $0.id, track: track, player: player) }
        let artistID = facts.artistID ?? song.artistId.flatMap { $0.isEmpty ? nil : $0 }
        let id = card?.id.flatMap { $0.isEmpty ? nil : $0 }
        if route != nil || artistID != nil || id != nil {
            HStack(spacing: DockLook.headerGap) {
                if let route {
                    Button(AboutFactWords.goToAlbum) { navigation.openAlbum(route) }
                        .buttonStyle(DWButtonStyle(kind: .pri))
                }
                if let artistID {
                    Button(AboutFactWords.goToArtist) { goToArtist(artistID, name: track.artist) }
                        .buttonStyle(DWButtonStyle())
                }
                Spacer(minLength: 0)
                if let id, let card {
                    //? the album as it was played from - or, for a playlist's songs, a stub Album info asks the whole of
                    let album = player.playedAlbum(id: id)
                        ?? Album(id: id, name: card.title, artist: track.artist, coverArt: card.coverArt, partial: true)
                    NavigationLink(value: AlbumInfoPush(album: album)) {
                        Text(AlbumInfoWords.title)
                    }
                    .buttonStyle(DWButtonStyle())
                }
            }
        }

        let sound = soundRows(entry)
        //? Sound's Format first, as the phone's This song has it, then the song's facts, then the rest of how it sounds
        let format = sound.prefix(1).map { InfoRow(label: $0.label, value: $0.value, mono: true) }
        DockGroup(legend: MacAlbumFacts.Words.properties) {
            ForEach(format + facts.song + sound.dropFirst(), id: \.label) { (row: InfoRow) in
                DockFact(label: row.label, value: row.value, mono: row.mono)
            }
            DockFact(label: DownloadWords.playsFrom, value: playsFrom(track.id))
            // the EQ, only while it is on - a view of its own, so the EQ's changes redraw it alone
            InfoEQFact()
        }

        if !facts.album.isEmpty {
            DockGroup(legend: AboutFactWords.theAlbum) {
                ForEach(facts.album, id: \.label) { (row: InfoRow) in
                    DockFact(label: row.label, value: row.value, mono: row.mono)
                }
            }
        }
    }

    /// The Mac's Debug: its sections as groups, each row its label, its value and its note.
    @ViewBuilder
    private func macDebug(_ entry: QueueEntry) -> some View {
        ForEach(Array(debugSections(entry).enumerated()), id: \.offset) { _, section in
            DockGroup(legend: section.title) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    DockFact(label: row.label, value: row.value, mono: row.mono, note: row.note, noteMono: row.noteMono)
                }
            }
        }
    }

    // MARK: Debug

    /// Debug's sections, the copy on this phone in Sent to this device (Phase 2).
    private func debugSections(_ entry: QueueEntry) -> [InfoSection] {
        let track = entry.track
        let song = player.song(for: entry) ?? Song(queued: track)
        let album = raw.flatMap { $0.albumID == track.albumId ? $0.answer : nil }
        //? the engine's rows move as it plays: read again at each tick (`tick` read so the rows are drawn again)
        let _ = tick
        let engine = InfoDebug.Engine(player.engineDebug(), outputName: player.outputName, readout: player.conversion,
                                      eq: eq.infoDebug)
        return InfoDebug.sections(song: song, level: track.level, key: entry.key, decisions: player.levelDecisions,
                                  live: track.albumId.flatMap { player.loudness(albumID: $0) },
                                  engine: engine, album: album, device: Platform.device).map { section in
            //? Sent to this device gains the copy on this phone (Phase 2)
            guard section.title == Self.sentTitle else { return section }
            let onPhone = InfoRow(label: DownloadWords.onThisDevice(Platform.device),
                                  value: DownloadWords.debugOnPhone(downloads.records[track.id], channels: song.channelCount))
            return InfoSection(title: section.title, rows: section.rows + [onPhone])
        }
    }

    /// Debug's section the copy on this phone is said in.
    private static let sentTitle = "Sent to this device"

    /// Sound's Plays from: this phone and its check, or streamed - what is heard.
    private func playsFrom(_ songID: String) -> String {
        guard let record = downloads.records[songID], record.state == .done, !downloads.streamEvenWhenDownloaded else {
            return DownloadWords.streamed
        }
        return DownloadWords.playsFrom(record.check ?? .unchecked, isFLAC: record.suffix.lowercased() == "flac", device: Platform.device)
    }

    /// Debug's clock: a tick each second while it shows, none otherwise.
    private func ticking(_ tab: InfoTab) async {
        guard tab == .debug else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
            tick &+= 1
        }
    }

    // MARK: asking

    /// The song's details and its album's folders, for the song playing (InfoAsk.details).
    private func askDetails() async {
        guard let track = player.current?.track, let client = server.client else { return }
        let songID = track.id
        said = said.flatMap { $0.songID == songID ? $0 : nil }
        await InfoAsk.details(songID: songID, albumID: track.albumId, bridge: server.access.hasLibrary, client: client) { details in
            said = InfoAsk.Said(songID: songID, details: details)
        }
    }

    /// What Debug's raw album is asked for: the album the queue was played from, while Debug shows - nil otherwise.
    private func rawAsk(_ tab: InfoTab) -> String? {
        guard tab == .debug, let id = player.current?.track.albumId, !id.isEmpty, player.playedAlbum(id: id) != nil else { return nil }
        return id
    }

    private func askRaw(_ tab: InfoTab) async {
        guard let id = rawAsk(tab), raw?.albumID != id, let client = server.client else { return }
        let answer = await InfoAsk.rawAlbum(id: id, client: client)
        if Task.isCancelled { return }
        raw = (id, answer)
    }
}

/// (R16) Properties' EQ row in the Mac's dock, only while the EQ is on - a view of its own, as the phone's InfoEQRow is.
private struct InfoEQFact: View {
    @Environment(EQModel.self) private var eq

    var body: some View {
        if let sound = eq.infoSound {
            DockFact(label: EQWords.Info.label, value: sound)
        }
    }
}

/// (R3b) One of iInfo's facts (`.kv`): its label white at the row's 16, 116 wide at least, its value at the right in the
/// second colour at the small 13 - monospaced where the fact is a number, a time or a path (`.mono.s`), and selectable,
/// to copy - 42 tall at least on its hairline, as PhoneKV is - on its label's baseline, as `.kv` is (25 Nov: centred, a
/// readout's shorter line set it higher). At the accessibility sizes the value goes under its label, where a long label
/// and its value both have the page's width. One element for VoiceOver: its label, then its value.
private struct InfoKV: View {
    let row: InfoRow

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: CGFloat(PhoneLook.kvGap) / 2))
                             : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: CGFloat(PhoneLook.kvGap)))
        layout {
            Text(row.label)
                .font(Typeface.Phone.text(.row))
                .foregroundStyle(DWPalette.kvLabel)
                .frame(minWidth: stacked ? nil : CGFloat(PhoneLook.kvLabelWidth), alignment: .leading)
            if !stacked { Spacer(minLength: 0) }
            Text(row.value)
                .font(row.mono ? Typeface.Phone.mono(.small) : Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, stacked ? CGFloat(PhoneLook.kvGap) / 2 : 0)
        .lookHeight(PhoneLook.kvRow)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        .accessibilityElement(children: .combine)
    }
}

/// (R3b) This song's EQ row, only while the EQ is on (EQWords.Info: "Bass Boost on James's AirPods Pro, preamp -6.1 dB") -
/// a view of its own, so the EQ's changes redraw this row alone, never the page.
private struct InfoEQRow: View {
    @Environment(EQModel.self) private var eq

    var body: some View {
        if let sound = eq.infoSound {
            InfoKV(row: InfoRow(label: EQWords.Info.label, value: sound))
        }
    }
}

/// (R3b) One of Debug's rows on the phone: its label white at the row's 16, its value under it in the second colour at
/// the small 13 (monospaced for an id or a path) and its note under that at the extra-small, both selectable - on the
/// group's hairline, 42 tall at least. One element.
private struct InfoDebugRow: View {
    let row: InfoRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.label)
                .font(Typeface.Phone.text(.row))
                .foregroundStyle(DWPalette.kvLabel)
            Text(row.value)
                .font(row.mono ? Typeface.Phone.mono(.small) : Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .textSelection(.enabled)
            if let note = row.note, !note.isEmpty {
                Text(note)
                    .font(row.noteMono ? Typeface.Phone.mono(.extraSmall) : Typeface.Phone.text(.extraSmall))
                    .foregroundStyle(DWPalette.t3)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CGFloat(PhoneLook.kvGap) / 2)
        .lookHeight(PhoneLook.kvRow)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        .accessibilityElement(children: .combine)
    }
}

/// (R3b) A way on's words (Go to album, Go to artist): one line, three at the accessibility sizes, centred.
private struct InfoButtonWords: View {
    let words: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(words)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
    }
}
