import DeadwaxCore
import SwiftUI

/// Phase 0's one screen: the address and Check, signing in when logins are on, the test sounds,
/// the hi-res row, what is playing, and how long this install runs.
struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                server
                if model.report?.needsSignIn == true { signIn }
                if model.report?.ok == true {
                    testSounds
                    hiRes
                }
                playing
                Section {
                    Text(model.installLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.quiet)
                } footer: {
                    Text(version)
                }
            }
            .navigationTitle("deadwax")
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "deadwax for iPhone \(short) (\(build)) - Phase 0"
    }

    // MARK: the server

    private var server: some View {
        Section {
            TextField("http://192.168.1.20:8090", text: $model.addressText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { Task { await model.check() } }
            Button(model.checking ? "Checking\u{2026}" : "Check") {
                Task { await model.check() }
            }
            .disabled(model.checking)
            ForEach(model.report?.lines ?? [], id: \.self) { line in
                Text(line).font(.footnote)
            }
            if model.me?.loginsOn == true {
                Button("Sign out", role: .destructive) { Task { await model.signOut() } }
            }
        } header: {
            Text("deadwax's address")
        } footer: {
            Text("The address you open deadwax at, by IP or by name. The first time, iOS asks to let deadwax find devices on your local network: say yes.")
        }
    }

    private var signIn: some View {
        Section {
            TextField("Navidrome user name", text: $model.username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $model.password)
                .textContentType(.password)
                .onSubmit { Task { await model.signIn() } }
            Button(model.signingIn ? "Signing in\u{2026}" : "Sign in") { Task { await model.signIn() } }
                .disabled(model.signingIn || model.username.isEmpty || model.password.isEmpty)
            if let words = model.signInWords {
                Text(words).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Sign in")
        } footer: {
            Text("Your Navidrome name and password, as on the web app. The password isn't kept on the phone: only the session deadwax gives back, in the Keychain.")
        }
    }

    // MARK: the test sounds

    private var testSounds: some View {
        Section {
            Picker("Play", selection: $model.source) {
                ForEach(AppModel.Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            ForEach(Array(model.testSongs.enumerated()), id: \.element.id) { index, song in
                songRow(song, playing: model.queue.current?.id == song.id) {
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
                songRow(song, playing: model.queue.current?.id == song.id) {
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
            if let song = model.queue.current {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.name).font(.headline)
                    Text([song.artist, song.album].compactMap { $0 }.joined(separator: " \u{2014} "))
                        .font(.subheadline).foregroundStyle(Palette.quiet)
                    Text("\(model.phaseWords) \u{00B7} \(clock(model.elapsed))\(song.duration.map { " of \(clock($0))" } ?? "")")
                        .font(.footnote.monospacedDigit())
                    if let readout = model.readout {
                        Text(readout).font(.footnote)
                    }
                }
                HStack {
                    Spacer()
                    Button { model.previous() } label: { Image(systemName: "backward.fill") }
                        .accessibilityLabel("Previous")
                    Spacer()
                    Button { model.toggle() } label: {
                        Image(systemName: model.engineState.phase == .playing ? "pause.fill" : "play.fill")
                            .font(.title)
                    }
                    .accessibilityLabel(model.engineState.phase == .playing ? "Pause" : "Play")
                    Spacer()
                    Button { model.next() } label: { Image(systemName: "forward.fill") }
                        .accessibilityLabel("Next")
                        .disabled(model.queue.nextIndex == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 4)
            } else {
                Text("Nothing playing").foregroundStyle(Palette.quiet)
            }
            if let words = model.playWords {
                Text(words).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Playing")
        }
    }

    private func clock(_ seconds: Double) -> String {
        let whole = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
