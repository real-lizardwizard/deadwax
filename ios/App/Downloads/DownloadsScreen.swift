import DeadwaxCore
import SwiftUI

/// Settings > Downloads (notes/ios-specs/phase2-downloads.md 6; You > Downloads until 16 Nov), an inset-grouped list,
/// top to bottom: Storage - what's used, the bar, the storage limit under it, other accounts' downloads; Your library
/// (Phase 3, phase3-autodownload.md 3.1) - its switch, what fits, the last check, the question an empty list asks;
/// Download over - one row, a menu of its two choices since 16 Nov, and the network in use now under it; Downloading
/// and Didn't download, only while there is something in them; Downloaded, every album
/// with a song on the phone, largest first; Remove All Downloads; and the last footer. With nothing downloaded,
/// waiting or failed, the lists give way to the Library's own empty words, the settings staying above them: they are
/// chosen before the first download.
///
/// Every word is DownloadWords', every rule Core's; this draws DownloadModel's records, by album (the app is album-
/// shaped: an album's page shows its songs one by one). A row opens its album's page, pushed on Settings' stack; a swipe
/// removes it (VoiceOver has it as an action); progress moves while the screen shows (`followProgress`).
///
/// (The redesign, slice R9) Flat, as Settings' other pages: a plain list on the page's black - no inset-grouped grey
/// cells - each group's legend and its note rows of their own (ListLegend, ListNote), each album's and playlist's row
/// iArtists' tall row (the cover at 44, the name, the line under it in the second colour, its hairline), the switches
/// the purple ones, Remove All Downloads the red button. Every row, choice and swipe is as it was: the Storage limit and
/// Download over among them.
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
                Section {
                    ListNote(words: DownloadWords.lastFooter(Platform.device))
                }
                .flatRows()
            } else if shelf.isEmpty {
                Section {
                    ListLegend(words: DownloadWords.downloadedHeader)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DownloadWords.nothingYet)
                            .font(Typeface.Phone.text(.row))
                        Text(DownloadWords.nothingYetHow)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.t2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    ListNote(words: DownloadWords.lastFooter(Platform.device))
                }
                .flatRows()
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
                        ButtonWords(words: DownloadWords.removeAll)
                    }
                    .buttonStyle(DWButtonStyle(kind: .danger, fills: true))
                    .padding(.top, CGFloat(PhoneLook.groupAbove))
                    // from the button itself, so it comes up from it ("The ••• menus open from the •••")
                    .confirmationDialog(DownloadWords.removeAllTitle, isPresented: $askingRemoveAll,
                                        titleVisibility: .visible) {
                        Button(DownloadWords.removeAll, role: .destructive) {
                            downloads.removeAll()
                            player.say(DownloadWords.removedAll)
                        }
                        Platform.dialogCancel()
                    } message: {
                        Text(shelf.removeAllMessage(downloads, server: server))
                    }
                    ListNote(words: DownloadWords.lastFooter(Platform.device))
                }
                .flatRows()
            }
        }
        // (R9) flat: a plain list, as the Library's are, no grey cells - each group's legend and note rows of its own
        // (a plain list's header would stand pinned on a bar), each row its own hairline
        .listStyle(.plain)
        .navigationTitle(DownloadWords.downloads)
        .animation(.default, value: shelf.isEmpty)
        .pullToRefresh {
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
/// words each draws. (R9) The Mac's Downloaded draws its columns from the same shelf (MacDownloadedPage).
struct DownloadShelf {
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
        /// (R9) Its songs here, of how many the album has, and when each came - the Mac's columns.
        let songs: Int
        let total: Int
        let doneAt: [Int64?]
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
        /// (R9) Downloaded's: its songs here, of how many, and their size - the Mac's columns.
        var songs = 0
        var total = 0
        var bytes: Int64 = 0
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
            let line = PlaylistDownloadWords.downloadingRow(going.progress, wait: going.wait, device: Platform.device)
            let name = entry.name.isEmpty ? PlayerWords.untitled : entry.name
            return PlaylistLine(id: entry.id, name: name, coverArt: entry.answer?.playlist.coverArt, line: line,
                            spoken: PlaylistDownloadWords.downloadingSpoken(name, going.progress, wait: going.wait, device: Platform.device),
                            fraction: going.fetching ? going.progress.fraction : nil)
        }
        playlistsHere = entries.compactMap { (entry: KeptPlaylist) -> PlaylistLine? in
            let here = downloads.playlistHere(entry)
            guard here.here > 0 || entry.songIDs.isEmpty else { return nil }
            let line = DownloadWords.downloadedRow(here: here.here, of: here.of, bytes: here.bytes)
            let name = entry.name.isEmpty ? PlayerWords.untitled : entry.name
            return PlaylistLine(id: entry.id, name: name, coverArt: entry.answer?.playlist.coverArt, line: line,
                            spoken: "\(name), \(line)", fraction: nil, songs: here.here, total: here.of, bytes: here.bytes)
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
                         line: DownloadWords.downloadingRow(here: here, of: of, wait: wait, onlySong: only, device: Platform.device),
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
                                               server: server.address, admin: server.access.seesDetail, device: Platform.device)
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
                        line: DownloadWords.downloadedRow(here: records.count, of: total, bytes: bytes), verdict: verdict,
                        songs: records.count, total: total, doneAt: records.map(\.doneAt))
        }
        // largest first - the order iOS's own storage lists keep, since this is where space is made
        downloaded = here.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }
    }

    /// Remove All Downloads' question: what goes, and that your library and the downloaded playlists go too - Settings >
    /// Downloads' and (R9) the Mac's Downloaded's Remove all….
    @MainActor
    func removeAllMessage(_ downloads: DownloadModel, server: ServerModel) -> String {
        let scope = downloads.follower.scope ?? AlbumScope.albums(for: server.me)
        return [DownloadWords.removeAllMessage(songs: songsHere, bytes: downloads.bytesHere, device: Platform.device),
                downloads.follower.on ? AutoDownloadWords.removeAllToo(scope) : nil,
                PlaylistDownloadWords.removeAllToo(playlists: PlaylistDownloads.shelf(downloads.playlists.kept).count,
                                                   device: Platform.device)]
            .compactMap { $0 }.joined(separator: " ")
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
            ListLegend(words: DownloadWords.storage)
            VStack(alignment: .leading, spacing: 8) {
                if shelf.songsHere > 0 {
                    let used = DownloadWords.used(bytes, limit: limit)
                    // one Text, so at the largest sizes it wraps as a sentence
                    Text("\(Text(used.amount).font(Typeface.title2.bold()))\(Text(used.rest).font(Typeface.title2).foregroundStyle(DWPalette.t2))")
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(DownloadWords.nothingYetHeadline)
                        .font(Typeface.headline)
                }
                DownloadBar(fraction: over ? 1 : fraction(bytes, limit: limit), amber: over)
                    .padding(.vertical, 2)
                Text(DownloadWords.usageLine(albums: shelf.albumsHere, songs: shelf.songsHere, free: free, device: Platform.device))
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                if over {
                    Text(DownloadWords.overLimit(limit))
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.amberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DownloadWords.downloads)
            .accessibilityValue([DownloadWords.usageSpoken(bytes, limit: limit, free: free, device: Platform.device),
                                 over ? DownloadWords.overLimit(limit) : nil].compactMap { $0 }.joined(separator: ". "))

            SettingsChoiceRow(title: DownloadWords.storageLimit) {
                Picker(DownloadWords.storageLimit, selection: $downloads.storageLimit) {
                    ForEach(StorageLimit.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.menu)
            }

            if downloads.otherBytes > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DownloadWords.otherAccounts(Platform.device))
                            .font(Typeface.Phone.text(.row))
                        Text(Bytes.words(downloads.otherBytes))
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.t2)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 8)
                    Button(DownloadWords.remove, role: .destructive) { askingRemoveOthers = true }
                        .buttonStyle(DWButtonStyle(kind: .danger, size: .small))
                        .confirmationDialog(DownloadWords.removeOthersTitle, isPresented: $askingRemoveOthers,
                                            titleVisibility: .visible) {
                            Button(DownloadWords.remove, role: .destructive) { downloads.removeOthers() }
                            Platform.dialogCancel()
                        } message: {
                            Text(DownloadWords.removeOthersMessage(downloads.otherBytes, device: Platform.device))
                        }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
            }

            if let problem = downloads.storeProblem {
                ErrorNote(text: DownloadWords.storeUnreadable(Platform.device), detail: problem)
                    .foregroundStyle(DWPalette.amberText)
            }
            ListNote(words: DownloadWords.storageFooter)
        }
        .flatRows()
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
            ListLegend(words: AutoDownloadWords.header(scope))
            // (R9's review) the switch is iOS's own switch to VoiceOver (PhoneSwitchStyle's representation; the Mac's
            // Toggle): its name, its note as the hint, and its state - no element of our own over it
            Toggle(isOn: Binding(get: { follower.on }, set: { turn($0) })) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(AutoDownloadWords.switchName(scope))
                    Text(AutoDownloadWords.note(scope, device: Platform.device))
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
            .accessibilityLabel(AutoDownloadWords.switchName(scope))
            .accessibilityHint(AutoDownloadWords.note(scope, device: Platform.device))
            .settingsSwitch()
            // from the switch itself, so it comes up from it
            .confirmationDialog(AutoDownloadWords.offTitle(scope, albums: offAlbums), isPresented: $askingOff,
                                titleVisibility: .visible) {
                Button(AutoDownloadWords.offAndRemove, role: .destructive) { follower.on = false }
                Platform.dialogCancel()
            } message: {
                Text(AutoDownloadWords.offMessage(bytes: offBytes, device: Platform.device))
            }
            if follower.on {
                fit(follower, scope: scope)
                ChargingToggle(scope: scope)
                if follower.asks, let held = follower.held,
                   let question = AutoDownloadWords.question(held, scope: scope, here: albumsHere(follower), device: Platform.device) {
                    QuestionRow(question: question)
                }
                footer(follower)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .padding(.top, SettingsLook.noteAbove)
            }
        }
        .flatRows()
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
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AutoDownloadWords.reading(scope, read: reading.read, of: reading.of))
            .accessibilityAddTraits(.updatesFrequently)
        } else if let plan = downloads.libraryFill {
            Text(AutoDownloadWords.fit(plan, limit: downloads.storageLimit, bytes: plan.bytes, device: Platform.device))
                .font(Typeface.Phone.text(.row))
                .foregroundStyle(plan.allFit ? DWPalette.text : DWPalette.amberText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
                .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func footer(_ follower: LibraryFollower) -> some View {
        if let error = follower.lastError {
            ErrorNote(error, failed: AutoDownloadWords.couldntCheck)
                .foregroundStyle(DWPalette.amberText)
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
/// iOS's Settings draws a switch with an explanation, VoiceOver reading it as one: (R9's review) iOS's own switch, its
/// name, its note as the hint, and its state.
private struct ChargingToggle: View {
    let scope: AlbumScope

    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        Toggle(isOn: Binding(get: { downloads.onlyWhileCharging },
                             set: { (on: Bool) -> Void in downloads.onlyWhileCharging = on })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AutoDownloadWords.onlyWhileCharging)
                Text(AutoDownloadWords.chargingNote(scope, device: Platform.device))
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
        }
        .accessibilityLabel(AutoDownloadWords.onlyWhileCharging)
        .accessibilityHint(AutoDownloadWords.chargingNote(scope, device: Platform.device))
        .settingsSwitch()
    }
}

/// The empty list's or the large drop's question (2.3), amber, with Keep Them and Remove - Remove asking nothing more:
/// the question is the asking, and what it lets go still waits for a check ten minutes on to agree. (R9's review) At the
/// accessibility sizes the two go one over the other, each across the row on up to three lines.
private struct QuestionRow: View {
    let question: String

    @Environment(DownloadModel.self) private var downloads
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 10) {
            Text(question)
                .foregroundStyle(DWPalette.amberText)
                .fixedSize(horizontal: false, vertical: true)
            Text(AutoDownloadWords.questionNote)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
                .fixedSize(horizontal: false, vertical: true)
            if stacked {
                VStack(alignment: .leading, spacing: 10) { buttons(stacked: true) }
            } else {
                HStack(spacing: 12) { buttons(stacked: false) }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
    }

    @ViewBuilder private func buttons(stacked: Bool) -> some View {
        Button {
            downloads.follower.keepThem()
        } label: {
            ButtonWords(words: AutoDownloadWords.keepThem)
        }
        .buttonStyle(DWButtonStyle(size: .small, fills: stacked))
        Button(role: .destructive) {
            downloads.follower.removeThem()
        } label: {
            ButtonWords(words: AutoDownloadWords.remove)
        }
        .buttonStyle(DWButtonStyle(kind: .danger, size: .small, fills: stacked))
    }
}

/// (R9's review) A button's words on Settings > Downloads: one line, three at the accessibility sizes, centred - the
/// innermost limit, so it holds over DWButtonStyle's one (the button fills its row there, so they can wrap).
private struct ButtonWords: View {
    let words: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(words)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
    }
}

/// (slice 3) A downloaded playlist's row - in Downloading ("3 of 12 songs to go", the bar while its songs fetch) and in
/// Downloaded ("12 songs · 412 MB"): its mosaic (not kept with the download, question 15: with no connection it is
/// the cover cache's, or the empty cover), its name and line; a tap opens its page, pushed on You's stack. One VoiceOver element.
private struct PlaylistLineRow: View {
    let row: DownloadShelf.PlaylistLine

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let large = typeSize.isAccessibilitySize
        Button {
            navigation.open(.playlist(PlaylistRoute(id: row.id)))
        } label: {
            // (R9) iArtists' tall row: the cover at 44, the name, the line under it in the second colour, the hairline
            HStack(alignment: .center, spacing: 0) {
                PlaylistCover(id: row.coverArt, side: LibraryLook.rowCover, pixels: CoverSize.row)
                    .frame(width: LibraryLook.rowCover, height: LibraryLook.rowCover)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .font(Typeface.body)
                        .foregroundStyle(DWPalette.text)
                        .lineLimit(large ? nil : 1)
                    Text(row.line)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let fraction = row.fraction {
                        DownloadBar(fraction: fraction)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, LibraryLook.rowTextSide)
                .frame(maxWidth: .infinity, alignment: .leading)
                LibraryChevron()
            }
            .tallRow(macRoom: 4)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
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
        let line = downloads.libraryWait.map { DownloadWords.wait($0, device: Platform.device) } ?? AutoDownloadWords.downloadingRow(progress)
        Button {
            navigation.open(.downloaded)
        } label: {
            // (R9) iArtists' tall row, the download's mark in the cover's place
            HStack(alignment: .center, spacing: 0) {
                Image(systemName: DownloadWords.downloadSymbol)
                    .font(Typeface.symbol(.title3))
                    .foregroundStyle(DWPalette.acc)
                    .frame(width: LibraryLook.rowCover, height: LibraryLook.rowCover)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AutoDownloadWords.downloadingTitle(scope))
                        .font(Typeface.body)
                        .foregroundStyle(DWPalette.text)
                    Text(line)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                        .fixedSize(horizontal: false, vertical: true)
                    DownloadBar(fraction: progress.fraction)
                        .padding(.top, 4)
                }
                .padding(.horizontal, LibraryLook.rowTextSide)
                .frame(maxWidth: .infinity, alignment: .leading)
                LibraryChevron()
            }
            .tallRow(macRoom: 4)
            .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(downloads.libraryWait.map { "\(AutoDownloadWords.downloadingTitle(scope)), \(DownloadWords.wait($0, device: Platform.device))" }
                            ?? AutoDownloadWords.downloadingSpoken(scope, progress))
        .accessibilityAddTraits([.isButton, .updatesFrequently])
    }
}

// MARK: Download over (6.4)

/// Drawn as Normalization is (PlaybackSection): (16 Nov) one row, "Download over" and the choice at its right, a menu of
/// the two (`.pickerStyle(.menu)`, as the Storage limit above it is) - a list of ticks until then. Each choice had its
/// line under its name: the chosen one's leads the footer now, and VoiceOver hears it as the row's hint. Then what's used
/// now, amber while something waits for it, and that both are kept on this phone.
private struct DownloadOverSection: View {
    let waitingForIt: Bool

    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let chosen = DownloadWords.over(downloads.downloadOver, device: Platform.device)
        Section {
            SettingsChoiceRow(title: DownloadWords.downloadOver) {
                Picker(DownloadWords.downloadOver, selection: Binding<DownloadOver>(get: { downloads.downloadOver },
                                                                                  set: { (choice: DownloadOver) -> Void in
                                                                                      downloads.downloadOver = choice
                                                                                  })) {
                    ForEach(DownloadOver.allCases, id: \.self) { (choice: DownloadOver) in
                        Text(DownloadWords.over(choice, device: Platform.device).name).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityHint(chosen.note)
            }
            .padding(.top, CGFloat(PhoneLook.groupAbove))
            // (R9) the group's note, flat: its own row under the choice, as Settings' other pages draw theirs
            VStack(alignment: .leading, spacing: 8) {
                // the chosen one's own line first: what it does
                Text(chosen.note)
                Text(DownloadWords.overNow(reachability.path, setting: downloads.downloadOver, device: Platform.device))
                    .foregroundStyle(waitingForIt ? DWPalette.amberText : DWPalette.t2)
                Text(DownloadWords.overKept(Platform.device))
            }
            .font(Typeface.Phone.text(.small))
            .foregroundStyle(DWPalette.t2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, SettingsLook.noteAbove)
        }
        .flatRows()
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
            ListLegend(words: DownloadWords.downloadingHeader)
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
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                    if let fraction = row.fraction {
                        DownloadBar(fraction: fraction)
                            .padding(.top, 4)
                    }
                }
                .removable(name: row.album?.name) { downloads.remove(album: row.id) }
            }
            let lines = [allWaitForWifi ? DownloadWords.allWaitForWifi(Platform.device) : nil,
                         downloads.forceQuitShown ? DownloadWords.forceQuit(Platform.device) : nil].compactMap { $0 }
            if !lines.isEmpty {
                ListNote(words: lines.joined(separator: "\n\n"))
            }
        }
        .flatRows()
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Section {
            ListLegend(words: DownloadWords.didntDownloadHeader)
            ForEach(rows) { row in
                FailedRow(row: row)
            }
            if rows.count > 1 {
                // (R9's review) across the row at the accessibility sizes, so its words can wrap
                Button {
                    downloads.tryAllAgain()
                } label: {
                    ButtonWords(words: DownloadWords.tryAllAgain)
                }
                .buttonStyle(DWButtonStyle(fills: typeSize.isAccessibilitySize))
            }
        }
        .flatRows()
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
                    DownloadMark(mark: .failed, font: Typeface.symbol(.caption))
                    Text(DownloadWords.didntDownload(row.records.count))
                        .font(Typeface.Phone.text(.small).weight(.medium))
                        .foregroundStyle(DWPalette.amberText)
                }
                Text(row.reason.said)
                    .font(Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            } trailing: {
                Button(DownloadWords.tryAgain) { tryAgain() }
                    .buttonStyle(DWButtonStyle(size: .small))
            }
            // the raw words for whoever runs deadwax - ErrorNote's split, its own element
            if server.access.seesDetail, let detail = row.reason.detail, !detail.isEmpty {
                DisclosureGroup(ErrorWords.forWhoever) {
                    Text(detail)
                        .font(Typeface.mono(.footnote))
                        .foregroundStyle(DWPalette.t2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Typeface.Phone.text(.small))
                .tint(DWPalette.acc)
                .padding(.leading, AlbumLineInset.text)
            }
        }
        .removable(name: row.album?.name, asks: asks, ask: ask, offered: removes) { remove() }
        // keeping a library album off lets go of its songs already here too: said, with Cancel
        .confirmationDialog(AutoDownloadWords.keepOffTitle(name, device: Platform.device), isPresented: $askingKeepOff,
                            titleVisibility: .visible) {
            Button(DownloadWords.removeDownload, role: .destructive) {
                remove()
                player.say(DownloadWords.removed(name, device: Platform.device))
            }
            Platform.dialogCancel()
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
            ListLegend(words: DownloadWords.downloadedHeader)
            ForEach(playlists) { row in
                PlaylistLineRow(row: row)
                    .removable(name: row.name) { downloads.remove(playlist: row.id) }
            }
            ForEach(rows) { row in
                let large = typeSize.isAccessibilitySize
                AlbumLine(album: row.album, albumID: row.id, spoken: spoken(row)) {
                    Text(row.line)
                        .font(Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                    if large { verdict(row.verdict).padding(.top, 2) }
                } trailing: {
                    if !large { verdict(row.verdict) }
                }
                .removable(name: row.album?.name) { downloads.remove(album: row.id) }
            }
            ListNote(words: DownloadWords.downloadedFooter)
        }
        .flatRows()
    }

    /// The album's check: "Checked" with its mark in the library's green; "Checked by size" and "Checking…" quiet.
    @ViewBuilder
    private func verdict(_ verdict: DownloadRules.Verdict) -> some View {
        let words = DownloadWords.verdict(verdict)
        if verdict == .checked {
            Label(words, systemImage: DownloadWords.Mark.checked.rawValue)
                .labelStyle(VerdictLabel())
                .foregroundStyle(DWPalette.greenText)
        } else {
            Text(words)
                .font(Typeface.Phone.text(.small))
                .foregroundStyle(DWPalette.t2)
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
            configuration.icon.font(Typeface.symbol(.caption))
            configuration.title.font(Typeface.Phone.text(.small))
        }
    }
}

// MARK: one album's row

/// Where an album row's words start: the cover (iArtists' 44) and its words' room - a detail under the row lines up with
/// them.
private enum AlbumLineInset {
    static let text: CGFloat = LibraryLook.rowCover + LibraryLook.rowTextSide
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
        // (R9) iArtists' tall row: the cover at 44, the album, the artist and the section's lines under it in the second
        // colour, what trails, and the row's hairline
        HStack(alignment: .center, spacing: CGFloat(PhoneLook.goGap)) {
            Button {
                navigation.open(.album(album.map { AlbumRoute($0) } ?? AlbumRoute(id: albumID)))
            } label: {
                HStack(alignment: .center, spacing: 0) {
                    CoverImage(id: album?.coverArt, size: LibraryLook.rowCover)
                        .frame(width: LibraryLook.rowCover, height: LibraryLook.rowCover)
                        .clipShape(Corners.artShape)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(album?.name ?? "")
                            .font(Typeface.body)
                            .foregroundStyle(DWPalette.text)
                            .lineLimit(large ? nil : 1)
                        if let artist = album?.artist, !artist.isEmpty {
                            Text(artist)
                                .font(Typeface.Phone.text(.small))
                                .foregroundStyle(DWPalette.t2)
                                .lineLimit(large ? nil : 1)
                        }
                        lines()
                    }
                    .padding(.horizontal, LibraryLook.rowTextSide)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
                .tallRow()
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
        .overlay(alignment: .bottom) { DWRule(colour: DWPalette.rowRule) }
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

    /// (R9's review) iArtists' tall row's height: on the phone 60 at least (lookHeight's minHeight); on the Mac its
    /// content's own, `macRoom` above and below - lookHeight is exact there and the Mac's tallRowHeight its table's 30,
    /// which cut the 44-point cover and the three lines beside it.
    @ViewBuilder func tallRow(macRoom: CGFloat = 0) -> some View {
        if Platform.mac {
            padding(.vertical, macRoom)
        } else {
            lookHeight(DWLook.here.tallRowHeight)
        }
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
                    .tint(Palette.danger) // the destructive swipe's own red
            } else {
                Button(DownloadWords.remove, systemImage: "trash", role: .destructive) {
                    remove()
                    player.say(DownloadWords.removed(name ?? PlayerWords.untitled, device: Platform.device))
                }
            }
        }
    }
}

// MARK: (R9) flat, in a plain list

/// A group's legend, as PhoneGroup draws it (`.dw.ph .group > .legend`), as a row of the list's own: the legend's 13,
/// semibold, the second colour, the group's room above it - a plain list's section header would stand pinned on a bar.
private struct ListLegend: View {
    let words: String

    var body: some View {
        Text(words)
            .font(Typeface.Phone.text(.legend).weight(.semibold))
            .foregroundStyle(DWPalette.t2)
            .lookHeight(PhoneLook.legendLine)
            .padding(.leading, CGFloat(PhoneLook.legendSide))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, CGFloat(PhoneLook.groupAbove - PhoneLook.legendLift))
            .padding(.bottom, CGFloat(PhoneLook.legendLift - PhoneLook.legendLine))
            .accessibilityAddTraits(.isHeader)
    }
}

/// A group's note under its rows (iOS Settings' footer, flat), as a row of the list's own - Settings' SettingsNote.
private struct ListNote: View {
    let words: String
    var colour: Color = DWPalette.t2

    var body: some View {
        SettingsNote(words: words, colour: colour)
    }
}

private extension View {
    /// A section's rows drawn flat (R9): no list hairlines (each row draws its own), the page's sides, no cell behind.
    func flatRows() -> some View {
        listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: LibraryLook.side, bottom: 0, trailing: LibraryLook.side))
            .listRowBackground(Color.clear)
    }
}
