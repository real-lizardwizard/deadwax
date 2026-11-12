import DeadwaxCore
import SwiftUI
import UIKit

/// You's Debug (admins only, D1): Phase 0's one screen, moved - Check's report, the test sounds, the hi-res row,
/// what is playing (with the engine's own words for its last failure, D7, and an Up Next edit held for the join, D4),
/// the engine's log (its last 500 lines, with Copy and Share), the Library's last album list asks (how many albums,
/// how long - check 1), and how long this install runs. The address and the sign-in are the app's own screens now.
struct DebugView: View {
    @Environment(DebugModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(LibraryModel.self) private var library

    init() {}

    var body: some View {
        Form {
            server
            if model.report?.ok == true {
                testSounds
                hiRes
            }
            playing
            EngineLogSection()
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
            Picker("Play", selection: Binding(get: { model.source }, set: { model.source = $0 })) {
                ForEach(DebugModel.Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            ForEach(Array(model.testSongs.enumerated()), id: \.element.id) { index, song in
                songRow(song, playing: player.current?.track.id == song.id) {
                    model.play(model.testSongs, at: index)
                }
            }
            if !model.testSongs.isEmpty {
                let missing = model.testSongs.filter { !model.downloaded.contains($0.id) }
                Button(missing.isEmpty ? "All downloaded" : "Download all \(model.testSongs.count)") {
                    Task { await model.download(model.testSongs) }
                }
                .disabled(missing.isEmpty || !model.downloading.isEmpty)
                if !model.downloaded.isEmpty {
                    Button("Remove the downloads", role: .destructive) { model.removeDownloads() }
                }
            }
            if let words = model.testWords { Text(words).font(.footnote) }
            if let words = model.downloadWords { Text(words).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Test sounds")
        } footer: {
            Text("Songs 1 to 8 are three beeps each: tap one to play the album from it and count the beeps - all three, every time? Songs 9 and 10 are one tone cut in two: played one into the other, the tone should never break. \"Downloaded\" plays the copies on the phone (a song with none is streamed).")
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
                    Task { await model.download([song]) }
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
