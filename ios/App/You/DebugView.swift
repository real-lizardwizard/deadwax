import DeadwaxAudio
import DeadwaxCore
import SwiftUI
import UIKit

/// You's Debug (admins only, D1): Phase 0's one screen, moved - Check's report, the test sounds (with the record's
/// engine beside the song, turntable.md 7.2), the hi-res row,
/// what is playing (with the engine's own words for its last failure, D7, and an Up Next edit held for the join, D4),
/// the EQ (eq.md 3.13: the route's outputs, its key, the unit, the curve, what the last start put in and how long it
/// took, the kept file) and "Muffle what plays" (slice 2), the engine's log (its last 500 lines, with Copy and
/// Share), the Library's last album list asks (how many albums, how long - check 1) and its top's last reading (18 Nov,
/// LibraryTop), and how long this install runs. Phase 2's Downloads section: the songs by state, the session's
/// tasks, reachability, what waits to be sent, the time each check took, the download log and "Stream even when
/// downloaded" (phase2-downloads.md 6.9). Phase 3's Your library (phase3-autodownload.md 3.5): Follow your library, what
/// is followed, the albums and their songs read, the last check, the first read's time and what would fit. The address
/// and the sign-in are the app's own screens now. Its measurements are in the readout face (Courier Prime, 25 Nov):
/// `.monospacedDigit()` held them still in Noto Sans, and does nothing in Libre Franklin.
///
/// (R20 - notes/ios.md "The panel review, R20: the known holdouts (2026-11-26)") No Form: drawn from the canvas's pieces,
/// as no drawing has it. On the phone flat, as R9's Settings pages are (iSettings) - each section a group's heading
/// over its rows on their hairlines, on the page's black, its footer a note under it; on the Mac each a group box
/// (Settings.dc.html's `.group.onbg`), its facts as the Mac's Settings draws a fact - the label right-aligned at 124 in
/// the second colour, the value beside it. Every line it showed is still there, in the same order; every fact's value
/// sits on its label's first baseline (HoldoutFact), the readouts in Courier Prime, the words in Libre Franklin.
struct DebugView: View {
    @Environment(DebugModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(LibraryModel.self) private var library
    @Environment(DownloadModel.self) private var downloads
    @Environment(EQModel.self) private var eq
    @State private var deckTrial = DeckTrialModel()

    init() {}

    var body: some View {
        HoldoutPage {
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
            HoldoutGroup(note: DebugWords.footer(version: YouView.appVersion, device: Platform.device)) {
                HoldoutLine(model.installLine)
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
        HoldoutGroup(legend: "Library") {
            ForEach([AlbumScope.yours, .store], id: \.self) { scope in
                if let fetch = library.lastFetch[scope] {
                    HoldoutFact(scope == .yours ? "Your albums" : "All albums",
                                "\(fetch.albums) albums \u{00B7} \(fetch.status) \u{00B7} \(String(format: "%.2f", fetch.seconds)) s")
                }
            }
            if library.lastFetch.isEmpty {
                HoldoutLine("Not asked yet")
            }
            // (18 Nov) the Library's top's last reading - the row in its window, the window's inset, the room it came
            // down, whether something was presented: what to send if the row still stands in the Dynamic Island
            HoldoutFact("Top", model.libraryTop?.line ?? "Not measured yet")
        }
    }

    // MARK: the server

    private var server: some View {
        HoldoutGroup(legend: "deadwax") {
            HoldoutButtons {
                Button {
                    Task { await model.check() }
                } label: {
                    HoldoutWords(model.checking ? "Checking\u{2026}" : "Check")
                }
                .disabled(model.checking)
            }
            ForEach(model.report?.lines(Platform.device) ?? [], id: \.self) { line in
                HoldoutLine(line, tone: DWPalette.text)
            }
        }
    }

    // MARK: the test sounds

    private var testSounds: some View {
        HoldoutGroup(legend: "Test sounds",
                     note: DebugWords.testSoundsFooter(trial: TurntableDebugRows.trialFooter, device: Platform.device)) {
            ForEach(Array(model.testSongs.enumerated()), id: \.element.id) { index, song in
                songRow(song, playing: player.current?.track.id == song.id) {
                    model.play(model.testSongs, at: index)
                }
            }
            if !model.testSongs.isEmpty {
                let missing = model.testSongs.filter { !model.downloaded.contains($0.id) }
                HoldoutButtons {
                    Button {
                        model.download(model.testSongs)
                    } label: {
                        HoldoutWords(missing.isEmpty ? "All downloaded" : "Download all \(model.testSongs.count)")
                    }
                    .disabled(missing.isEmpty || !model.downloading.isEmpty)
                    if !model.downloaded.isEmpty {
                        Button(role: .destructive) {
                            model.removeDownloads()
                        } label: {
                            HoldoutWords("Remove the downloads")
                        }
                        .buttonStyle(DWButtonStyle(kind: .danger, size: .small))
                    }
                }
            }
            if let words = model.testWords { HoldoutLine(words) }
            DeckTrialRows(model: deckTrial)
        }
    }

    /// A song's row: its name (in the accent while it plays) over its facts, a tap playing it from there - and its
    /// download's glyph, a flat button on the phone and a small one on the Mac, or the spinner while it comes.
    private func songRow(_ song: Song, playing: Bool, play: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Button(action: play) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.name)
                            .font(HoldoutLook.words)
                            .foregroundStyle(playing ? DWPalette.acc : DWPalette.text)
                        Text(detail(song))
                            .font(HoldoutLook.extraSmall)
                            .foregroundStyle(DWPalette.t2)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if playing {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(DWPalette.acc)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if model.downloading.contains(song.id) {
                ProgressView()
            } else {
                Button {
                    model.download([song])
                } label: {
                    Image(systemName: model.downloaded.contains(song.id) ? "checkmark.circle.fill" : "arrow.down.circle")
                }
                .buttonStyle(DWButtonStyle(size: .small))
                .disabled(model.downloaded.contains(song.id))
                .accessibilityLabel(model.downloaded.contains(song.id) ? "Downloaded" : "Download")
            }
        }
        .holdoutRow()
    }

    private func detail(_ song: Song) -> String {
        var parts: [String] = []
        if let rate = song.samplingRate {
            parts.append([song.bitDepth.map { "\($0)-bit" }, RateWords.kHz(Double(rate))].compactMap { $0 }.joined(separator: " "))
        }
        if let suffix = song.suffix { parts.append(suffix.uppercased()) }
        if let duration = song.duration { parts.append(clock(duration)) }
        parts.append(model.downloaded.contains(song.id) ? DebugWords.onThe(Platform.device) : "not downloaded")
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: the hi-res row

    private var hiRes: some View {
        HoldoutGroup(legend: "Hi-res",
                     note: "Decodes the song at its own rate. What's playing below says the file's rate and the output's: when they differ, the app's audio engine converts to the output's rate, as any app must.") {
            HoldoutButtons {
                Button {
                    Task { await model.findHiRes() }
                } label: {
                    HoldoutWords(model.findingHiRes ? "Looking\u{2026}" : (model.hiRes == nil ? "Find a 24/192 FLAC" : "Look again"))
                }
                .disabled(model.findingHiRes)
            }
            if let song = model.hiRes {
                songRow(song, playing: player.current?.track.id == song.id) {
                    model.play([song], at: 0)
                }
            }
            if let words = model.hiResWords { HoldoutLine(words) }
        }
    }

    // MARK: playing

    private var playing: some View {
        HoldoutGroup(legend: "Playing") {
            if let track = player.current?.track {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.title.isEmpty ? track.id : track.title)
                        .font(HoldoutLook.words.weight(.semibold))
                        .foregroundStyle(DWPalette.text)
                    Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " \u{2014} "))
                        .font(HoldoutLook.small)
                        .foregroundStyle(DWPalette.t2)
                    Text("\(player.phaseWords) \u{00B7} \(clock(player.shownPosition))\(player.duration > 0 ? " of \(clock(player.duration))" : "")")
                        .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))
                        .foregroundStyle(DWPalette.t2)
                    if let readout = player.readout {
                        Text(readout)
                            .font(HoldoutLook.small)
                            .foregroundStyle(DWPalette.t2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .holdoutRow()
                HStack {
                    Spacer()
                    Button { player.previous() } label: { SharpSymbol(.previous).font(Typeface.symbol(.body)) }
                        .accessibilityLabel("Previous")
                    Spacer()
                    Button { player.toggle() } label: {
                        PlayPauseGlyph(playing: player.engineState.phase == .playing)
                            .font(Typeface.symbol(.title))
                    }
                    .accessibilityLabel(player.engineState.phase == .playing ? "Pause" : "Play")
                    Spacer()
                    Button { player.next() } label: { SharpSymbol(.next).font(Typeface.symbol(.body)) }
                        .accessibilityLabel("Next")
                        .disabled(nextIndex(player.queue) == nil)
                    Spacer()
                }
                .buttonStyle(DWButtonStyle())
                .holdoutRow()
            } else {
                HoldoutLine("Nothing playing")
            }
            if player.holdsAnEdit {
                HoldoutFact(UpNextWords.title, "An edit held for the next song", words: true)
            }
            if let words = player.lastFailure {
                HoldoutFact("Last failure", words, words: true, tone: DWPalette.redChipText)
            }
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
        HoldoutGroup(legend: EQWords.Debug.header, note: EQWords.Debug.muffleFooter) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HoldoutFact(row.label, row.value, words: true)
            }
            HoldoutSwitch(words: EQWords.Debug.muffle, on: Binding<Bool>(get: { eq.muffle }, set: { (on: Bool) -> Void in
                eq.muffle = on
            }))
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
        HoldoutGroup(legend: "Turntable") {
            ForEach(Array(rows.enumerated()), id: \.offset) { (_: Int, row: InfoRow) in
                HoldoutFact(row.label, row.value, words: !row.mono, note: row.note)
            }
            TurntableRecordingRow(status: recording, shown: deck.hasDeck, url: deck.recordingURL) {
                deck.record()
                recording = deck.recordingStatus
            }
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
        let again = TurntableDebugRows.recordAgain(status, turntable: shown)
        HoldoutFact(said.row.label, said.row.value, words: true, note: said.row.note)
        if said.action != nil || again != nil {
            HoldoutButtons {
                if let action = said.action {
                    if case .saved = status, let url {
                        ShareLink(item: url) { Text(action) }
                    } else {
                        Button(action: record) { HoldoutWords(action) }
                    }
                }
                if let again {
                    Button(action: record) { HoldoutWords(again) }
                }
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
        HoldoutControlRow(label: TurntableDebugRows.trialLabel) {
            Button {
                model.toggle()
            } label: {
                HoldoutWords(TurntableDebugRows.trialButton(running: model.running))
            }
            .buttonStyle(DWButtonStyle(size: .small))
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                model.read()
                try? await Task.sleep(for: .seconds(0.25))
            }
        }
        ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
            HoldoutFact(row.label, row.value)
        }
    }
}

/// The engine's log (EngineTrace): its last lines, the newest last, read again once a second while the log's row is
/// on screen and the app is in front - and only then (not on a locked phone left on Debug with music playing) - and
/// drawn lazily, a line at a time, each in the readout face. Copy puts the whole log on the clipboard as it is at the
/// tap; Share hands it on as text (Mail, Messages, Files...) as last read.
private struct EngineLogSection: View {
    @State private var shown = EngineLog.Snapshot.empty
    @State private var copied = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        HoldoutGroup(legend: "Engine log",
                     note: DebugWords.engineLogFooter(capacity: EngineTrace.log.capacity, total: shown.total,
                                                      device: Platform.device)) {
            HoldoutButtons {
                Button {
                    UIPasteboard.general.string = EngineTrace.log.snapshot().text
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    HoldoutWords(copied ? "Copied" : "Copy")
                }
                ShareLink(item: shown.text, preview: SharePreview("deadwax engine log")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(shown.lines.isEmpty)
            Group {
                if shown.lines.isEmpty {
                    HoldoutLine("Nothing yet: the engine writes here once something plays.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            // by each line's number, which stays its own as the window moves on
                            ForEach(shown.first..<shown.total, id: \.self) { number in
                                Text(shown.lines[number - shown.first])
                                    .font(Platform.mac ? Typeface.Look.mono(.chip) : Typeface.Phone.mono(.extraSmall))
                            }
                        }
                        .foregroundStyle(DWPalette.t2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .frame(height: 320)
                    .holdoutRow()
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
        HoldoutGroup(legend: "Downloads") {
            HoldoutSwitch(words: "Stream even when downloaded",
                          on: Binding(get: { downloads.streamEvenWhenDownloaded },
                                      set: { downloads.streamEvenWhenDownloaded = $0 }))
            ForEach(StoredState.allCases, id: \.self) { state in
                let rows = downloads.records.values.filter { $0.state == state }
                let bytes = rows.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
                HoldoutFact(state.rawValue, "\(rows.count) \u{00B7} \(Bytes.words(bytes))")
            }
            HoldoutFact("Tasks", tasksLine)
            HoldoutFact("Reach", reachability.reach.rawValue + (reachability.probing ? " \u{00B7} probing" : ""))
            HoldoutFact("Path", pathFacts(reachability.path))
            HoldoutFact("Last probe", reachability.lastProbe.map { "\($0.answered ? "answered" : "no answer") \u{00B7} \($0.at.formatted(date: .omitted, time: .standard))" } ?? "none yet")
            HoldoutFact("Plays waiting to be sent", "\(downloads.playsWaiting)")
            HoldoutFact("Starts waiting to be sent", "\(downloads.startsWaiting)")
            if !downloads.checkSeconds.isEmpty {
                let times = Array(downloads.checkSeconds.values)
                HoldoutFact("Checks", "\(times.count) \u{00B7} mean \(String(format: "%.2f", times.reduce(0, +) / Double(times.count))) s \u{00B7} longest \(String(format: "%.2f", times.max() ?? 0)) s")
            }
            if let problem = downloads.storeProblem {
                HoldoutLine(problem, tone: DWPalette.redChipText, readout: true)
            }
            if downloads.log.isEmpty {
                HoldoutLine("No download events yet.")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(downloads.log.suffix(50).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(Platform.mac ? Typeface.Look.mono(.chip) : Typeface.Phone.mono(.extraSmall))
                    }
                }
                .foregroundStyle(DWPalette.t2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .holdoutRow()
            }
        }
        .task {
            while !Task.isCancelled {
                tasks = await downloads.debugTasks()
                tasksRead = true
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// The session's tasks: running, waiting and how many have resume data - "Reading..." until first asked.
    private var tasksLine: String {
        let running = tasks.filter(\.running).count
        let resumable = downloads.records.values.filter { $0.resume != nil }.count
        return tasksRead ? "\(running) running \u{00B7} \(tasks.count - running) waiting \u{00B7} \(resumable) with resume data"
                         : "Reading\u{2026}"
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
/// (slice 3) The phone's power as Only while charging reads it, and the last background runs - check 61's evidence
/// that iOS ran one at all.
private struct LibraryFollowDebugSection: View {
    @Environment(DownloadModel.self) private var downloads

    var body: some View {
        let follower = downloads.follower
        HoldoutGroup(legend: LibraryFollowWords.section, note: LibraryFollowWords.followNote(Platform.device)) {
            if follower.on {
                facts(follower)
            } else {
                HoldoutLine(LibraryFollowWords.notFollowing)
            }
            backgroundRows()
        }
    }

    @ViewBuilder
    private func facts(_ follower: LibraryFollower) -> some View {
        let now = ListenTracker.wallMs()
        let albums = follower.ordered
        let listed = albums.filter(\.isListed).count
        let read = albums.filter { $0.isListed && $0.songs != nil }.count
        if let scope = follower.scope {
            HoldoutFact("Following", LibraryFollowWords.scope(scope), words: true)
        }
        HoldoutFact("Albums", LibraryFollowWords.count(albums.count))
        HoldoutFact("Songs read", LibraryFollowWords.read(read, of: listed)
                    + (follower.readingNow > 0 ? " \u{00B7} reading \(follower.readingNow)" : ""))
        HoldoutFact("Missing", LibraryFollowWords.missing(albums, now: now))
        HoldoutFact("Held back", LibraryFollowWords.held(follower.held, device: Platform.device)
                    + (follower.believing ? " \u{00B7} believing (Remove)" : "")
                    + (follower.keptThem ? " \u{00B7} kept them" : ""), words: true)
        HoldoutFact("Removed, to let go", LibraryFollowWords.count(follower.removed.count))
        HoldoutFact("Leaving their albums", LibraryFollowWords.leaving(albums))
        HoldoutFact("Last check", follower.checking ? "Checking\u{2026}"
                    : follower.lastCheck.map { LibraryFollowWords.lastCheck($0, now: now) } ?? LibraryFollowWords.noCheckYet)
        if let first = follower.firstRead {
            HoldoutFact("First read", LibraryFollowWords.firstRead(seconds: first.seconds, albums: first.albums))
        }
        if let plan = downloads.libraryFill {
            VStack(alignment: .leading, spacing: 2) {
                Text(LibraryFollowWords.wouldFit(plan, limit: downloads.storageLimit, device: Platform.device))
                    .font(HoldoutLook.words)
                    .foregroundStyle(DWPalette.text)
                Text(LibraryFollowWords.fitDetail(plan, device: Platform.device))
                    .font(HoldoutLook.small)
                    .foregroundStyle(DWPalette.t2)
                if plan.deficit > 0 {
                    Text(LibraryFollowWords.underReserve(plan.deficit, confirmed: downloads.libraryDeficitConfirmed))
                        .font(HoldoutLook.small)
                        .foregroundStyle(DWPalette.amberText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .holdoutRow()
            .accessibilityElement(children: .combine)
        }
        if let problem = follower.problem {
            HoldoutLine(problem, tone: DWPalette.redChipText, readout: true)
        }
        HoldoutButtons {
            Button {
                follower.check(.byHand)
            } label: {
                HoldoutWords(LibraryFollowWords.checkNow)
            }
            .disabled(follower.checking)
        }
    }

    /// The power, Only while charging, the albums handed to iOS, and the background runs kept.
    @ViewBuilder
    private func backgroundRows() -> some View {
        HoldoutFact("Power", LibraryFollowWords.power(downloads.power, device: Platform.device)
                    + (downloads.onlyWhileCharging ? " \u{00B7} only while charging" : ""), words: true)
        HoldoutFact("Albums out", LibraryFollowWords.count(downloads.libraryAlbumsOut))
        VStack(alignment: .leading, spacing: 2) {
            Text("In the background")
                .font(HoldoutLook.words)
                .foregroundStyle(DWPalette.text)
            let now = ListenTracker.wallMs()
            if downloads.backgroundRuns.isEmpty {
                Text(LibraryFollowWords.noBackgroundRun)
                    .font(HoldoutLook.small)
                    .foregroundStyle(DWPalette.t2)
            }
            ForEach(Array(downloads.backgroundRuns.enumerated()), id: \.offset) {
                (item: (offset: Int, element: LibraryBackground.Run)) in
                Text(LibraryFollowWords.backgroundRun(item.element, now: now, device: Platform.device))
                    .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))
                    .foregroundStyle(DWPalette.t2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .holdoutRow()
        .accessibilityElement(children: .combine)
    }
}

// MARK: the holdouts' pieces (R20)

/// (R20 - notes/ios.md "The panel review, R20: the known holdouts (2026-11-26)") The pages that kept iOS's grouped lists
/// longest - Debug, an artist's Artist images, Move albums and Which artist is this? - drawn from the canvas's pieces,
/// since no drawing has them (James, 26 Nov: "the undrawn pages are drawn from the canvas's pieces"). Each piece draws
/// its own device's: flat on the phone (R1c) - PhoneGroup's headings, rows on hairlines, the page's black - and on the Mac
/// the Mac's groups (dw.css's `.group`, as MacGroupBox draws it, which a file outside App/Mac can't name) on --bg.
/// Their words in each device's sizes: the phone's `.dw.ph`, the Mac's `.dw` (through Typeface.Look's roles, the only
/// Mac sizes a page both devices draw may name).
enum HoldoutLook {
    /// A row's words: the phone's 16 (.go, .kv), the Mac's 13 (.dw).
    static var words: Font { Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.row) }
    /// .s: the phone's 13, the Mac's 12.
    static var small: Font { Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small) }
    /// .xs: the phone's 12, the Mac's 11.5.
    static var extraSmall: Font { Platform.mac ? Typeface.Look.text(.chip) : Typeface.Phone.text(.extraSmall) }
    /// The page's ground: the phone's black (.dw.ph), the Mac's --bg.
    static var ground: Color { Platform.mac ? DWPalette.bg : DWPalette.page }

    /// The phone's room above and below a row's words, inside its 42 at least (.kv's min-height).
    static let rowRoom: CGFloat = 10
    /// The Mac's room above and below a row in a group (.group.col's gap of 7, shared out).
    static let macRowRoom: CGFloat = 3
    /// The Mac's fact label (Settings.dc.html's `.field > label` and `.kv > span`, 124 wide).
    static let macLabel: CGFloat = 124
    /// The Mac's gap beside a label (.field gap).
    static let macGap: CGFloat = 8
    /// The Mac's room between groups (Settings.dc.html's `.col` gap) and round the page (`.page.pad`, its top 28).
    static let macGroupGap: CGFloat = 24
    static let macPage = EdgeInsets(top: 28, leading: 22, bottom: 22, trailing: 22)
    /// The Mac's group: .group's padding 14px 12px 12px, its legend's 0 6px, 16 tall, set 10 in and 8 up on the edge.
    static let macGroup = EdgeInsets(top: 14, leading: 12, bottom: 12, trailing: 12)
    static let macLegendSide: CGFloat = 6
    static let macLegendHeight: CGFloat = 16
    static let macLegendIn: CGFloat = 10
    static let macLegendUp: CGFloat = -8
    /// The Mac's note under a group, and the buttons' gap (.f gap 6).
    static let macNoteAbove: CGFloat = 6
    static let macButtonGap: CGFloat = 6
    /// The phone's gap between flat buttons on a row.
    static let buttonGap: CGFloat = 12
}

/// (R20) A page of groups on either device: on the phone Settings' own (SettingsPage - 16 in from each edge, down the
/// page's black, no List); on the Mac a scroll of group boxes 24 apart on --bg, the page's 22 either side.
struct HoldoutPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if Platform.mac {
            ScrollView {
                VStack(alignment: .leading, spacing: HoldoutLook.macGroupGap) {
                    content
                }
                .padding(HoldoutLook.macPage)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(DWPalette.bg)
        } else {
            SettingsPage {
                content
            }
            .background(DWPalette.page)
        }
    }
}

/// (R20) A group on either device, with its note under it: on the phone PhoneGroup (its heading over its rows, no face)
/// and Settings' note; on the Mac `.group.onbg` - a box's corners in the line's edge, its legend set into the top edge
/// on --bg, a header for VoiceOver - and the note under it in the third colour.
struct HoldoutGroup<Content: View>: View {
    var legend: String? = nil
    var note: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        if Platform.mac {
            VStack(alignment: .leading, spacing: HoldoutLook.macNoteAbove) {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(HoldoutLook.macGroup)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(DWCorners.boxShape.strokeBorder(DWPalette.line, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if let legend {
                        Text(legend)
                            .font(Typeface.Look.text(.chip).weight(.semibold))
                            .foregroundStyle(DWPalette.label)
                            .lineLimit(1)
                            .padding(.horizontal, HoldoutLook.macLegendSide)
                            .frame(height: HoldoutLook.macLegendHeight)
                            .background(DWPalette.bg)
                            .offset(x: HoldoutLook.macLegendIn, y: HoldoutLook.macLegendUp)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .accessibilityElement(children: .contain)
                if let note, !note.isEmpty {
                    Text(note)
                        .font(HoldoutLook.extraSmall)
                        .foregroundStyle(DWPalette.t3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                PhoneGroup(legend: legend) {
                    content
                }
                if let note, !note.isEmpty {
                    SettingsNote(words: note)
                }
            }
        }
    }
}

/// (R20) A fact's row: its label, then its value on the label's first baseline - in the readout face (Courier Prime,
/// the drawings' `.mono.s`) unless it is `words` - with a `note` under the value in the third colour. On the phone
/// `.kv`'s (PhoneKV's look: the label white at the row's 16, 116 at least, the value at the right in the second colour,
/// 42 tall at least on its hairline), the value under its label where the two don't fit side by side; on the Mac the
/// Mac's Settings' (the label right-aligned at 124 in the second colour, the value beside it in white, 28 tall at least).
/// One element for VoiceOver: its label, then its value.
struct HoldoutFact: View {
    let label: String
    let value: String
    var words = false
    var tone: Color? = nil
    var note: String? = nil

    init(_ label: String, _ value: String, words: Bool = false, tone: Color? = nil, note: String? = nil) {
        self.label = label
        self.value = value
        self.words = words
        self.tone = tone
        self.note = note
    }

    var body: some View {
        if Platform.mac {
            HStack(alignment: .firstTextBaseline, spacing: HoldoutLook.macGap) {
                Text(label)
                    .font(Typeface.Look.text(.fieldLabel))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(width: HoldoutLook.macLabel, alignment: .trailing)
                said(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))
            .accessibilityElement(children: .combine)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: CGFloat(PhoneLook.kvGap)) {
                    phoneLabel
                        .frame(minWidth: CGFloat(PhoneLook.kvLabelWidth), alignment: .leading)
                    Spacer(minLength: 0)
                    said(.trailing)
                }
                VStack(alignment: .leading, spacing: 2) {
                    phoneLabel
                    said(.leading)
                }
            }
            .holdoutRow()
            .accessibilityElement(children: .combine)
        }
    }

    private var phoneLabel: some View {
        Text(label)
            .font(Typeface.Phone.text(.row))
            .foregroundStyle(DWPalette.kvLabel)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The value (and its note), at `edge`.
    private func said(_ edge: HorizontalAlignment) -> some View {
        VStack(alignment: edge, spacing: 2) {
            if words {
                // PhoneKV's value at the row's 16; MacSettingsFact's at the Mac's 13
                Text(value)
                    .font(HoldoutLook.words)
            } else {
                Text(value)
                    .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))
            }
            if let note, !note.isEmpty {
                Text(note)
                    .font(HoldoutLook.extraSmall)
                    .foregroundStyle(DWPalette.t3)
            }
        }
        .foregroundStyle(tone ?? (Platform.mac ? DWPalette.text : DWPalette.t2))
        .multilineTextAlignment(edge == .trailing ? .trailing : .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// (R20) A line of a group's own: words in the small size - the second colour unless said - or (`readout`) data in the
/// readout face, selectable (a problem's own words, to send on); wrapping, a row of the group's.
struct HoldoutLine: View {
    let words: String
    var tone: Color = DWPalette.t2
    var readout = false

    init(_ words: String, tone: Color = DWPalette.t2, readout: Bool = false) {
        self.words = words
        self.tone = tone
        self.readout = readout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if readout {
                Text(words)
                    .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.small))
                    .textSelection(.enabled)
            } else {
                Text(words)
                    .font(HoldoutLook.small)
            }
        }
        .foregroundStyle(tone)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .holdoutRow()
    }
}

/// (R20) A row of buttons in a group: DWButtonStyle's small - flat accent words on the phone, the Mac's faced buttons -
/// side by side, and on the phone one over another, each the row's width, at the accessibility sizes and wherever side
/// by side they don't fit (R20's review: Debug's "Save the recording (1.2 MB)" and "Record 20 s again" are 368 at xLarge
/// on a 375 phone's 343) - RequestCards' ButtonPair's rule. Stacked, 12 apart, so no button's 44 reaches over the next's
/// face. A button that is another kind (the red) says so itself.
struct HoldoutButtons<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if Platform.mac {
                side
            } else if typeSize.isAccessibilitySize {
                stack
            } else {
                ViewThatFits(in: .horizontal) {
                    side
                    stack
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .holdoutRow()
    }

    private var side: some View {
        HStack(spacing: Platform.mac ? HoldoutLook.macButtonGap : HoldoutLook.buttonGap) {
            content
        }
        .buttonStyle(DWButtonStyle(size: .small))
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: HoldoutLook.buttonGap) {
            content
        }
        .buttonStyle(DWButtonStyle(size: .small, fills: true))
    }
}

/// (R20) A row with one control beside its name: on the phone the name at the row's 16 in white and the control at the
/// row's end; on the Mac a Settings row - the name right-aligned at 124 in the second colour, the control beside it. One
/// element for VoiceOver, the control's action its own.
struct HoldoutControlRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: Control

    var body: some View {
        if Platform.mac {
            HStack(spacing: HoldoutLook.macGap) {
                Text(label)
                    .font(Typeface.Look.text(.fieldLabel))
                    .foregroundStyle(DWPalette.t2)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(width: HoldoutLook.macLabel, alignment: .trailing)
                control
                Spacer(minLength: 0)
            }
            .frame(minHeight: CGFloat(DWLook.here.fieldRowHeight))
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: CGFloat(PhoneLook.goGap)) {
                Text(label)
                    .font(Typeface.Phone.text(.row))
                    .foregroundStyle(DWPalette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                control
            }
            .holdoutRow()
            .accessibilityElement(children: .combine)
        }
    }
}

/// (R20) A switch's row: on the phone the purple switch on Settings' row (settingsSwitch); on the Mac the checkbox, as
/// the Mac's Settings draws a choice in a group (DWCheckbox). Either is a toggle to VoiceOver, its name and its state.
struct HoldoutSwitch: View {
    let words: String
    @Binding var on: Bool

    var body: some View {
        if Platform.mac {
            DWCheckbox(words: words, on: $on)
                .frame(maxWidth: .infinity, alignment: .leading)
                .holdoutRow()
        } else {
            Toggle(isOn: $on) {
                Text(words)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsSwitch()
        }
    }
}

/// (R20) A button's words: one line, and up to three at the accessibility sizes (DWButtonStyle draws one line).
struct HoldoutWords: View {
    let words: String
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ words: String) {
        self.words = words
    }

    var body: some View {
        Text(words)
            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
            .multilineTextAlignment(.center)
    }
}

/// (R20) A page that can't be drawn yet - opened out of reach: its glyph, its name and why, centred on the page's ground
/// (in place of the system's ContentUnavailableView and its grey). One element for VoiceOver.
struct HoldoutUnavailable: View {
    let title: String
    let symbol: String
    let words: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(Typeface.symbol(.title2))
                .foregroundStyle(DWPalette.t3)
            Text(title)
                .font(HoldoutLook.words.weight(.semibold))
                .foregroundStyle(DWPalette.text)
            Text(words)
                .font(HoldoutLook.small)
                .foregroundStyle(DWPalette.t2)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, CGFloat(PhoneLook.bigSide))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HoldoutLook.ground)
        .accessibilityElement(children: .combine)
    }
}

/// (R20) A field you type in, on the look's well on either device: on the phone DWWellField (its focus the page's own);
/// on the Mac `.in` - the plain field in the field's type on DWWell, 24 tall, the accent's edge while it has the cursor
/// (DWWellField draws nothing on the Mac: the page's own field, which a List boxed until now) - and (R20's review) a
/// click on the well's room either side of the words puts the cursor in it, as DWField's does.
struct HoldoutField<Field: Hashable>: ViewModifier {
    let focus: FocusState<Field?>.Binding
    let field: Field

    @ViewBuilder func body(content: Content) -> some View {
        if Platform.mac {
            content
                .textFieldStyle(.plain)
                .font(Typeface.Look.text(.field))
                .foregroundStyle(DWPalette.fieldText)
                .focusEffectDisabled()
                // .in: padding 0 8px
                .padding(.horizontal, 8)
                .lookHeight(DWLook.here.fieldHeight)
                .background {
                    DWWell(focused: focus.wrappedValue == field)
                        .contentShape(DWTarget(face: DWCorners.buttonShape))
                        .onTapGesture {
                            focus.wrappedValue = field
                        }
                }
        } else {
            content
                .modifier(DWWellField(focus: focus, field: field))
        }
    }
}

extension View {
    /// (R20) A row of a group's: on the phone 10 above and below its words, 42 tall at least (.kv), on the group's
    /// hairline (PhoneGroup clips the last one's); on the Mac its content's height with 3 above and below, no line (the
    /// Mac's groups draw none between their rows).
    @ViewBuilder func holdoutRow() -> some View {
        if Platform.mac {
            padding(.vertical, HoldoutLook.macRowRoom)
        } else {
            padding(.vertical, HoldoutLook.rowRoom)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lookHeight(PhoneLook.kvRow)
                .overlay(alignment: .bottom) { DWRule(colour: DWPalette.groupRule) }
        }
    }
}
