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
/// the sheet's (`picked`), so the strip's taps keep it; Debug's sections are groups too. In the Mac's side panel the page
/// is as it was, its song's lines the same facts as rows - Played among them.
struct InfoView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(EQModel.self) private var eq
    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    /// (The Mac app, slice 3) Drawn in the desktop frame's side panel: Done puts the panel away (MacPanel).
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

    /// The album card's cover.
    private static let cover: CGFloat = 60
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

    /// The page: the phone's in the sheet, under its top; the Mac's in the side panel, as it was.
    @ViewBuilder
    private func page(tabs: [InfoTab], tab: InfoTab, admin: Bool) -> some View {
        if let sheet {
            phonePage(tabs: tabs, tab: tab, admin: admin)
                .sheetTop(sheet) {}
        } else {
            VStack(spacing: 0) {
                if tabs.count > 1 {
                    Picker(InfoWords.title, selection: picked) {
                        ForEach(tabs, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                if let entry = player.current {
                    List {
                        switch tab {
                        case .about: about(entry, folders: admin)
                        case .debug: debug(entry)
                        }
                    }
                    .listStyle(.insetGrouped)
                    //? each tab, and each song, from its top
                    .id("\(tab.rawValue)|\(entry.key)")
                } else {
                    Spacer()
                }
            }
            .navigationTitle(InfoWords.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(InfoWords.done) {
                        if inSidePanel { navigation.closePanel() } else { dismiss() }
                    }
                    // (the Mac app, slice 3) a panel's Done: Escape's after a field with the cursor, before the page's
                    // Edit (MacFrame.escape - one owner)
                    .escapeCloses(MacFrame.escape(typing: TextEditing.shared.typing, panel: navigation.macPanel) == .panel)
                }
            }
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

    @ViewBuilder
    private func about(_ entry: QueueEntry, folders: Bool) -> some View {
        let track = entry.track
        let album = playedAbout(track)
        let details = saidDetails(track)
        let about = AboutCard.about(track: AboutTrack(entry: track), album: album, details: details, folders: folders)
        let facts = aboutFacts(entry, folders: folders)
        let song = player.song(for: entry) ?? Song(queued: track)

        Section {
            VStack(alignment: .leading, spacing: 3) {
                Text(about.song.title)
                    .font(Typeface.headline)
                if !about.song.artist.isEmpty {
                    Text(about.song.artist)
                        .foregroundStyle(Palette.quiet)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            //? (R3b) the song's lines as rows - Track, Disc, Length, Played ("19 times · today"), Written by - as the
            //? phone's This song has them
            ForEach(facts.song, id: \.label) { (row: InfoRow) in
                LabeledContent(row.label, value: row.value)
            }
        } header: {
            Text(InfoWords.songTitle).font(Typeface.footnote)
        }

        if let card = about.album {
            Section {
                if let route = PlayedAlbum.route(id: card.id, track: track, player: player) {
                    Button {
                        navigation.openAlbum(route)
                    } label: {
                        HStack(spacing: 12) {
                            albumCard(card)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(Typeface.symbol(.footnote).weight(.semibold))
                                .foregroundStyle(Palette.quiet)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    albumCard(card)
                }
                if let id = card.id, !id.isEmpty {
                    //? the album as it was played from - or, for a playlist's songs, a stub Album info asks the whole of
                    let album = player.playedAlbum(id: id)
                        ?? Album(id: id, name: card.title, artist: track.artist, coverArt: card.coverArt, partial: true)
                    NavigationLink(value: AlbumInfoPush(album: album)) {
                        Label(AlbumInfoWords.title, systemImage: AlbumInfoWords.symbol)
                    }
                }
            } header: {
                Text(InfoWords.albumTitle).font(Typeface.footnote)
            }
        }

        if let artist = about.artist {
            Section {
                Text(artist.name)
                    .font(Typeface.headline)
            } header: {
                Text(InfoWords.artistTitle).font(Typeface.footnote)
            }
        }

        Section {
            let rows = LevelWords.soundRows(song: song, level: track.level, key: entry.key, decisions: player.levelDecisions,
                                            live: track.albumId.flatMap { player.loudness(albumID: $0) })
            ForEach(rows, id: \.label) { row in
                LabeledContent(row.label, value: row.value)
            }
            // the phone's own row, apart from the web's three
            LabeledContent(DownloadWords.playsFrom, value: playsFrom(track.id))
            // and the EQ, only while it is on (3.1)
            if let sound = eq.infoSound {
                LabeledContent(EQWords.Info.label, value: sound)
            }
        } header: {
            Text(LevelWords.soundTitle).font(Typeface.footnote)
        }

        //? last: a path to copy, and a line landing late here moves no card a finger is reaching for
        if let folder = about.album?.folder {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(InfoWords.folder)
                    Text(folder)
                        .font(Typeface.mono(.footnote))
                        .foregroundStyle(Palette.quiet)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text(InfoWords.serverTitle).font(Typeface.footnote)
            }
        }
    }

    private func albumCard(_ card: About.AlbumCard) -> some View {
        HStack(spacing: 12) {
            CoverImage(id: card.coverArt, size: Self.cover)
                .frame(width: Self.cover, height: Self.cover)
                .clipShape(Corners.artShape)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(Typeface.headline)
                if !card.line.isEmpty {
                    Text(card.line)
                        .font(Typeface.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
                if let pressing = card.pressing {
                    Text(pressing)
                        .font(Typeface.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Debug

    @ViewBuilder
    private func debug(_ entry: QueueEntry) -> some View {
        ForEach(Array(debugSections(entry).enumerated()), id: \.offset) { _, section in
            Section {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    DebugRowView(row: row)
                }
            } header: {
                Text(section.title).font(Typeface.footnote)
            }
        }
    }

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

/// One of Debug's rows: its label, its value - in the monospaced face for an id or a path - and a smaller note
/// under it; the value and note can be selected, to copy.
private struct DebugRowView: View {
    let row: InfoRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.label)
                .font(Typeface.subheadline.weight(.medium))
            Text(row.value)
                .font(row.mono ? Typeface.mono(.footnote) : Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .textSelection(.enabled)
            if let note = row.note, !note.isEmpty {
                Text(note)
                    .font(row.noteMono ? Typeface.mono(.caption) : Typeface.caption)
                    .foregroundStyle(Palette.quiet)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
