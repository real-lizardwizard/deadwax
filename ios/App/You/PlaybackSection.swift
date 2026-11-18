import DeadwaxCore
import SwiftUI

/// Settings > Playback (16 Nov, a page of its own - You's Playback section before; screens.md 8): PlaybackSection, and
/// the EQ pushed from it as before. Everything on it is this phone's own, so nothing is asked of deadwax here.
struct PlaybackPage: View {
    var body: some View {
        List {
            PlaybackSection()
        }
        .navigationTitle(YouWords.playback)
    }
}

/// Playback's choices (screens.md 8), in the web's order (You.tsx:296-320):
///
/// - **Gapless**, which the phone can't turn off - its engine joins every song end to end, so the row says On and the
///   line under it what that means (Open question 1).
/// - The turntable's two (turntable.md 6.1, app 0.6): **Now Playing opens as** - Cover or Turntable - and **Pause
///   winds the record down**, each a Section with the web's note as its footer, less the note's last sentence about the
///   web's desktop frame. Both DeckController's, kept on this phone under the web's keys. (The Mac app, slice 2) Not on
///   the Mac, which has no turntable: Now Playing is the cover there (NowPlayingView's `look`).
/// - **Normalization**, the web's four choices with the web's names (Core's Normalization: Off's note without "unless
///   Maximum quality converts it", D3), Automatic by default. The choice is PlayerModel's `normalization`, kept on this
///   phone (UserDefaults, the web's key) and read at each play's tap - so it changes from the next thing played, never
///   what is already queued (the footer says so).
/// - The **EQ** (eq.md 3.1, app 0.5): one row - "EQ", the output now under it, its short setting at the right - pushing
///   the EQ page of the output now; its footer ends as Normalization's does, "This is kept on this phone."
///
/// (16 Nov) Now Playing opens as and Normalization are each one row with the choice at its right, a menu of the
/// choices (`.pickerStyle(.menu)`) - lists of ticks until then; James: "maybe some dropdowns instead of big lists".
/// Normalization's choices each had a line of their own under their name: the chosen one's line now leads the footer,
/// before the web's note, and VoiceOver hears it as the row's hint. The others' lines show only once chosen: the menu
/// names each choice, nothing more. VoiceOver reads
/// each row's name and its choice. The toggle stays a toggle.
struct PlaybackSection: View {
    @Environment(PlayerModel.self) private var player
    @Environment(EQModel.self) private var eq
    @Environment(DeckController.self) private var deck

    var body: some View {
        Section {
            LabeledContent(YouWords.gapless, value: YouWords.gaplessOn)
        } footer: {
            Text(YouWords.gaplessLine)
                .font(Typeface.footnote)
        }

        // the turntable's two: not on the Mac, which has no turntable (NowPlayingView's `look`)
        if !Platform.mac {
            Section {
                Picker(TurntableWords.opensAs, selection: Binding<TurntableSettings.Look>(get: { deck.opensAs },
                                                                                       set: { (look: TurntableSettings.Look) -> Void in
                                                                                           deck.opensAs = look
                                                                                       })) {
                    ForEach(TurntableSettings.Look.allCases, id: \.self) { (look: TurntableSettings.Look) in
                        Text(Self.name(look)).tag(look)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text(TurntableWords.lookNote)
                    .font(Typeface.footnote)
            }

            Section {
                Toggle(TurntableWords.windDown, isOn: Binding<Bool>(get: { deck.windDown }, set: { (on: Bool) -> Void in
                    deck.windDown = on
                }))
            } footer: {
                Text(TurntableWords.windDownNote)
                    .font(Typeface.footnote)
            }
        }

        Section {
            Picker(Normalization.title, selection: Binding<Normalization>(get: { player.normalization },
                                                                        set: { (choice: Normalization) -> Void in
                                                                            player.normalization = choice
                                                                        })) {
                ForEach(Normalization.allCases, id: \.self) { (choice: Normalization) in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.menu)
            // what the chosen one does, as its row's line said under it
            .accessibilityHint(player.normalization.note)
        } footer: {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    // the chosen one's own line first: what it does
                    Text(player.normalization.note)
                    Text(YouWords.normalizationNote)
                    Text(YouWords.kept)
                }
            }
            .font(Typeface.footnote)
        }

        Section {
            let now = eq.now
            EQLink(route: .now) {
                LabeledContent {
                    Text(now.short)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(EQWords.You.row)
                        Text(now.name)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                }
            }
        } footer: {
            Text(EQWords.You.footer)
                .font(Typeface.footnote)
        }
    }

    /// A look's name (LookChoice.tsx's): Cover, Turntable.
    private static func name(_ look: TurntableSettings.Look) -> String {
        look == .turntable ? TurntableWords.lookTurntable : TurntableWords.lookCover
    }
}
