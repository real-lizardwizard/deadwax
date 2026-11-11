import DeadwaxCore
import SwiftUI

/// Info (ui/src/app/InfoSheet.tsx, D8), a sheet over Now Playing, for the song playing.
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
struct InfoView: View {
    @Environment(PlayerModel.self) private var player
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var picked: InfoTab = .about
    @State private var said: InfoAsk.Said?
    @State private var raw: (albumID: String, answer: RawJSON?)?
    /// Debug's second hand: the engine's rows are read again as it moves.
    @State private var tick = 0

    /// The album card's cover.
    private static let cover: CGFloat = 60

    init() {}

    var body: some View {
        let admin = server.access.isAdmin
        let tabs = InfoTab.tabs(admin: admin)
        let tab = InfoTab.shown(picked, admin: admin)
        NavigationStack {
            VStack(spacing: 0) {
                if tabs.count > 1 {
                    Picker(InfoWords.title, selection: $picked) {
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
                    Button(InfoWords.done) { dismiss() }
                }
            }
        }
        .task(id: player.current?.track.id) { await askDetails() }
        .task(id: rawAsk(tab)) { await askRaw(tab) }
        .task(id: tab) { await ticking(tab) }
        .onChange(of: admin) { _, now in
            //? the role gone: About, and the Debug chosen before forgotten when it comes back
            if !now { picked = .about }
        }
    }

    // MARK: About

    @ViewBuilder
    private func about(_ entry: QueueEntry, folders: Bool) -> some View {
        let track = entry.track
        let album = track.albumId.flatMap { player.playedAlbum(id: $0) }.map(AboutAlbum.init(album:))
        let details = said.flatMap { $0.songID == track.id ? $0.details : nil }
        let about = AboutCard.about(track: AboutTrack(entry: track), album: album, details: details, folders: folders)
        let song = player.song(for: entry) ?? Song(queued: track)

        Section(InfoWords.songTitle) {
            VStack(alignment: .leading, spacing: 3) {
                Text(about.song.title)
                    .font(.headline)
                if !about.song.artist.isEmpty {
                    Text(about.song.artist)
                        .foregroundStyle(Palette.quiet)
                }
                ForEach(about.song.lines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
                if let writers = about.song.writtenBy {
                    Text(InfoWords.writtenBy(writers))
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }

        if let card = about.album {
            Section(InfoWords.albumTitle) {
                if let route = PlayedAlbum.route(id: card.id, track: track, player: player) {
                    Button {
                        navigation.openAlbum(route)
                    } label: {
                        HStack(spacing: 12) {
                            albumCard(card)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.quiet)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    albumCard(card)
                }
            }
        }

        if let artist = about.artist {
            Section(InfoWords.artistTitle) {
                Text(artist.name)
                    .font(.headline)
            }
        }

        Section(LevelWords.soundTitle) {
            let rows = LevelWords.soundRows(song: song, level: track.level, key: entry.key, decisions: player.levelDecisions,
                                            live: track.albumId.flatMap { player.loudness(albumID: $0) })
            ForEach(rows, id: \.label) { row in
                LabeledContent(row.label, value: row.value)
            }
        }

        //? last: a path to copy, and a line landing late here moves no card a finger is reaching for
        if let folder = about.album?.folder {
            Section(InfoWords.serverTitle) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(InfoWords.folder)
                    Text(folder)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Palette.quiet)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func albumCard(_ card: About.AlbumCard) -> some View {
        HStack(spacing: 12) {
            CoverImage(id: card.coverArt, size: Self.cover)
                .frame(width: Self.cover, height: Self.cover)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(.headline)
                if !card.line.isEmpty {
                    Text(card.line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
                if let pressing = card.pressing {
                    Text(pressing)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Debug

    @ViewBuilder
    private func debug(_ entry: QueueEntry) -> some View {
        let track = entry.track
        let song = player.song(for: entry) ?? Song(queued: track)
        let album = raw.flatMap { $0.albumID == track.albumId ? $0.answer : nil }
        //? the engine's rows move as it plays: read again at each tick (`tick` read so the rows are drawn again)
        let _ = tick
        let engine = InfoDebug.Engine(player.engineDebug(), outputName: player.outputName, readout: player.conversion)
        let sections = InfoDebug.sections(song: song, level: track.level, key: entry.key, decisions: player.levelDecisions,
                                          live: track.albumId.flatMap { player.loudness(albumID: $0) },
                                          engine: engine, album: album)
        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
            Section(section.title) {
                ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                    DebugRowView(row: row)
                }
            }
        }
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
                .font(.subheadline.weight(.medium))
            Text(row.value)
                .font(row.mono ? .footnote.monospaced() : .footnote)
                .foregroundStyle(Palette.quiet)
                .textSelection(.enabled)
            if let note = row.note, !note.isEmpty {
                Text(note)
                    .font(row.noteMono ? .caption.monospaced() : .caption)
                    .foregroundStyle(Palette.quiet)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
