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
                    }
                }
        }
    }
}

/// Album info (James, 2026-11-15: "I'd like somewhere I can see all the album metadata like quality, media type,
/// etc."): the album as a whole, in a listener's words, grouped - pushed inside Info's stack from its album card, or in
/// AlbumInfoSheet from the album page's •••. Every line is Core's (AlbumInfo); this draws and asks.
///
/// At once, from the album in hand and this phone: the cover, title and artist, then Quality, The album and On this
/// phone. Then what deadwax adds (AlbumInfoAsk: the album again, the id bridge, the folders' files) - The release,
/// MusicBrainz and, for an admin, On the server - drawn once every answer is in or AlbumInfoWords.settleSeconds has
/// gone, a "Reading the album's files…" row in their place until then. Info's album may be a playlist's stub of it
/// (`partial`): its own lines wait for the album's answer too, since a stub's songs are only the playlist's. While
/// deadwax can't be reached nothing is asked: the release's lines are drawn from the album alone, with a line saying the
/// rest comes when deadwax is back.
///
/// An id, a path or a number read in columns is in the monospaced face, selectable, with a Copy button beside it
/// ("Copied" said to VoiceOver, the button's sign a tick for a moment); a MusicBrainz page opens in Safari, beside the
/// app (openURL), and if iOS refuses, a line under the row says so. A line wraps at every text size, never truncated;
/// VoiceOver reads each line's label and words as one.
struct AlbumInfoList: View {
    let album: Album

    @Environment(ServerModel.self) private var server
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @Environment(\.openURL) private var openURL
    @State private var said: (albumID: String, said: AlbumInfoAsk.Said)?
    /// The row whose Copy was tapped last, while its tick shows.
    @State private var copied: String?
    /// A link row iOS wouldn't open.
    @State private var refused: String?

    /// The header's cover.
    private static let cover: CGFloat = 60
    /// How long a Copy button shows its tick.
    private static let copiedSeconds = 2.0

    var body: some View {
        let answer = said.flatMap { $0.albumID == album.id ? $0.said : nil }
        //? the album's own answer once it has come; a playlist's stub of it is never counted from
        let whole = answer?.album ?? (album.partial ? nil : album)
        let asking = reachability.online && server.client != nil
        List {
            Section {
                header(whole ?? album)
            }

            if let whole {
                ForEach(AlbumInfo.local(album: whole, onPhone: onPhone(whole))) { section in
                    infoSection(section)
                }
            }

            if let answer {
                ForEach(AlbumInfo.fromServer(album: whole ?? album, extras: answer.extras, store: answer.store,
                                             files: answer.files, folders: server.access.isAdmin,
                                             countryName: Self.countryName)) { section in
                    infoSection(section)
                }
                if let failure = answer.filesFailure {
                    Section {
                        ErrorNote(failure, gone: AlbumInfoWords.filesGone, failed: AlbumInfoWords.filesFailed)
                    }
                } else if answer.reading {
                    Section { reading }
                }
            } else if asking {
                Section { reading }
            } else {
                // nothing asked: what the album says alone, and that the rest waits for deadwax
                if let whole {
                    ForEach(AlbumInfo.fromServer(album: whole, extras: nil, store: nil, files: nil, folders: false,
                                                 countryName: Self.countryName)) { section in
                        infoSection(section)
                    }
                }
                Section {
                    Text(AlbumInfoWords.offline)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AlbumInfoWords.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: askKey) { await ask() }
        .task { await downloads.followProgress() }
    }

    // MARK: drawing

    private func header(_ album: Album) -> some View {
        HStack(spacing: 12) {
            CoverImage(id: album.coverArt, size: Self.cover)
                .frame(width: Self.cover, height: Self.cover)
                .clipShape(Corners.artShape)
            VStack(alignment: .leading, spacing: 3) {
                Text(album.name ?? "")
                    .font(Typeface.headline)
                if let artist = album.artist, !artist.isEmpty {
                    Text(artist)
                        .font(Typeface.subheadline)
                        .foregroundStyle(Palette.quiet)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func infoSection(_ section: AlbumInfoSection) -> some View {
        Section {
            ForEach(section.rows) { row in
                infoRow(row)
            }
        } header: {
            Text(section.title).font(Typeface.footnote)
        }
    }

    @ViewBuilder
    private func infoRow(_ row: AlbumInfoRow) -> some View {
        switch row.style {
        case .plain:
            words(row)
                .accessibilityElement(children: .combine)
        case .copyable:
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                words(row)
                    .accessibilityElement(children: .combine)
                Button {
                    copy(row)
                } label: {
                    Image(systemName: copied == row.id ? AlbumInfoWords.copiedSymbol : AlbumInfoWords.copySymbol)
                        .font(Typeface.symbol(.body))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(AlbumInfoWords.copyName(row.label))
            }
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    open(row)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: AlbumInfoWords.outSymbol)
                            .font(Typeface.symbol(.body))
                            .foregroundStyle(Palette.quiet)
                            .accessibilityHidden(true)
                    }
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

    /// A line's label, its words, and the lines under them.
    private func words(_ row: AlbumInfoRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.label)
                .font(Typeface.subheadline)
                .foregroundStyle(Palette.quiet)
            Text(row.value)
                .font(row.style == .copyable ? Typeface.mono(.body) : Typeface.body)
                .textSelection(.enabled)
            ForEach(row.lines, id: \.self) { line in
                Text(line)
                    .font(Typeface.subheadline)
                    .foregroundStyle(Palette.quiet)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private var reading: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(AlbumInfoWords.reading)
                .font(Typeface.footnote)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// On this phone's line - nil while there is no download store open (signed out).
    private func onPhone(_ album: Album) -> AlbumInfoRow? {
        let songs = album.song ?? []
        guard downloads.isOpen, !songs.isEmpty else { return nil }
        let here = downloads.here(songs)
        return AlbumInfo.onPhone(downloads.album(songs), here: here.count, of: songs.count, bytes: here.bytes)
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
        let id = album.id
        await AlbumInfoAsk.ask(albumID: id, client: client) { now in
            said = (id, now)
        }
    }

    /// A two-letter country code in words, in the app's own English ("GB" -> "United Kingdom").
    static func countryName(_ code: String) -> String? {
        Locale(identifier: "en_GB").localizedString(forRegionCode: code)
    }
}
