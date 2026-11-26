import DeadwaxCore
import SwiftUI

/// Settings > Playback (16 Nov, a page of its own - You's Playback section before; screens.md 8): PlaybackSection, and
/// the EQ pushed from it as before. Everything on it is this phone's own, so nothing is asked of deadwax here. (R9)
/// Flat, a Settings page (SettingsPage).
struct PlaybackPage: View {
    var body: some View {
        SettingsPage {
            PlaybackSection()
        }
        .navigationTitle(YouWords.playback)
    }
}

/// Playback's choices (screens.md 8), in the web's order (You.tsx:296-320):
///
/// - **Gapless**, which the phone can't turn off - its engine joins every song end to end, so the row says On and the
///   line under it what that means (Open question 1). (R9) A fact on its hairline, never a switch: there is no setting
///   behind it (the build plan's 3.6) - the drawing's Gapless switch isn't drawn.
/// - The turntable's two (turntable.md 6.1, app 0.6): **Now Playing opens as** - Cover or Turntable - and **Pause
///   winds the record down**, each a group with the web's note under it, less the note's last sentence about the
///   web's desktop frame. Both DeckController's, kept on this phone under the web's keys. (The Mac app, slice 2) Not on
///   the Mac, which has no turntable: Now Playing is the cover there (NowPlayingView's `look`).
/// - **Normalization**, the web's four choices with the web's names (Core's Normalization: Off's note without "unless
///   Maximum quality converts it", D3), Automatic by default. The choice is PlayerModel's `normalization`, kept on this
///   phone (UserDefaults, the web's key) and read at each play's tap - so it changes from the next thing played, never
///   what is already queued (the note says so).
/// - The **EQ** (eq.md 3.1, app 0.5): one row - "EQ", the output now under it, its short setting at the right - pushing
///   the EQ page of the output now; its note ends as Normalization's does, "This is kept on this phone."
///
/// (16 Nov) Now Playing opens as and Normalization are each one row with the choice at its right, a menu of the
/// choices (`.pickerStyle(.menu)`) - lists of ticks until then; James: "maybe some dropdowns instead of big lists".
/// Normalization's choices each had a line of their own under their name: the chosen one's line now leads the note,
/// before the web's note, and VoiceOver hears it as the row's hint. The others' lines show only once chosen: the menu
/// names each choice, nothing more. VoiceOver reads each row's name and its choice. (R9) Each row flat on its group's
/// hairline (SettingsChoiceRow), each note under its group (SettingsNote); the toggle the purple switch
/// (`.toggleStyle(.phoneSwitch)`), unchanged in what it does.
struct PlaybackSection: View {
    @Environment(PlayerModel.self) private var player
    @Environment(EQModel.self) private var eq
    @Environment(DeckController.self) private var deck

    var body: some View {
        PhoneGroup {
            PhoneKV(label: YouWords.gapless, value: YouWords.gaplessOn)
        }
        SettingsNote(words: YouWords.gaplessLine)

        // the turntable's two: not on the Mac, which has no turntable (NowPlayingView's `look`)
        if !Platform.mac {
            PhoneGroup {
                SettingsChoiceRow(title: TurntableWords.opensAs) {
                    Picker(TurntableWords.opensAs, selection: Binding<TurntableSettings.Look>(get: { deck.opensAs },
                                                                                           set: { (look: TurntableSettings.Look) -> Void in
                                                                                               deck.opensAs = look
                                                                                           })) {
                        ForEach(TurntableSettings.Look.allCases, id: \.self) { (look: TurntableSettings.Look) in
                            Text(Self.name(look)).tag(look)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            SettingsNote(words: TurntableWords.lookNote)

            PhoneGroup {
                Toggle(TurntableWords.windDown, isOn: Binding<Bool>(get: { deck.windDown }, set: { (on: Bool) -> Void in
                    deck.windDown = on
                }))
                .toggleStyle(.phoneSwitch)
                .settingsRow()
            }
            SettingsNote(words: TurntableWords.windDownNote)
        }

        PhoneGroup {
            SettingsChoiceRow(title: Normalization.title) {
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
            }
        }
        // the chosen one's own line first: what it does
        SettingsNote(words: player.normalization.note)
        SettingsNote(words: YouWords.normalizationNote)
        SettingsNote(words: YouWords.kept(Platform.device))

        PhoneGroup {
            let now = eq.now
            EQLink(route: .now) {
                SettingsGo {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(EQWords.You.row)
                        Text(now.name)
                            .font(Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.t2)
                    }
                } value: {
                    // centred on the two lines beside it, in their face, as today's row has it
                    Text(now.short)
                        .foregroundStyle(DWPalette.t3)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
        SettingsNote(words: EQWords.You.footer(Platform.device))
    }

    /// A look's name (LookChoice.tsx's): Cover, Turntable.
    private static func name(_ look: TurntableSettings.Look) -> String {
        look == .turntable ? TurntableWords.lookTurntable : TurntableWords.lookCover
    }
}
