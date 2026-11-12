import DeadwaxCore
import SwiftUI

/// You > Downloads (notes/ios-specs/phase2-downloads.md 6), an inset-grouped list, top to bottom: Storage - what's
/// used, the bar, the storage limit under it, other accounts' downloads; Download over - its two choices and the
/// network in use now; Downloading and Didn't download, only while there is something in them; Downloaded, every album
/// with a song on the phone, largest first; Remove All Downloads; and the last footer. With nothing downloaded,
/// waiting or failed, the lists give way to the Library's own empty words, the settings staying above them: they are
/// chosen before the first download.
///
/// Every word is DownloadWords', every rule Core's; this draws DownloadModel's records, by album (the app is album-
/// shaped: an album's page shows its songs one by one). A row opens its album's page, pushed on You's stack; a swipe
/// removes it (VoiceOver has it as an action); progress moves while the screen shows (`followProgress`).
struct DownloadsScreen: View {
    @Environment(DownloadModel.self) private var downloads
    @Environment(PlayerModel.self) private var player
    @Environment(ServerModel.self) private var server
    /// The phone's free space, read again as what's here changes.
    @State private var free: Int64 = DownloadStore.freeSpace() ?? 0
    @State private var askingRemoveAll = false

    var body: some View {
        let shelf = DownloadShelf(downloads, server: server)
        List {
            StorageSection(shelf: shelf, free: free)
            DownloadOverSection(waitingForIt: shelf.waitingForNetwork)
            if downloads.storeProblem != nil {
                // downloads are off for this launch: no list to draw, nothing to remove
                Section {} footer: { Text(DownloadWords.lastFooter) }
            } else if shelf.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DownloadWords.nothingYet)
                        Text(DownloadWords.nothingYetHow)
                            .font(.subheadline)
                            .foregroundStyle(Palette.quiet)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                } header: {
                    Text(DownloadWords.downloadedHeader)
                } footer: {
                    Text(DownloadWords.lastFooter)
                }
            } else {
                if !shelf.downloading.isEmpty {
                    DownloadingSection(rows: shelf.downloading, allWaitForWifi: shelf.allWaitForWifi)
                }
                if !shelf.failed.isEmpty {
                    FailedSection(rows: shelf.failed)
                }
                if !shelf.downloaded.isEmpty {
                    DownloadedSection(rows: shelf.downloaded)
                }
                Section {
                    Button(role: .destructive) {
                        askingRemoveAll = true
                    } label: {
                        Text(DownloadWords.removeAll)
                            .frame(maxWidth: .infinity)
                    }
                    // from the button itself, so it comes up from it ("The ••• menus open from the •••")
                    .confirmationDialog(DownloadWords.removeAllTitle, isPresented: $askingRemoveAll,
                                        titleVisibility: .visible) {
                        Button(DownloadWords.removeAll, role: .destructive) {
                            downloads.removeAll()
                            player.say(DownloadWords.removedAll)
                        }
                    } message: {
                        Text(DownloadWords.removeAllMessage(songs: shelf.songsHere, bytes: downloads.bytesHere))
                    }
                } footer: {
                    Text(DownloadWords.lastFooter)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DownloadWords.downloads)
        .animation(.default, value: shelf.isEmpty)
        .task { await downloads.followProgress() }
        .task(id: downloads.bytesHere) { free = DownloadStore.freeSpace() ?? free }
    }
}

// MARK: the records, by album

/// The screen's albums, made once per drawing from DownloadModel's records: each section's rows in its order, with the
/// words each draws.
private struct DownloadShelf {
    struct Going: Identifiable {
        let id: String
        let album: Album?
        let line: String
        /// The bar's fraction, while something of it is fetching.
        let fraction: Double?
        let records: [DownloadRecord]
    }

    struct Failed: Identifiable {
        let id: String
        let album: Album?
        let records: [DownloadRecord]
        let reason: ErrorWords.Line
    }

    struct Here: Identifiable {
        let id: String
        let album: Album?
        let bytes: Int64
        let line: String
        let verdict: DownloadRules.Verdict
    }

    let downloading: [Going]
    let failed: [Failed]
    let downloaded: [Here]
    let songsHere: Int
    let albumsHere: Int
    /// Every song on its way waits for Wi-Fi (the Downloading footer).
    let allWaitForWifi: Bool
    /// Something waits for a network Download over doesn't allow (Download over's footer, amber).
    let waitingForNetwork: Bool

    var isEmpty: Bool { downloading.isEmpty && failed.isEmpty && downloaded.isEmpty }

    @MainActor
    init(_ downloads: DownloadModel, server: ServerModel) {
        let going = downloads.downloading
        let waits = going.map { downloads.state($0.id) }
        downloading = Self.byAlbum(going).map { albumID, records in
            let all = downloads.songIDs(album: albumID)?.compactMap { downloads.records[$0] } ?? records
            let state = downloads.album(records: all.filter { $0.state != .failed })
            var here = 0, of = records.count, wait: DownloadWait?, fraction: Double?
            switch state {
            case .downloading(let h, let o, let f): here = h; of = o; fraction = f
            case .waiting(let reason, let h, let o): here = h; of = o; wait = reason
            default: break
            }
            let only = all.count == 1 ? downloads.song(all[0].id)?.title ?? PlayerWords.untitled : nil
            return Going(id: albumID, album: downloads.keptAlbum(albumID),
                         line: DownloadWords.downloadingRow(here: here, of: of, wait: wait, onlySong: only),
                         fraction: fraction, records: records)
        }
        allWaitForWifi = !waits.isEmpty && waits.allSatisfy { $0 == .waiting(.wifi) }
        waitingForNetwork = waits.contains { state in
            if case .waiting(let wait) = state { return [.wifi, .hotspot, .lowData].contains(wait) }
            return false
        }

        failed = Self.byAlbum(downloads.failed).map { albumID, records in
            let first = records.first { $0.failure != nil }
            let reason = DownloadWords.failure(first?.failure ?? .unsaved, songID: first?.id ?? "",
                                               server: server.address, admin: server.access.seesDetail)
            return Failed(id: albumID, album: downloads.keptAlbum(albumID), records: records, reason: reason)
        }

        let done = downloads.downloaded
        songsHere = done.count
        let here = Self.byAlbum(done).map { albumID, records -> Here in
            let album = downloads.keptAlbum(albumID)
            let bytes = records.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
            let total = max(album?.song?.count ?? album?.songCount ?? records.count, records.count)
            let verdict = DownloadRules.verdict(records.map { ($0.check ?? .unchecked, $0.flac != nil) })
            return Here(id: albumID, album: album, bytes: bytes,
                        line: DownloadWords.downloadedRow(here: records.count, of: total, bytes: bytes), verdict: verdict)
        }
        // largest first - the order iOS's own storage lists keep, since this is where space is made
        downloaded = here.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }
        albumsHere = here.count
    }

    /// The records grouped by album, in the order the first of each came.
    private static func byAlbum(_ records: [DownloadRecord]) -> [(String, [DownloadRecord])] {
        var order: [String] = []
        var groups: [String: [DownloadRecord]] = [:]
        for record in records {
            if groups[record.albumID] == nil { order.append(record.albumID) }
            groups[record.albumID, default: []].append(record)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}

// MARK: Storage (6.3)

private struct StorageSection: View {
    let shelf: DownloadShelf
    let free: Int64

    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server
    @State private var askingRemoveOthers = false

    var body: some View {
        @Bindable var downloads = downloads
        let bytes = downloads.bytesHere
        let limit = downloads.storageLimit
        let over = limit.bytes.map { bytes > $0 } ?? false
        Section {
            VStack(alignment: .leading, spacing: 8) {
                if shelf.songsHere > 0 {
                    let used = DownloadWords.used(bytes, limit: limit)
                    // one Text, so at the largest sizes it wraps as a sentence
                    Text("\(Text(used.amount).font(.title2.bold()))\(Text(used.rest).font(.title2).foregroundStyle(Palette.quiet))")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(DownloadWords.nothingYetHeadline)
                        .font(.headline)
                }
                DownloadBar(fraction: over ? 1 : fraction(bytes, limit: limit), amber: over)
                    .padding(.vertical, 2)
                Text(DownloadWords.usageLine(albums: shelf.albumsHere, songs: shelf.songsHere, free: free))
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
                if over {
                    Text(DownloadWords.overLimit(limit))
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DownloadWords.downloads)
            .accessibilityValue([DownloadWords.usageSpoken(bytes, limit: limit, free: free),
                                 over ? DownloadWords.overLimit(limit) : nil].compactMap { $0 }.joined(separator: ". "))

            Picker(DownloadWords.storageLimit, selection: $downloads.storageLimit) {
                ForEach(StorageLimit.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.menu)

            if downloads.otherBytes > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DownloadWords.otherAccounts)
                        Text(Bytes.words(downloads.otherBytes))
                            .font(.subheadline)
                            .foregroundStyle(Palette.quiet)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 8)
                    Button(DownloadWords.remove, role: .destructive) { askingRemoveOthers = true }
                        .buttonStyle(.borderless)
                        .confirmationDialog(DownloadWords.removeOthersTitle, isPresented: $askingRemoveOthers,
                                            titleVisibility: .visible) {
                            Button(DownloadWords.remove, role: .destructive) { downloads.removeOthers() }
                        } message: {
                            Text(DownloadWords.removeOthersMessage(downloads.otherBytes))
                        }
                }
            }

            if let problem = downloads.storeProblem {
                ErrorNote(text: DownloadWords.storeUnreadable, detail: problem)
                    .foregroundStyle(Palette.amber)
            }
        } header: {
            Text(DownloadWords.storage)
        } footer: {
            Text(DownloadWords.storageFooter)
        }
    }

    /// The bar's fill: what's here over the limit - with No limit, over what's here and the phone's free space.
    private func fraction(_ bytes: Int64, limit: StorageLimit) -> Double {
        let whole = limit.bytes ?? (bytes + free)
        return whole > 0 ? Double(bytes) / Double(whole) : 0
    }
}

// MARK: Download over (6.4)

/// Drawn as Normalization is (PlaybackSection): one row per choice, its note under it, the accent checkmark on the
/// chosen - a radio group for VoiceOver - and under them what's used now, amber while something waits for it.
private struct DownloadOverSection: View {
    let waitingForIt: Bool

    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability

    var body: some View {
        Section {
            ForEach(DownloadOver.allCases, id: \.self) { choice in
                row(choice)
            }
        } header: {
            Text(DownloadWords.downloadOver)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(DownloadWords.overNow(reachability.path, setting: downloads.downloadOver))
                    .foregroundStyle(waitingForIt ? Palette.amber : Palette.quiet)
                Text(DownloadWords.overKept)
            }
        }
    }

    private func row(_ choice: DownloadOver) -> some View {
        let chosen = downloads.downloadOver == choice
        let words = DownloadWords.over(choice)
        return Button {
            downloads.downloadOver = choice
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(words.name)
                        .foregroundStyle(.primary)
                    Text(words.note)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .opacity(chosen ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words.name)
        .accessibilityHint(words.note)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: Downloading (6.5)

private struct DownloadingSection: View {
    let rows: [DownloadShelf.Going]
    let allWaitForWifi: Bool

    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        Section {
            ForEach(rows) { row in
                AlbumLine(album: row.album, albumID: row.id, spoken: spoken(row), updates: row.fraction != nil) {
                    Text(row.line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                    if let fraction = row.fraction {
                        DownloadBar(fraction: fraction)
                            .padding(.top, 4)
                    }
                }
                .removable(name: row.album?.name) { downloads.remove(album: row.id) }
            }
        } header: {
            Text(DownloadWords.downloadingHeader)
        } footer: {
            let lines = [allWaitForWifi ? DownloadWords.allWaitForWifi : nil,
                         downloads.forceQuitShown ? DownloadWords.forceQuit : nil].compactMap { $0 }
            if !lines.isEmpty {
                Text(lines.joined(separator: "\n\n"))
            }
        }
    }

    /// "Dummy, Portishead, 4 of 12 songs, 40 percent" (6.8) - the section's header already says it is downloading.
    private func spoken(_ row: DownloadShelf.Going) -> String {
        [row.album?.name, row.album?.artist, row.line, row.fraction.map { DownloadWords.percent($0) }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: Didn't download (6.5)

private struct FailedSection: View {
    let rows: [DownloadShelf.Failed]

    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server

    var body: some View {
        Section {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    AlbumLine(album: row.album, albumID: row.id, spoken: spoken(row), tryAgain: { tryAgain(row) }) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            DownloadMark(mark: .failed, font: .caption)
                            Text(DownloadWords.didntDownload(row.records.count))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.amber)
                        }
                        Text(row.reason.said)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    } trailing: {
                        Button(DownloadWords.tryAgain) { tryAgain(row) }
                            .buttonStyle(.borderless)
                            .font(.subheadline.weight(.semibold))
                    }
                    // the raw words for whoever runs deadwax - ErrorNote's split, its own element
                    if server.access.seesDetail, let detail = row.reason.detail, !detail.isEmpty {
                        DisclosureGroup(ErrorWords.forWhoever) {
                            Text(detail)
                                .font(.footnote.monospaced())
                                .foregroundStyle(Palette.quiet)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.footnote)
                        .padding(.leading, AlbumLineInset.text)
                    }
                }
                .removable(name: row.album?.name) { downloads.remove(songs: row.records.map(\.id)) }
            }
            if rows.count > 1 {
                Button {
                    downloads.tryAllAgain()
                } label: {
                    Text(DownloadWords.tryAllAgain)
                        .foregroundStyle(Palette.accent)
                }
            }
        } header: {
            Text(DownloadWords.didntDownloadHeader)
        }
    }

    private func tryAgain(_ row: DownloadShelf.Failed) {
        for record in row.records { downloads.tryAgain(record.id) }
    }

    private func spoken(_ row: DownloadShelf.Failed) -> String {
        [row.album?.name, row.album?.artist, DownloadWords.didntDownload(row.records.count), row.reason.said]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: Downloaded (6.6)

private struct DownloadedSection: View {
    let rows: [DownloadShelf.Here]

    @Environment(DownloadModel.self) private var downloads
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Section {
            ForEach(rows) { row in
                let large = typeSize.isAccessibilitySize
                AlbumLine(album: row.album, albumID: row.id, spoken: spoken(row)) {
                    Text(row.line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                        .monospacedDigit()
                    if large { verdict(row.verdict).padding(.top, 2) }
                } trailing: {
                    if !large { verdict(row.verdict) }
                }
                .removable(name: row.album?.name) { downloads.remove(album: row.id) }
            }
        } header: {
            Text(DownloadWords.downloadedHeader)
        } footer: {
            Text(DownloadWords.downloadedFooter)
        }
    }

    /// The album's check: "Checked" with its mark in the library's green; "Checked by size" and "Checking…" quiet.
    @ViewBuilder
    private func verdict(_ verdict: DownloadRules.Verdict) -> some View {
        let words = DownloadWords.verdict(verdict)
        if verdict == .checked {
            Label(words, systemImage: DownloadWords.Mark.checked.rawValue)
                .labelStyle(VerdictLabel())
                .foregroundStyle(Palette.held)
        } else {
            Text(words)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
        }
    }

    /// "Dummy, Portishead, 12 songs · 412 MB, Checked".
    private func spoken(_ row: DownloadShelf.Here) -> String {
        [row.album?.name, row.album?.artist, row.line, DownloadWords.verdict(row.verdict)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// "Checked" with its mark: footnote, the mark at caption's size, side by side on the text's baseline.
private struct VerdictLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            configuration.icon.font(.caption)
            configuration.title.font(.footnote)
        }
    }
}

// MARK: one album's row

/// Where an album row's words start: the cover (44 points at the default size) and its gap - a detail under the row
/// lines up with them.
private enum AlbumLineInset {
    static let text: CGFloat = 44 + 12
}

/// An album's row on the screen (6.5, 6.6): the cover at the leading edge (44 points, growing with the text), the album
/// and the artist, the section's own lines under them, anything trailing. The cover and the words are one button - a
/// tap opens the album's page, pushed on You's stack - and one VoiceOver element, saying `spoken`; what trails (Try
/// again, the check) is a button of its own for a finger and, for VoiceOver, an action or a word already in `spoken`.
/// Every line wraps at accessibility sizes, the cover staying at the leading edge.
private struct AlbumLine<Lines: View, Trailing: View>: View {
    let album: Album?
    let albumID: String
    let spoken: String
    var updates = false
    var tryAgain: (() -> Void)?
    @ViewBuilder let lines: () -> Lines
    @ViewBuilder let trailing: () -> Trailing

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var cover: CGFloat = 44

    init(album: Album?, albumID: String, spoken: String, updates: Bool = false, tryAgain: (() -> Void)? = nil,
         @ViewBuilder lines: @escaping () -> Lines, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.album = album
        self.albumID = albumID
        self.spoken = spoken
        self.updates = updates
        self.tryAgain = tryAgain
        self.lines = lines
        self.trailing = trailing
    }

    var body: some View {
        let large = typeSize.isAccessibilitySize
        HStack(alignment: .center, spacing: 12) {
            Button {
                navigation.open(.album(album.map { AlbumRoute($0) } ?? AlbumRoute(id: albumID)))
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    CoverImage(id: album?.coverArt, size: cover)
                        .frame(width: cover, height: cover)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(album?.name ?? "")
                            .foregroundStyle(.primary)
                            .lineLimit(large ? nil : 1)
                        if let artist = album?.artist, !artist.isEmpty {
                            Text(artist)
                                .font(.subheadline)
                                .foregroundStyle(Palette.quiet)
                                .lineLimit(large ? nil : 1)
                        }
                        lines()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityAddTraits(updates ? [.isButton, .updatesFrequently] : .isButton)
            .accessibilityActions {
                if let tryAgain {
                    Button(DownloadWords.tryAgain, action: tryAgain)
                }
            }
            trailing()
                .accessibilityHidden(true)
        }
    }
}

extension AlbumLine where Trailing == EmptyView {
    init(album: Album?, albumID: String, spoken: String, updates: Bool = false, tryAgain: (() -> Void)? = nil,
         @ViewBuilder lines: @escaping () -> Lines) {
        self.init(album: album, albumID: albumID, spoken: spoken, updates: updates, tryAgain: tryAgain, lines: lines,
                  trailing: { EmptyView() })
    }
}

private extension View {
    /// The row's swipe: Remove (destructive, `trash`), which VoiceOver has as an action; its notice names the album.
    func removable(name: String?, remove: @escaping () -> Void) -> some View {
        modifier(Removable(name: name, remove: remove))
    }
}

private struct Removable: ViewModifier {
    let name: String?
    let remove: () -> Void

    @Environment(PlayerModel.self) private var player

    func body(content: Content) -> some View {
        content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(DownloadWords.remove, systemImage: "trash", role: .destructive) {
                remove()
                player.say(DownloadWords.removed(name ?? PlayerWords.untitled))
            }
        }
    }
}
