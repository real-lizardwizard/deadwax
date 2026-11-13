import DeadwaxAudio
import DeadwaxCore
import SwiftUI
import UIKit

/// You's Debug (admins only, D1): Phase 0's one screen, moved - Check's report, the test sounds (with the record's
/// engine beside the song, turntable.md 7.2), the hi-res row,
/// what is playing (with the engine's own words for its last failure, D7, and an Up Next edit held for the join, D4),
/// the EQ (eq.md 3.13: the route's outputs, its key, the unit, the curve, what the last start put in and how long it
/// took, the kept file) and "Muffle what plays" (slice 2), the engine's log (its last 500 lines, with Copy and
/// Share), the Library's last album list asks (how many albums, how long - check 1), and how long this install runs. Phase 2's Downloads section: the songs by state, the session's
/// tasks, reachability, what waits to be sent, the time each check took, the download log and "Stream even when
/// downloaded" (phase2-downloads.md 6.9). Phase 3's Your library (phase3-autodownload.md 3.5): Follow your library, what
/// is followed, the albums and their songs read, the last check, the first read's time and what would fit. The address
/// and the sign-in are the app's own screens now.
struct DebugView: View {
    @Environment(DebugModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(LibraryModel.self) private var library
    @Environment(DownloadModel.self) private var downloads
    @Environment(EQModel.self) private var eq
    @State private var deckTrial = DeckTrialModel()

    init() {}

    var body: some View {
        Form {
            server
            if model.report?.ok == true {
                testSounds
                hiRes
            }
            playing
            TurntableDebugSection()
            EQDebugSection()
            EngineLogSection()
            DownloadsDebugSection()
            LibraryFollowDebugSection()
            libraryLists
            Section {
                Text(model.installLine)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
            } footer: {
                Text("deadwax for iPhone \(YouView.appVersion)")
            }
        }
        .navigationTitle("Debug")
        .task { if model.report == nil { await model.check() } }
        // Muffle is a test (eq.md 5.2): it goes off as Debug closes - back out of it, or another tab - so it can't be
        // left on under real listening. Locking the phone doesn't close it (check E0d needs Muffle on, locked). The record's
        // engine beside the song (turntable.md 7.2) stops the same way.
        .onDisappear {
            eq.muffle = false
            deckTrial.stop()
        }
    }

    // MARK: the Library's lists

    /// Each scope's last album_index answer: a new list (200) or the one kept still standing (304), how many albums
    /// and how long it took - to count against the web's Library, and to time a big library.
    private var libraryLists: some View {
        Section {
            ForEach([AlbumScope.yours, .store], id: \.self) { scope in
                if let fetch = library.lastFetch[scope] {
                    LabeledContent(scope == .yours ? "Your albums" : "All albums") {
                        Text("\(fetch.albums) albums \u{00B7} \(fetch.status) \u{00B7} \(String(format: "%.2f", fetch.seconds)) s")
                            .font(.footnote.monospacedDigit())
                    }
                }
            }
            if library.lastFetch.isEmpty {
                Text("Not asked yet").foregroundStyle(Palette.quiet)
            }
        } header: {
            Text("Library")
        }
    }

    // MARK: the server

    private var server: some View {
        Section {
            Button(model.checking ? "Checking\u{2026}" : "Check") {
                Task { await model.check() }
            }
            .disabled(model.checking)
            ForEach(model.report?.lines ?? [], id: \.self) { line in
                Text(line).font(.footnote)
            }
        } header: {
            Text("deadwax")
        }
    }

    // MARK: the test sounds

    private var testSounds: some View {
        Section {
            ForEach(Array(model.testSongs.enumerated()), id: \.element.id) { index, song in
                songRow(song, playing: player.current?.track.id == song.id) {
                    model.play(model.testSongs, at: index)
                }
            }
            if !model.testSongs.isEmpty {
                let missing = model.testSongs.filter { !model.downloaded.contains($0.id) }
                Button(missing.isEmpty ? "All downloaded" : "Download all \(model.testSongs.count)") {
                    model.download(model.testSongs)
                }
                .disabled(missing.isEmpty || !model.downloading.isEmpty)
                if !model.downloaded.isEmpty {
                    Button("Remove the downloads", role: .destructive) { model.removeDownloads() }
                }
            }
            if let words = model.testWords { Text(words).font(.footnote) }
            DeckTrialRows(model: deckTrial)
        } header: {
            Text("Test sounds")
        } footer: {
            Text("Songs 1 to 8 are three beeps each: tap one to play the album from it and count the beeps - all three, every time? Songs 9 and 10 are one tone cut in two: played one into the other, the tone should never break. A song downloaded to this phone plays from there, as every song does; \"Stream even when downloaded\" (under Downloads) streams it instead, to hear the two side by side. \(TurntableDebugRows.trialFooter)")
        }
    }

    private func songRow(_ song: Song, playing: Bool, play: @escaping () -> Void) -> some View {
        HStack {
            Button(action: play) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.name).foregroundStyle(playing ? Palette.accent : .primary)
                        Text(detail(song)).font(.caption).foregroundStyle(Palette.quiet)
                    }
                    Spacer()
                    if playing { Image(systemName: "speaker.wave.2.fill").foregroundStyle(Palette.accent) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            if model.downloading.contains(song.id) {
                ProgressView()
            } else {
                Button {
                    model.download([song])
                } label: {
                    Image(systemName: model.downloaded.contains(song.id) ? "checkmark.circle.fill" : "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .disabled(model.downloaded.contains(song.id))
                .accessibilityLabel(model.downloaded.contains(song.id) ? "Downloaded" : "Download")
            }
        }
    }

    private func detail(_ song: Song) -> String {
        var parts: [String] = []
        if let rate = song.samplingRate {
            parts.append([song.bitDepth.map { "\($0)-bit" }, RateWords.kHz(Double(rate))].compactMap { $0 }.joined(separator: " "))
        }
        if let suffix = song.suffix { parts.append(suffix.uppercased()) }
        if let duration = song.duration { parts.append(clock(duration)) }
        parts.append(model.downloaded.contains(song.id) ? "on the phone" : "not downloaded")
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: the hi-res row

    private var hiRes: some View {
        Section {
            Button(model.findingHiRes ? "Looking\u{2026}" : (model.hiRes == nil ? "Find a 24/192 FLAC" : "Look again")) {
                Task { await model.findHiRes() }
            }
            .disabled(model.findingHiRes)
            if let song = model.hiRes {
                songRow(song, playing: player.current?.track.id == song.id) {
                    model.play([song], at: 0)
                }
            }
            if let words = model.hiResWords { Text(words).font(.footnote) }
        } header: {
            Text("Hi-res")
        } footer: {
            Text("Decodes the song at its own rate. What's playing below says the file's rate and the output's: when they differ, the app's audio engine converts to the output's rate, as any app must.")
        }
    }

    // MARK: playing

    private var playing: some View {
        Section {
            if let track = player.current?.track {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title.isEmpty ? track.id : track.title).font(.headline)
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " \u{2014} "))
                        .font(.subheadline).foregroundStyle(Palette.quiet)
                    Text("\(player.phaseWords) \u{00B7} \(clock(player.shownPosition))\(player.duration > 0 ? " of \(clock(player.duration))" : "")")
                        .font(.footnote.monospacedDigit())
                    if let readout = player.readout {
                        Text(readout).font(.footnote)
                    }
                }
                HStack {
                    Spacer()
                    Button { player.previous() } label: { Image(systemName: "backward.fill") }
                        .accessibilityLabel("Previous")
                    Spacer()
                    Button { player.toggle() } label: {
                        Image(systemName: player.engineState.phase == .playing ? "pause.fill" : "play.fill")
                            .font(.title)
                    }
                    .accessibilityLabel(player.engineState.phase == .playing ? "Pause" : "Play")
                    Spacer()
                    Button { player.next() } label: { Image(systemName: "forward.fill") }
                        .accessibilityLabel("Next")
                        .disabled(nextIndex(player.queue) == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 4)
            } else {
                Text("Nothing playing").foregroundStyle(Palette.quiet)
            }
            if player.holdsAnEdit {
                LabeledContent("Up Next", value: "An edit held for the next song")
            }
            if let words = player.lastFailure {
                LabeledContent("Last failure") {
                    Text(words).font(.footnote).foregroundStyle(.red)
                }
            }
        } header: {
            Text("Playing")
        }
    }

    private func clock(_ seconds: Double) -> String { Format.clock(seconds) }
}

/// Debug's EQ (eq.md 3.13): the route's outputs (port type, name, UID raw) and the key they make, the unit's rows -
/// in the graph and what it does, the rate's sections, the changes, what the last start put in, samples over full
/// scale, its render time - with the curve and its sections at this rate among them, how long the last start took to
/// put its curve in, and what eq.json holds; read once a second while they show and the app is in front. Then
/// "Muffle what plays", the test curve through the real unit (check 0), now EQModel's - the same door every change
/// goes through.
private struct EQDebugSection: View {
    @Environment(EQModel.self) private var eq
    @Environment(\.scenePhase) private var phase
    @State private var rows: [(label: String, value: String)] = []

    var body: some View {
        Section {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                LabeledContent(row.label) {
                    Text(row.value).font(.footnote)
                }
            }
            Toggle(EQWords.Debug.muffle, isOn: Binding<Bool>(get: { eq.muffle }, set: { (on: Bool) -> Void in
                eq.muffle = on
            }))
        } header: {
            Text(EQWords.Debug.header)
        } footer: {
            Text(EQWords.Debug.muffleFooter)
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                rows = eq.debugRows(eq.status())
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Debug's Turntable (turntable.md 6.2): the web's rows where the phone has the same fact, and the phone's own - read
/// four times a second while they show and the app is in front. "Off: the turntable isn't showing" until the turntable
/// has shown once; after that, what it last did, while its deck lives.
private struct TurntableDebugSection: View {
    @Environment(DeckController.self) private var deck
    @Environment(\.scenePhase) private var phase
    @State private var rows: [InfoRow] = []
    @State private var recording: DeckRecordingStatus = .idle

    var body: some View {
        Section {
            ForEach(Array(rows.enumerated()), id: \.offset) { (_: Int, row: InfoRow) in
                LabeledContent(row.label) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(row.value).font(row.mono ? .footnote.monospaced() : .footnote)
                        if let note = row.note {
                            Text(note).font(.caption).foregroundStyle(Palette.quiet)
                        }
                    }
                }
            }
            TurntableRecordingRow(status: recording, shown: deck.hasDeck, url: deck.recordingURL) {
                deck.record()
                recording = deck.recordingStatus
            }
        } header: {
            Text("Turntable")
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                rows = deck.debugRows()
                recording = deck.recordingStatus
                try? await Task.sleep(for: .seconds(0.25))
            }
        }
    }
}

/// Debug's Recording row (turntable.md 6.2, 6.3): "Record 20 s", how it is going, then the file through the share
/// sheet - what James sends back when the record's sound is wrong on the phone.
private struct TurntableRecordingRow: View {
    let status: DeckRecordingStatus
    let shown: Bool
    let url: URL?
    let record: () -> Void

    var body: some View {
        let said = TurntableDebugRows.recordingRow(status, turntable: shown)
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(said.row.label) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(said.row.value).font(.footnote)
                    if let note = said.row.note {
                        Text(note).font(.caption).foregroundStyle(Palette.quiet)
                    }
                }
            }
            if let action = said.action {
                if case .saved = status, let url {
                    ShareLink(item: url) { Text(action) }
                } else {
                    Button(action, action: record)
                }
            }
            if let again = TurntableDebugRows.recordAgain(status, turntable: shown) {
                Button(again, action: record)
            }
        }
    }
}

/// Test sounds' "The record's engine beside the song" (notes/ios-specs/turntable.md 7.2, checks 0a-0c): the deck engine
/// playing DeckTrial's fixed run through its real render beside whatever the song's engine plays. Made at the first
/// Start; DebugView stops it as Debug closes (as it turns Muffle off), so it can't be left playing.
@MainActor
@Observable
final class DeckTrialModel {
    private(set) var running = false
    private(set) var rows: [InfoRow] = []
    @ObservationIgnored private var trial: DeckTrial?
    @ObservationIgnored private var failure: String?

    func toggle() {
        let made = trial ?? { () -> DeckTrial in
            let made = DeckTrial(ioBuffer: { AudioSessionController.ioBuffer() },
                                 latency: { AudioSessionController.latency() })
            // the app's session made active at every start, as a play's is (slice 2's review, question 6): with nothing
            // played yet it isn't, and the engine would start on an inactive session
            made.engine.activate = { try AudioSessionController.activateShared() }
            return made
        }()
        trial = made
        if made.isRunning {
            made.stop()
            running = false
        } else {
            do {
                try made.start()
                failure = nil
                running = true
            } catch {
                failure = error.localizedDescription
                running = false
            }
        }
        read()
    }

    func stop() {
        guard let trial, trial.isRunning else { return }
        trial.stop()
        running = false
        read()
    }

    /// The engine's row, its Clock (6.2) and Messages dropped when there were any.
    func read() {
        guard let trial else { return }
        let status = trial.status()
        var made = [TurntableDebugRows.trialRow(rate: status.rate, blocks: status.blocks, starts: status.starts,
                                                lastStart: status.lastStartSeconds, failure: failure ?? status.failure),
                    status.clockRow]
        if let dropped = TurntableDebugRows.messagesDroppedRow(status.dropped) { made.append(dropped) }
        rows = made
    }
}

/// Its rows: Start and Stop, then what DeckTrialModel reads - four times a second while the button's row is on screen
/// and the app is in front.
private struct DeckTrialRows: View {
    let model: DeckTrialModel
    @Environment(\.scenePhase) private var phase

    var body: some View {
        LabeledContent(TurntableDebugRows.trialLabel) {
            Button(TurntableDebugRows.trialButton(running: model.running)) { model.toggle() }
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                model.read()
                try? await Task.sleep(for: .seconds(0.25))
            }
        }
        ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
            LabeledContent(row.label) {
                Text(row.value).font(.footnote.monospacedDigit())
            }
        }
    }
}

/// The engine's log (EngineTrace): its last lines, the newest last, read again once a second while the log's row is
/// on screen and the app is in front - and only then (not on a locked phone left on Debug with music playing) - and
/// drawn lazily, a line at a time. Copy puts the whole log on the clipboard as it is at the tap; Share hands it on as
/// text (Mail, Messages, Files...) as last read.
private struct EngineLogSection: View {
    @State private var shown = EngineLog.Snapshot.empty
    @State private var copied = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Section {
            HStack(spacing: 24) {
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = EngineTrace.log.snapshot().text
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                ShareLink(item: shown.text, preview: SharePreview("deadwax engine log")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.borderless)
            .disabled(shown.lines.isEmpty)
            Group {
                if shown.lines.isEmpty {
                    Text("Nothing yet: the engine writes here once something plays.")
                        .foregroundStyle(Palette.quiet)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            // by each line's number, which stays its own as the window moves on
                            ForEach(shown.first..<shown.total, id: \.self) { number in
                                Text(shown.lines[number - shown.first])
                            }
                        }
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: 320)
                }
            }
            .task(id: phase) {
                // while the log's row is on screen and the app in front (a locked phone is .background, no
                // onDisappear): the log read again when it has moved
                guard phase == .active else { return }
                while !Task.isCancelled {
                    if EngineTrace.log.total != shown.total { shown = EngineTrace.log.snapshot() }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        } header: {
            Text("Engine log")
        } footer: {
            Text("The engine's last \(EngineTrace.log.capacity) lines, the newest last (\(shown.total) so far); once there are \(EngineTrace.log.capacity), the oldest go as new ones come, so the lines move up while you read - Copy keeps them as they are. Each line starts with a time in seconds on the phone's clock: the gaps between lines are what count. Console on a Mac shows them too, as they happen: choose the iPhone, turn on Action > Include Info Messages, press Start, then search for subsystem:net.lizardlounge.deadwax.")
        }
    }
}

/// Debug's Downloads (phase2-downloads.md 6.9): the songs by state and their bytes; the background session's tasks
/// (running, waiting, with resume data), asked again every second while it shows; reachability, the path's facts and
/// the last probe; the plays waiting to be sent; the time each check took (the plan's R9); the last 50 download events;
/// and "Stream even when downloaded" - Phase 0's Streamed/Downloaded switch, kept as the admin's A/B.
private struct DownloadsDebugSection: View {
    @Environment(DownloadModel.self) private var downloads
    @Environment(Reachability.self) private var reachability
    @State private var tasks: [DownloadSession.Out] = []
    @State private var tasksRead = false

    var body: some View {
        Section {
            Toggle("Stream even when downloaded", isOn: Binding(get: { downloads.streamEvenWhenDownloaded },
                                                                set: { downloads.streamEvenWhenDownloaded = $0 }))
            ForEach(StoredState.allCases, id: \.self) { state in
                let rows = downloads.records.values.filter { $0.state == state }
                let bytes = rows.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
                LabeledContent(state.rawValue) {
                    Text("\(rows.count) \u{00B7} \(Bytes.words(bytes))")
                        .font(.footnote.monospacedDigit())
                }
            }
            LabeledContent("Tasks") {
                let running = tasks.filter(\.running).count
                let resumable = downloads.records.values.filter { $0.resume != nil }.count
                Text(tasksRead ? "\(running) running \u{00B7} \(tasks.count - running) waiting \u{00B7} \(resumable) with resume data"
                               : "Reading\u{2026}")
                    .font(.footnote.monospacedDigit())
            }
            LabeledContent("Reach") {
                Text(reachability.reach.rawValue + (reachability.probing ? " \u{00B7} probing" : ""))
                    .font(.footnote.monospaced())
            }
            LabeledContent("Path") {
                Text(pathFacts(reachability.path))
                    .font(.footnote.monospaced())
            }
            LabeledContent("Last probe") {
                Text(reachability.lastProbe.map { "\($0.answered ? "answered" : "no answer") \u{00B7} \($0.at.formatted(date: .omitted, time: .standard))" } ?? "none yet")
                    .font(.footnote.monospaced())
            }
            LabeledContent("Plays waiting to be sent") {
                Text("\(downloads.playsWaiting)")
                    .font(.footnote.monospacedDigit())
            }
            LabeledContent("Starts waiting to be sent") {
                Text("\(downloads.startsWaiting)")
                    .font(.footnote.monospacedDigit())
            }
            if !downloads.checkSeconds.isEmpty {
                let times = Array(downloads.checkSeconds.values)
                LabeledContent("Checks") {
                    Text("\(times.count) \u{00B7} mean \(String(format: "%.2f", times.reduce(0, +) / Double(times.count))) s \u{00B7} longest \(String(format: "%.2f", times.max() ?? 0)) s")
                        .font(.footnote.monospacedDigit())
                }
            }
            if let problem = downloads.storeProblem {
                Text(problem)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Palette.danger)
                    .textSelection(.enabled)
            }
            if downloads.log.isEmpty {
                Text("No download events yet.")
                    .foregroundStyle(Palette.quiet)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(downloads.log.suffix(50).enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                }
                .font(.caption2.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("Downloads")
        }
        .task {
            while !Task.isCancelled {
                tasks = await downloads.debugTasks()
                tasksRead = true
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func pathFacts(_ path: NetworkPath) -> String {
        guard path.satisfied else { return "none" }
        return [path.wifi ? "wifi" : nil, path.cellular ? "cellular" : nil, path.expensive ? "expensive" : nil,
                path.constrained ? "constrained" : nil].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }
}

/// Phase 3's Your library (phase3-autodownload.md 3.5): what Download your library follows - its switch is You >
/// Downloads' (slice 2) - and how much of it is read; the last check; the first read's time (R13, check L0a); what fits
/// at the storage limit, as the last plan worked it out. The library's log lines are the Downloads section's.
private struct LibraryFollowDebugSection: View {
    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        let follower = downloads.follower
        Section {
            if follower.on {
                facts(follower)
            } else {
                Text(LibraryFollowWords.notFollowing)
                    .foregroundStyle(Palette.quiet)
            }
        } header: {
            Text(LibraryFollowWords.section)
        } footer: {
            Text(LibraryFollowWords.followNote)
        }
    }

    @ViewBuilder
    private func facts(_ follower: LibraryFollower) -> some View {
        let now = ListenTracker.wallMs()
        let albums = follower.ordered
        let listed = albums.filter(\.isListed).count
        let read = albums.filter { $0.isListed && $0.songs != nil }.count
        if let scope = follower.scope {
            LabeledContent("Following") {
                Text(LibraryFollowWords.scope(scope))
                    .font(.footnote)
            }
        }
        LabeledContent("Albums") {
            Text(LibraryFollowWords.count(albums.count))
                .font(.footnote.monospacedDigit())
        }
        LabeledContent("Songs read") {
            Text(LibraryFollowWords.read(read, of: listed)
                 + (follower.readingNow > 0 ? " \u{00B7} reading \(follower.readingNow)" : ""))
                .font(.footnote.monospacedDigit())
        }
        LabeledContent("Missing") {
            Text(LibraryFollowWords.missing(albums, now: now))
                .font(.footnote.monospacedDigit())
        }
        LabeledContent("Held back") {
            Text(LibraryFollowWords.held(follower.held)
                 + (follower.believing ? " \u{00B7} believing (Remove)" : "")
                 + (follower.keptThem ? " \u{00B7} kept them" : ""))
                .font(.footnote)
        }
        LabeledContent("Removed, to let go") {
            Text(LibraryFollowWords.count(follower.removed.count))
                .font(.footnote.monospacedDigit())
        }
        LabeledContent("Last check") {
            Text(follower.checking ? "Checking\u{2026}"
                 : follower.lastCheck.map { LibraryFollowWords.lastCheck($0, now: now) } ?? LibraryFollowWords.noCheckYet)
                .font(.footnote.monospacedDigit())
        }
        if let first = follower.firstRead {
            LabeledContent("First read") {
                Text(LibraryFollowWords.firstRead(seconds: first.seconds, albums: first.albums))
                    .font(.footnote.monospacedDigit())
            }
        }
        if let plan = downloads.libraryFill {
            VStack(alignment: .leading, spacing: 2) {
                Text(LibraryFollowWords.wouldFit(plan, limit: downloads.storageLimit))
                Text(LibraryFollowWords.fitDetail(plan))
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
            }
            .accessibilityElement(children: .combine)
        }
        if let problem = follower.problem {
            Text(problem)
                .font(.footnote.monospaced())
                .foregroundStyle(Palette.danger)
                .textSelection(.enabled)
        }
        Button(LibraryFollowWords.checkNow) { follower.check(.byHand) }
            .disabled(follower.checking)
    }
}
