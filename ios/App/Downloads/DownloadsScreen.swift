import DeadwaxCore
import SwiftUI

/// You > Downloads (notes/ios-specs/phase2-downloads.md 6), an inset-grouped list, top to bottom: Storage - what's
/// used, the bar, the storage limit under it, other accounts' downloads; Your library (Phase 3, phase3-autodownload.md
/// 3.1) - its switch, what fits, the last check, the question an empty list asks; Download over - its two choices and the
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
            if downloads.storeProblem == nil {
                LibrarySection()
            }
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
                if !shelf.downloading.isEmpty || downloads.libraryProgress != nil || !shelf.playlistsGoing.isEmpty {
                    DownloadingSection(rows: shelf.downloading, playlists: shelf.playlistsGoing,
                                       allWaitForWifi: shelf.allWaitForWifi)
                }
                if !shelf.failed.isEmpty {
                    FailedSection(rows: shelf.failed)
                }
                if !shelf.downloaded.isEmpty || !shelf.playlistsHere.isEmpty {
                    DownloadedSection(rows: shelf.downloaded, playlists: shelf.playlistsHere)
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
                        let scope = downloads.follower.scope ?? AlbumScope.albums(for: server.me)
                        Text([DownloadWords.removeAllMessage(songs: shelf.songsHere, bytes: downloads.bytesHere),
                              downloads.follower.on ? AutoDownloadWords.removeAllToo(scope) : nil,
                              PlaylistDownloadWords.removeAllToo(playlists: PlaylistDownloads.shelf(downloads.playlists.kept).count)]
                            .compactMap { $0 }.joined(separator: " "))
                    }
                } footer: {
                    Text(DownloadWords.lastFooter)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DownloadWords.downloads)
        .animation(.default, value: shelf.isEmpty)
        .refreshable {
            // a pull checks your library now (`byHand`), held until the check has answered - and looks at the downloaded
            // playlists (slice 3)
            downloads.playlists.look(.byHand)
            let follower = downloads.follower
            guard follower.on else { return }
            follower.check(.byHand)
            for _ in 0..<100 where follower.checking {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
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

    /// (slice 3) A downloaded playlist's row: Downloading's while songs of it are to come, Downloaded's while some are
    /// here.
    struct PlaylistLine: Identifiable {
        let id: String
        let name: String
        let coverArt: String?
        let line: String
        let spoken: String
        let fraction: Double?
    }

    let downloading: [Going]
    let failed: [Failed]
    let downloaded: [Here]
    let playlistsGoing: [PlaylistLine]
    let playlistsHere: [PlaylistLine]
    let songsHere: Int
    let albumsHere: Int
    /// Every song on its way waits for Wi-Fi (the Downloading footer).
    let allWaitForWifi: Bool
    /// Something waits for a network Download over doesn't allow (Download over's footer, amber).
    let waitingForNetwork: Bool

    let library: Bool

    var isEmpty: Bool {
        downloading.isEmpty && failed.isEmpty && downloaded.isEmpty && !library && playlistsGoing.isEmpty
            && playlistsHere.isEmpty
    }

    @MainActor
    init(_ downloads: DownloadModel, server: ServerModel) {
        library = downloads.libraryProgress != nil
        let going = downloads.downloading
        let waits = going.map { downloads.state($0.id) }
        // (slice 3) a downloaded playlist's songs are its own row's - not an album's, unless asked for another way too,
        // or (its review) the playlist's answer no longer lists it: then its album's, so it is on some row
        let listing = PlaylistDownloads.listing(downloads.playlists.kept)
        let ownRows = going.filter { (record: DownloadRecord) -> Bool in
            PlaylistDownloads.inDownloadingAlbumRow(record.id, origins: downloads.origins[record.id] ?? [.song],
                                                    listing: listing)
        }
        let shelf = PlaylistDownloads.shelf(downloads.playlists.kept)
        let entries = shelf.compactMap { (playlist: Playlist) -> KeptPlaylist? in
            downloads.playlists.entry(playlist.id)
        }
        playlistsGoing = entries.compactMap { (entry: KeptPlaylist) -> PlaylistLine? in
            guard let going = downloads.playlistProgress(entry) else { return nil }
            let line = PlaylistDownloadWords.downloadingRow(going.progress, wait: going.wait)
            let name = entry.name.isEmpty ? PlayerWords.untitled : entry.name
            return PlaylistLine(id: entry.id, name: name, coverArt: entry.answer?.playlist.coverArt, line: line,
                            spoken: PlaylistDownloadWords.downloadingSpoken(name, going.progress, wait: going.wait),
                            fraction: going.fetching ? going.progress.fraction : nil)
        }
        playlistsHere = entries.compactMap { (entry: KeptPlaylist) -> PlaylistLine? in
            let here = downloads.playlistHere(entry)
            guard here.here > 0 || entry.songIDs.isEmpty else { return nil }
            let line = DownloadWords.downloadedRow(here: here.here, of: here.of, bytes: here.bytes)
            let name = entry.name.isEmpty ? PlayerWords.untitled : entry.name
            return PlaylistLine(id: entry.id, name: name, coverArt: entry.answer?.playlist.coverArt, line: line,
                            spoken: "\(name), \(line)", fraction: nil)
        }
        downloading = Self.byAlbum(ownRows).map { albumID, records in
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
        albumsHere = Set(done.map(\.albumID)).count
        // (slice 3) a song only downloaded playlists keep is under its playlist's row, not an album's - unless (its
        // review) none of them lists it now
        let albumRows = done.filter { (record: DownloadRecord) -> Bool in
            PlaylistDownloads.inDownloadedAlbumRow(record.id, origins: downloads.origins[record.id] ?? [.song],
                                                   listing: listing)
        }
        let here = Self.byAlbum(albumRows).map { albumID, records -> Here in
            let album = downloads.keptAlbum(albumID)
            let bytes = records.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
            let total = max(album?.song?.count ?? album?.songCount ?? records.count, records.count)
            let verdict = DownloadRules.verdict(records.map { ($0.check ?? .unchecked, $0.flac != nil) })
            return Here(id: albumID, album: album, bytes: bytes,
                        line: DownloadWords.downloadedRow(here: records.count, of: total, bytes: bytes), verdict: verdict)
        }
        // largest first - the order iOS's own storage lists keep, since this is where space is made
        downloaded = here.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }
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

// MARK: Your library (phase3-autodownload.md 3.1)

/// Between Storage and Download over - the library is what fills the storage: the switch, its note under it (drawn as
/// iOS's Settings draws a switch with an explanation); on, the fit line (amber when not all fit) or, while albums' songs
/// are read, the reading line and its bar; the question an empty list or a large drop asks, as an amber row with its
/// two buttons; and the footer - when it was checked, or that it couldn't be (ErrorNote's split).
private struct LibrarySection: View {
    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server
    /// Turning it off with albums of it here asks first (after the review): what goes, with Cancel.
    @State private var askingOff = false
    @State private var offAlbums = 0
    @State private var offBytes: Int64 = 0

    var body: some View {
        let follower = downloads.follower
        let scope = follower.scope ?? AlbumScope.albums(for: server.me)
        Section {
            Toggle(isOn: Binding(get: { follower.on }, set: { turn($0) })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AutoDownloadWords.switchName(scope))
                    Text(AutoDownloadWords.note(scope))
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AutoDownloadWords.switchName(scope))
            .accessibilityHint(AutoDownloadWords.note(scope))
            .accessibilityValue(follower.on ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { turn(!follower.on) }
            // from the switch itself, so it comes up from it
            .confirmationDialog(AutoDownloadWords.offTitle(scope, albums: offAlbums), isPresented: $askingOff,
                                titleVisibility: .visible) {
                Button(AutoDownloadWords.offAndRemove, role: .destructive) { follower.on = false }
            } message: {
                Text(AutoDownloadWords.offMessage(bytes: offBytes))
            }
            if follower.on {
                fit(follower, scope: scope)
                ChargingToggle(scope: scope)
                if follower.asks, let held = follower.held,
                   let question = AutoDownloadWords.question(held, scope: scope, here: albumsHere(follower)) {
                    QuestionRow(question: question)
                }
            }
        } header: {
            Text(AutoDownloadWords.header(scope))
        } footer: {
            if follower.on { footer(follower) }
        }
    }

    /// The switch, turned: on at once; off at once only with nothing of it here - else asked first, and nothing goes
    /// until Turn Off and Remove (the switch stays on meanwhile, and on Cancel).
    private func turn(_ on: Bool) {
        let follower = downloads.follower
        guard !on, follower.on else {
            follower.on = on
            return
        }
        let loses = downloads.switchOffLoses
        guard loses.albums > 0 else {
            follower.on = false
            return
        }
        offAlbums = loses.albums
        offBytes = loses.bytes
        askingOff = true
    }

    @ViewBuilder
    private func fit(_ follower: LibraryFollower, scope: AlbumScope) -> some View {
        let reading = follower.reading
        if follower.readsPending, reading.of > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text(AutoDownloadWords.reading(scope, read: reading.read, of: reading.of))
                    .fixedSize(horizontal: false, vertical: true)
                DownloadBar(fraction: Double(reading.read) / Double(reading.of))
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AutoDownloadWords.reading(scope, read: reading.read, of: reading.of))
            .accessibilityAddTraits(.updatesFrequently)
        } else if let plan = downloads.libraryFill {
            Text(AutoDownloadWords.fit(plan, limit: downloads.storageLimit, bytes: plan.bytes))
                .foregroundStyle(plan.allFit ? Color.primary : Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func footer(_ follower: LibraryFollower) -> some View {
        if let error = follower.lastError {
            ErrorNote(error, failed: AutoDownloadWords.couldntCheck)
                .foregroundStyle(Palette.amber)
        } else {
            // read again every half minute, so "3 minutes ago" moves
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(AutoDownloadWords.checked(follower.lastAnswered, now: ListenTracker.wallMs()))
            }
        }
    }

    /// The library's albums with a song on this phone - the empty list's question names them.
    private func albumsHere(_ follower: LibraryFollower) -> Int {
        var albums = Set<String>()
        for record in downloads.records.values where record.state == .done && downloads.keptByLibrary(record.id) {
            albums.insert(record.albumID)
        }
        return albums.count
    }
}

/// (slice 3, 3.1's third row) Only while charging, under the fit line while Download your library is on - drawn as
/// iOS's Settings draws a switch with an explanation, VoiceOver reading it as one.
private struct ChargingToggle: View {
    let scope: AlbumScope

    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        Toggle(isOn: Binding(get: { downloads.onlyWhileCharging },
                             set: { (on: Bool) -> Void in downloads.onlyWhileCharging = on })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AutoDownloadWords.onlyWhileCharging)
                Text(AutoDownloadWords.chargingNote(scope))
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AutoDownloadWords.onlyWhileCharging)
        .accessibilityHint(AutoDownloadWords.chargingNote(scope))
        .accessibilityValue(downloads.onlyWhileCharging ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { downloads.onlyWhileCharging.toggle() }
    }
}

/// The empty list's or the large drop's question (2.3), amber, with Keep Them and Remove - Remove asking nothing more:
/// the question is the asking, and what it lets go still waits for a check ten minutes on to agree.
private struct QuestionRow: View {
    let question: String

    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .foregroundStyle(Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
            Text(AutoDownloadWords.questionNote)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(AutoDownloadWords.keepThem) { downloads.follower.keepThem() }
                    .buttonStyle(.bordered)
                Button(AutoDownloadWords.remove, role: .destructive) { downloads.follower.removeThem() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

/// (slice 3) A downloaded playlist's row - in Downloading ("3 of 12 songs to go", the bar while its songs fetch) and in
/// Downloaded ("12 songs · 412 MB"): its mosaic (not kept with the download, question 15: with no connection it is
/// the cover cache's, or the empty cover), its name and line; a tap opens its page, pushed on You's stack. One VoiceOver element.
private struct PlaylistLineRow: View {
    let row: DownloadShelf.PlaylistLine

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var cover: CGFloat = 44

    var body: some View {
        let large = typeSize.isAccessibilitySize
        Button {
            navigation.open(.playlist(PlaylistRoute(id: row.id)))
        } label: {
            HStack(alignment: .center, spacing: 12) {
                PlaylistCover(id: row.coverArt, side: cover, pixels: CoverSize.row, corner: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .foregroundStyle(.primary)
                        .lineLimit(large ? nil : 1)
                    Text(row.line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if let fraction = row.fraction {
                        DownloadBar(fraction: fraction)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
        .accessibilityAddTraits(row.fraction != nil ? [.isButton, .updatesFrequently] : .isButton)
    }
}

/// Downloading's one row for your library (3.3): its name, "38 of 412 albums to go · 12.4 GB" or what it waits for,
/// and the bar; a tap opens the Library's Downloaded. One VoiceOver element ("Your library, 38 of 412 albums to go,
/// 12.4 GB, 40 percent").
private struct LibraryDownloadingRow: View {
    let progress: LibraryDownloads.Progress

    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        let scope = downloads.follower.scope ?? AlbumScope.albums(for: server.me)
        let line = downloads.libraryWait.map { DownloadWords.wait($0) } ?? AutoDownloadWords.downloadingRow(progress)
        Button {
            navigation.open(.downloaded)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: DownloadWords.downloadSymbol)
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                    .frame(minWidth: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AutoDownloadWords.downloadingTitle(scope))
                        .foregroundStyle(.primary)
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                    DownloadBar(fraction: progress.fraction)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(downloads.libraryWait.map { "\(AutoDownloadWords.downloadingTitle(scope)), \(DownloadWords.wait($0))" }
                            ?? AutoDownloadWords.downloadingSpoken(scope, progress))
        .accessibilityAddTraits([.isButton, .updatesFrequently])
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
    /// (slice 3) A row per downloaded playlist with songs of it to come.
    let playlists: [DownloadShelf.PlaylistLine]
    let allWaitForWifi: Bool

    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        Section {
            if let progress = downloads.libraryProgress {
                LibraryDownloadingRow(progress: progress)
            }
            ForEach(playlists) { row in
                PlaylistLineRow(row: row)
                    .removable(name: row.name) { downloads.remove(playlist: row.id) }
            }
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

    var body: some View {
        Section {
            ForEach(rows) { row in
                FailedRow(row: row)
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
}

/// One album of Didn't download: its songs that failed, why, Try Again - and its Remove, which on an album your library
/// keeps with songs of it here asks first (after the review): keeping it off lets go of those too.
private struct FailedRow: View {
    let row: DownloadShelf.Failed

    @Environment(DownloadModel.self) private var downloads
    @Environment(ServerModel.self) private var server
    @Environment(PlayerModel.self) private var player
    @State private var askingKeepOff = false
    @State private var songsHere = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AlbumLine(album: row.album, albumID: row.id, spoken: spoken, tryAgain: { tryAgain() }) {
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
                Button(DownloadWords.tryAgain) { tryAgain() }
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
        .removable(name: row.album?.name, asks: asks, ask: ask, offered: removes) { remove() }
        // keeping a library album off lets go of its songs already here too: said, with Cancel
        .confirmationDialog(AutoDownloadWords.keepOffTitle(name), isPresented: $askingKeepOff,
                            titleVisibility: .visible) {
            Button(DownloadWords.removeDownload, role: .destructive) {
                remove()
                player.say(DownloadWords.removed(name))
            }
        } message: {
            Text(AutoDownloadWords.keepOffMessage(downloads.libraryScope, songsHere: songsHere))
        }
    }

    private var name: String { row.album?.name ?? PlayerWords.untitled }

    /// A song of the row your library keeps: its Remove keeps the album off - else the library would ask for it again.
    private var keepsOff: Bool { row.records.contains { downloads.keptByLibrary($0.id) } }

    /// Its Remove asks first: the album would be kept off with songs of it here only the library wants.
    private var asks: Bool { keepsOff && downloads.keptOffLoses(album: row.id) > 0 }

    /// (slice 3) Its Remove would take something: not every failed song is one a downloaded playlist keeps (that
    /// playlist's Remove Download is its own).
    private var removes: Bool {
        row.records.contains { (record: DownloadRecord) -> Bool in
            !downloads.staysAfterRemove(record.id, album: keepsOff ? row.id : nil)
        }
    }

    private func ask() {
        songsHere = downloads.keptOffLoses(album: row.id)
        askingKeepOff = true
    }

    /// The Remove: the failed songs let go - and with a song your library keeps, the album kept off (its songs
    /// downloaded by hand stay).
    private func remove() {
        if keepsOff {
            downloads.remove(failed: row.records.map(\.id), album: row.id)
        } else {
            downloads.remove(songs: row.records.map(\.id))
        }
    }

    private func tryAgain() {
        for record in row.records { downloads.tryAgain(record.id) }
    }

    private var spoken: String {
        [row.album?.name, row.album?.artist, DownloadWords.didntDownload(row.records.count), row.reason.said]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: Downloaded (6.6)

private struct DownloadedSection: View {
    let rows: [DownloadShelf.Here]
    /// (slice 3) The downloaded playlists with songs of them here, first.
    let playlists: [DownloadShelf.PlaylistLine]

    @Environment(DownloadModel.self) private var downloads
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Section {
            ForEach(playlists) { row in
                PlaylistLineRow(row: row)
                    .removable(name: row.name) { downloads.remove(playlist: row.id) }
            }
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
    /// `asks`: the Remove asks first (`ask`) - drawn red without the destructive role, so a full swipe doesn't take the
    /// row out before the answer.
    /// `offered`: false when the Remove would take nothing (slice 3) - no swipe at all.
    func removable(name: String?, asks: Bool = false, ask: @escaping () -> Void = {}, offered: Bool = true,
                   remove: @escaping () -> Void) -> some View {
        modifier(Removable(name: name, asks: asks, ask: ask, offered: offered, remove: remove))
    }
}

private struct Removable: ViewModifier {
    let name: String?
    let asks: Bool
    let ask: () -> Void
    let offered: Bool
    let remove: () -> Void

    @Environment(PlayerModel.self) private var player

    func body(content: Content) -> some View {
        content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !offered {
                EmptyView()
            } else if asks {
                Button(DownloadWords.remove, systemImage: "trash") { ask() }
                    .tint(.red) // the destructive swipe's own red
            } else {
                Button(DownloadWords.remove, systemImage: "trash", role: .destructive) {
                    remove()
                    player.say(DownloadWords.removed(name ?? PlayerWords.untitled))
                }
            }
        }
    }
}
