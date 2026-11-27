import DeadwaxCore
import SwiftUI
import UIKit

/// Album info as a sheet of its own (notes/ios.md "Album info"), from an album page's •••: AlbumInfoList in a
/// navigation stack, with Done.
struct AlbumInfoSheet: View {
    let album: Album

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AlbumInfoList(album: album)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AlbumInfoWords.done) { dismiss() }
                            .escapeCloses()
                    }
                }
        }
    }
}

/// Album info pushed inside Info's stack (`navigationDestination(for:)`): a value, so the page stays on the album it
/// was opened for when the song playing changes under it - Info's List is drawn afresh for each song, and a pushed
/// page tied to its row would go with it (or change album under a reader). Back goes to Info, for the song playing.
struct AlbumInfoPush: Hashable {
    let album: Album

    static func == (a: AlbumInfoPush, b: AlbumInfoPush) -> Bool { a.album == b.album }
    func hash(into hasher: inout Hasher) { hasher.combine(album.id) }
}

/// Album info (James, 2026-11-15: "I'd like somewhere I can see all the album metadata like quality, media type,
/// etc."): the album as a whole, in a listener's words, grouped - pushed inside Info's stack from its album card, or in
/// AlbumInfoSheet from the album page's •••. Every line is Core's (AlbumInfo); this draws and asks.
///
/// At once, from the album in hand and this phone: the cover, title and artist, then Quality, The album and On this
/// phone. Then what deadwax adds (AlbumInfoAsk: the album again, the id bridge, the folders' files) - The release,
/// MusicBrainz and, for an admin, On the server - drawn once every answer is in or AlbumInfoWords.settleSeconds has
/// gone, a "Reading the album's files…" row in their place until then (and under them while the rest comes). Info's
/// album may be a playlist's stub of it (`partial`): its own lines wait for the album's answer too, since a stub's songs
/// are only the playlist's. What couldn't be asked is said (ErrorNote): the album, where its files are, the files -
/// never left looking like tags that say nothing. While deadwax can't be reached nothing is asked: the release's lines
/// are drawn from what is in hand, and while that is short of everything, a line says the rest comes when deadwax is
/// back.
///
/// An id, a path or a number read in columns is in the monospaced face, selectable, with a Copy button beside it
/// ("Copied" said to VoiceOver, the button's sign a tick for a moment); a MusicBrainz page opens in Safari, beside the
/// app (openURL), and if iOS refuses, a line under the row says so. A line wraps at every text size, never truncated;
/// VoiceOver reads each line's label and words as one.
///
/// (The panel review's R16 - notes/ios.md "The panel review, R16: the Mac's dock tabs (2026-11-26)") Drawn flat on both
/// devices, no List. On the Mac (Albums.dc.html's panel - the dock's Info for an album, Info's Album info, the
/// right-click's Album info…) the cover (112, a cover's corners) beside the title (18, bold), the artist in the accent
/// and the year; in the dock only, the album's Play (the primary), Shuffle and Add to Queue from its songs in hand -
/// each an existing PlayerModel call in the click, offline the songs on this Mac - and Edit for whoever may
/// (Managing.albumEdit), the album's ••• and right-click's own, then its songs in a box, a row each at View ▸ Row Size;
/// then every section as a `.group` of DockFact rows, an id or a path in Courier Prime with its copy glyph, a link in
/// the accent. On the phone (iInfo's) the header as it was, each section a PhoneGroup on hairlines - a fact a `.kv`
/// (PhoneKV), a long or copyable one its label over its words, its copy glyph a finger's target, a link a PhoneGo.
struct AlbumInfoList: View {
    let album: Album

    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(\.openURL) private var openURL
    @Environment(PlayerModel.self) private var player
    @Environment(AppNavigation.self) private var navigation
    /// (R16) In the Mac's dock: the album's own Play, Shuffle, Add to Queue and Edit, and its songs.
    @Environment(\.inSidePanel) private var inSidePanel
    /// What deadwax said, for which album, by which asking (`runs`).
    @State private var said: (run: Int, albumID: String, said: AlbumInfoAsk.Said)?
    /// Each asking's number: the one that ends marks only its own answer as cut short.
    @State private var runs = 0
    /// The row whose Copy was tapped last, while its tick shows.
    @State private var copied: String?
    /// A link row iOS wouldn't open.
    @State private var refused: String?
    /// (R5) Now, for Played's day words - re-read at a day's change, never per row.
    @State private var now = ArtistTotals.now()

    /// The phone's header's cover (iInfo's 64) and the gap beside it, and the page's sides and foot.
    private static let cover: CGFloat = 64
    private static let coverGap: CGFloat = 12
    private static let side: CGFloat = 16
    private static let foot: CGFloat = 34
    /// How long a Copy button shows its tick.
    private static let copiedSeconds = 2.0

    var body: some View {
        let answer = said.flatMap { $0.albumID == album.id ? $0.said : nil }
        //? the album's own answer once it has come; a playlist's stub of it is never counted from
        let whole = answer?.album ?? (album.partial ? nil : album)
        let online = reachability.online && server.client != nil
        ScrollView {
            VStack(alignment: .leading, spacing: Platform.mac ? DockLook.gap : 0) {
                if Platform.mac {
                    macHeader(whole ?? album)
                    if inSidePanel { macTools(whole, online: online) }
                } else {
                    header(whole ?? album)
                }

                if let whole {
                    ForEach(AlbumInfo.local(album: whole, onPhone: onPhone(whole), device: Platform.device,
                                            played: played(whole))) { section in
                        infoSection(section)
                    }
                }

                // deadwax's answers once they've come (or the wait is over); offline, what is in hand
                if answer != nil || !online {
                    ForEach(AlbumInfo.fromServer(album: whole ?? album, extras: answer?.extras, store: answer?.store,
                                                 files: answer?.files, folders: server.access.isAdmin,
                                                 countryName: Self.countryName)) { section in
                        infoSection(section)
                    }
                }

                if online, let answer, let note = missing(answer) {
                    missingNote(note)
                        .padding(.top, Platform.mac ? 0 : Self.coverGap)
                }

                if online && (answer?.reading ?? true) {
                    reading
                        .padding(.top, Platform.mac ? 0 : Self.coverGap)
                } else if !online && !(answer?.complete ?? false) {
                    quiet(AlbumInfoWords.offline)
                        .padding(.top, Platform.mac ? 0 : Self.coverGap)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Platform.mac ? DockLook.side : Self.side)
            .padding(.top, Platform.mac ? DockLook.side : CGFloat(PhoneLook.topGap))
            .padding(.bottom, Platform.mac ? DockLook.side : Self.foot)
        }
        .scrollContentBackground(.hidden)
        .background(Platform.mac ? DWPalette.panel : DWPalette.page)
        .navigationTitle(AlbumInfoWords.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: askKey) { await ask() }
        .task { await downloads.followProgress() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // (R5) a day's change: Played's "yesterday" moves at midnight, as the album page's does
            now = ArtistTotals.now()
        }
    }

    /// (R5, check 555) The Mac's Played row in The album - the album page's own words (MacAlbumFacts.playedRow), so
    /// Albums' Info and the page agree; none on the iPhone, whose album page says nothing of plays.
    private func played(_ album: Album) -> AlbumInfoRow? {
        Platform.mac ? MacAlbumFacts.playedRow(album, now: now) : nil
    }

    // MARK: drawing

    /// The phone's header (iInfo's song row, for the album): its cover, its title, its artist in the accent - one element.
    private func header(_ album: Album) -> some View {
        HStack(spacing: Self.coverGap) {
            CoverImage(id: album.coverArt, size: Self.cover)
                .frame(width: Self.cover, height: Self.cover)
                .clipShape(Rectangle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name ?? "")
                    .font(Typeface.Phone.text(.row).weight(.semibold))
                    .foregroundStyle(DWPalette.text)
                if let artist = album.artist, !artist.isEmpty {
                    Text(artist)
                        .font(Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.acc)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// (R16) The Mac's header (Albums.dc.html's panel): the cover, the title, the artist in the accent and the year -
    /// one element, every line wrapping.
    private func macHeader(_ album: Album) -> some View {
        HStack(alignment: .top, spacing: DockLook.gap) {
            CoverImage(id: album.coverArt, size: DockLook.cover)
                .frame(width: DockLook.cover, height: DockLook.cover)
                .clipShape(DWCorners.chipShape)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.name ?? "")
                    .font(DockType.title)
                    .foregroundStyle(DWPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let artist = album.artist, !artist.isEmpty {
                    Text(artist)
                        .font(DockType.words)
                        .foregroundStyle(DWPalette.acc)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let year = album.year, year > 0 {
                    Text(String(year))
                        .font(DockType.small)
                        .foregroundStyle(DWPalette.t2)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// (R16) The songs the dock's Play, Shuffle and Add to Queue take: the album's own, once its answer is in - never a
    /// stub's, which are a playlist's - and offline only those on this Mac.
    private func playable(_ whole: Album?, online: Bool) -> [Song] {
        let songs = whole?.song ?? []
        return online ? songs : OfflineAlbum.playable(songs, here: downloads.isHere)
    }

    /// (R16) The dock's row of the album's actions (Albums.dc.html's: Play, Shuffle, Play next … Edit) - only those it
    /// has today, behind their own gates: Play, Shuffle and Add to Queue on the songs in hand, in the click with nothing
    /// awaited (dimmed until they are), and Edit at the right for whoever may edit the album, while deadwax can be
    /// reached; then the songs, in a box.
    @ViewBuilder
    private func macTools(_ whole: Album?, online: Bool) -> some View {
        let songs = playable(whole, online: online)
        let queued = whole.flatMap { (album: Album) -> QueuePick<Song>? in
            QueuePick.album(album).flatMap { AddToQueue.pick($0, online: online, gone: false, here: downloads.isHere) }
        }
        HStack(spacing: DockLook.headerGap) {
            Button {
                guard let whole, !songs.isEmpty else { return }
                player.play(songs: songs, album: whole, at: nil)
            } label: {
                HStack(spacing: DockLook.headerGap) {
                    SharpSymbol(.play)
                    Text(PlaylistWords.play)
                }
            }
            .buttonStyle(DWButtonStyle(kind: .pri))
            .disabled(songs.isEmpty)
            Button(ShuffleWords.shuffle) {
                guard let whole, !songs.isEmpty else { return }
                player.play(songs: songs, album: whole, at: nil, shuffle: true)
            }
            .buttonStyle(DWButtonStyle())
            .disabled(songs.isEmpty)
            Button(AddToQueue.words) {
                guard let queued else { return }
                _ = player.addToQueue(queued, album: whole)
            }
            .buttonStyle(DWButtonStyle())
            .disabled(queued == nil)
            Spacer(minLength: 0)
            if Managing.albumEdit(server.access.permissions).shown, online, let whole {
                Button(PlaylistWords.edit) {
                    navigation.editAlbum(AlbumEditRequest(target: .album(AlbumEdit.Subject(whole))))
                }
                .buttonStyle(DWButtonStyle())
            }
        }
        if let tracks = whole?.song, !tracks.isEmpty {
            VStack(spacing: 0) {
                ForEach(tracks) { (song: Song) in
                    DockSongRow(number: song.track.map(String.init) ?? "", title: song.title ?? "",
                                length: Format.trackTime(song.duration))
                }
            }
            .padding(.bottom, -1)
            .clipShape(DWCorners.boxShape)
            .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line))
        }
    }

    @ViewBuilder
    private func infoSection(_ section: AlbumInfoSection) -> some View {
        if Platform.mac {
            DockGroup(legend: section.title) {
                ForEach(section.rows) { row in
                    macRow(row)
                }
            }
        } else {
            PhoneGroup(legend: section.title) {
                ForEach(section.rows) { row in
                    phoneRow(row)
                }
            }
        }
    }

    /// (R16) A row in the Mac's `.group`: a fact, a fact to copy with its glyph, or a link in the accent.
    @ViewBuilder
    private func macRow(_ row: AlbumInfoRow) -> some View {
        let note = row.lines.isEmpty ? nil : row.lines.joined(separator: "\n")
        switch row.style {
        case .plain:
            DockFact(label: row.label, value: row.value, note: note)
        case .copyable:
            HStack(alignment: .firstTextBaseline, spacing: DockLook.headerGap) {
                DockFact(label: row.label, value: row.value, mono: true, note: note)
                copyButton(row)
            }
        case .link:
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    open(row)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(row.label)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: AlbumInfoWords.outSymbol)
                            .accessibilityHidden(true)
                    }
                    .font(DockType.small)
                    .foregroundStyle(DWPalette.acc)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(AlbumInfoWords.opensInSafari)
                if refused == row.id {
                    ErrorNote(text: AlbumInfoWords.notOpened)
                }
            }
        }
    }

    /// (R1c) A row in the phone's group: a fact as a `.kv`, a long or copyable one its label over its words with its
    /// copy glyph, or a link as a `.go` - each on its hairline.
    @ViewBuilder
    private func phoneRow(_ row: AlbumInfoRow) -> some View {
        switch row.style {
        case .plain where row.lines.isEmpty:
            PhoneKV(label: row.label, value: row.value)
        case .plain:
            words(row)
                .accessibilityElement(children: .combine)
                .modifier(AlbumInfoPhoneRule())
        case .copyable:
            HStack(spacing: CGFloat(PhoneLook.kvGap)) {
                words(row)
                    .accessibilityElement(children: .combine)
                copyButton(row)
            }
            .modifier(AlbumInfoPhoneRule())
        case .link:
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    open(row)
                } label: {
                    PhoneGo {
                        Text(row.label)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: AlbumInfoWords.outSymbol)
                            .font(Typeface.Phone.text(.small).weight(.semibold))
                            .foregroundStyle(DWPalette.t3)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(AlbumInfoWords.opensInSafari)
                if refused == row.id {
                    ErrorNote(text: AlbumInfoWords.notOpened)
                        .padding(.vertical, CGFloat(PhoneLook.kvGap) / 2)
                }
            }
        }
    }

    /// A row's Copy: its glyph in the accent - a tick for a moment once copied, "Copied" said to VoiceOver - a finger's
    /// target on the phone, the glyph's own on the Mac.
    private func copyButton(_ row: AlbumInfoRow) -> some View {
        Button {
            copy(row)
        } label: {
            Image(systemName: copied == row.id ? AlbumInfoWords.copiedSymbol : AlbumInfoWords.copySymbol)
                .font(Platform.mac ? DockType.small : Typeface.Phone.text(.row))
                .foregroundStyle(DWPalette.acc)
                .lookSquare(Platform.mac ? 0 : DWLook.here.target)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(AlbumInfoWords.copyName(row.label))
        .accessibilityLabel(AlbumInfoWords.copyName(row.label))
    }

    /// The phone's: a line's label, its words - in Courier Prime where they are to copy - and the lines under them.
    private func words(_ row: AlbumInfoRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.label)
                .font(Typeface.Phone.text(.row))
                .foregroundStyle(DWPalette.kvLabel)
            Text(row.value)
                .font(row.style == .copyable ? Typeface.Phone.mono(.small) : Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .textSelection(.enabled)
            ForEach(row.lines, id: \.self) { line in
                Text(line)
                    .font(Typeface.Phone.text(.extraSmall))
                    .foregroundStyle(DWPalette.t3)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A quiet line - offline, no folder, reading: the dock's label size on the Mac, the small 13 on the phone.
    private func quiet(_ words: String) -> some View {
        Text(words)
            .font(Platform.mac ? DockType.label : Typeface.Phone.text(.small))
            .foregroundStyle(DWPalette.t3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What couldn't be had - the first of: the album, where its files are, the files - else that deadwax knows no
    /// folder of it (so nothing could be read from its files). Nil when nothing is missing.
    private enum Missing {
        case failed(any Error, gone: String?, failed: String)
        case gone
        case noFolder
    }

    private func missing(_ answer: AlbumInfoAsk.Said) -> Missing? {
        if let failure = answer.albumFailure {
            return .failed(failure, gone: ErrorWords.albumGone, failed: AlbumInfoWords.albumFailed)
        }
        if answer.albumMissing { return .gone }
        if let failure = answer.storeFailure { return .failed(failure, gone: nil, failed: AlbumInfoWords.storeFailed) }
        if let failure = answer.filesFailure {
            return .failed(failure, gone: AlbumInfoWords.filesGone, failed: AlbumInfoWords.filesFailed)
        }
        if let store = answer.store, AlbumInfo.foldersToRead(store).isEmpty { return .noFolder }
        return nil
    }

    /// What is missing, in a listener's words (ErrorWords); that no folder is known, quietly - it is no failure.
    @ViewBuilder
    private func missingNote(_ missing: Missing) -> some View {
        switch missing {
        case .failed(let error, let gone, let failed):
            ErrorNote(error, gone: gone, failed: failed)
        case .gone:
            ErrorNote(text: ErrorWords.albumGone)
        case .noFolder:
            quiet(AlbumInfoWords.noFolder)
        }
    }

    private var reading: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(Platform.mac ? .small : .regular)
            quiet(AlbumInfoWords.reading)
        }
        .accessibilityElement(children: .combine)
    }

    /// On this phone's line - nil while there is no download store open (signed out).
    private func onPhone(_ album: Album) -> AlbumInfoRow? {
        let songs = album.song ?? []
        guard downloads.isOpen, !songs.isEmpty else { return nil }
        let here = downloads.here(songs)
        return AlbumInfo.onPhone(downloads.album(songs), here: here.count, of: songs.count, bytes: here.bytes, device: Platform.device)
    }

    // MARK: acting

    private func copy(_ row: AlbumInfoRow) {
        UIPasteboard.general.string = row.copy ?? row.value
        copied = row.id
        Notice.announce(AlbumInfoWords.copied)
        let id = row.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.copiedSeconds))
            if copied == id { copied = nil }
        }
    }

    /// A MusicBrainz page, in Safari beside the app; iOS refusing it (Safari turned off in Screen Time) is said under
    /// the row, and to VoiceOver.
    private func open(_ row: AlbumInfoRow) {
        guard let link = row.link else { return }
        refused = nil
        let id = row.id
        openURL(link) { (accepted: Bool) in
            guard !accepted else { return }
            Task { @MainActor in
                refused = id
                Notice.announce(AlbumInfoWords.notOpened)
            }
        }
    }

    // MARK: asking

    /// What the answers are asked by: who, and which album - nil while deadwax can't be reached (nothing is asked).
    private var askKey: String? {
        reachability.online ? "\(server.person)|\(album.id)" : nil
    }

    private func ask() async {
        guard reachability.online, let client = server.client else { return }
        runs += 1
        let run = runs
        let id = album.id
        await AlbumInfoAsk.ask(albumID: id, client: client) { now in
            said = (run, id, now)
        }
        //? done or cancelled (deadwax out of reach, the sheet going): this asking reads nothing more, so what it last
        //? put is no longer reading - and was cut short if it still was. A later asking's answer is left alone.
        if var last = said, last.run == run, last.said.reading {
            last.said.reading = false
            last.said.cut = true
            said = last
        }
    }

    /// A two-letter country code in words, in the app's own English ("GB" -> "United Kingdom").
    static func countryName(_ code: String) -> String? {
        Locale(identifier: "en_GB").localizedString(forRegionCode: code)
    }
}

/// (R16) A phone row's room and hairline (`.kv`'s): 42 tall at least, half the gap above and below what it holds.
private struct AlbumInfoPhoneRule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, CGFloat(PhoneLook.kvGap) / 2)
            .lookHeight(PhoneLook.kvRow)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
    }
}
