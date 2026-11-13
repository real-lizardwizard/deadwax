import DeadwaxCore
import SwiftUI

/// You > Playback (screens.md 8): Gapless, which the phone can't turn off - its engine joins every song end to end,
/// so the row says On and the line under it what that means (Open question 1) - and Normalization, the web's four
/// choices with the web's names and notes (Core's Normalization: Off's note without "unless Maximum quality converts
/// it", D3), Automatic by default.
///
/// The choice is PlayerModel's `normalization`, kept on this phone (UserDefaults, the web's key) and read at each
/// play's tap - so it changes from the next thing played, never what is already queued (the footer says so). The
/// rows are a radio group: one chosen, a tap picks, VoiceOver hears each choice's name, whether it is chosen, and its
/// note.
///
/// Between them, in the web's order (You.tsx:296-320), the turntable's two (turntable.md 6.1, app 0.6): "Now Playing
/// opens as" - Cover or Turntable, a radio group as Normalization's is - and "Pause winds the record down", each a
/// Section with the web's note as its footer, less the note's last sentence about the web's desktop frame. Both
/// DeckController's, kept on this phone under the web's keys.
///
/// Then the EQ (eq.md 3.1, app 0.5): one row - "EQ", the output now under it, its short setting at the right - pushing
/// the EQ page of the output now; its footer ends as Normalization's does, "This is kept on this phone."
struct PlaybackSection: View {
    @Environment(PlayerModel.self) private var player
    @Environment(EQModel.self) private var eq
    @Environment(DeckController.self) private var deck

    var body: some View {
        Section {
            LabeledContent(YouWords.gapless, value: YouWords.gaplessOn)
        } header: {
            Text(YouWords.playback)
        } footer: {
            Text(YouWords.gaplessLine)
        }

        Section {
            ForEach(TurntableSettings.Look.allCases, id: \.self) { (look: TurntableSettings.Look) in
                lookRow(look)
            }
        } header: {
            Text(TurntableWords.opensAs)
        } footer: {
            Text(TurntableWords.lookNote)
        }

        Section {
            Toggle(TurntableWords.windDown, isOn: Binding<Bool>(get: { deck.windDown }, set: { (on: Bool) -> Void in
                deck.windDown = on
            }))
        } footer: {
            Text(TurntableWords.windDownNote)
        }

        Section {
            ForEach(Normalization.allCases, id: \.self) { choice in
                row(choice)
            }
        } header: {
            Text(Normalization.title)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(YouWords.normalizationNote)
                Text(YouWords.kept)
            }
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
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                }
            }
        } footer: {
            Text(EQWords.You.footer)
        }
    }

    /// A look: its name, the checkmark on the chosen one (LookChoice.tsx's radio).
    private func lookRow(_ look: TurntableSettings.Look) -> some View {
        let chosen = deck.opensAs == look
        let label = look == .turntable ? TurntableWords.lookTurntable : TurntableWords.lookCover
        return Button {
            deck.opensAs = look
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .opacity(chosen ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    private func row(_ choice: Normalization) -> some View {
        let chosen = player.normalization == choice
        return Button {
            player.normalization = choice
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(choice.label)
                        .foregroundStyle(.primary)
                    Text(choice.note)
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
        .accessibilityLabel(choice.label)
        .accessibilityHint(choice.note)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}
