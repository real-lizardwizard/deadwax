import DeadwaxCore
import SwiftUI

/// "Yours or the collection's" under the hero (screens.md 4's mine block; logins on with a library of your own only):
/// Whose's line, its Add to my library (filled) or Remove from my library (a text button), and a refusal in ErrorWords'
/// words under it. While the button's ask is out it says "Adding…" / "Removing…" and takes no second tap, but stays a
/// button, so VoiceOver's focus stays on it (the web's aria-disabled). The line takes VoiceOver's focus when an Add or
/// Remove is taken (`noteFocused`), as the web hands its focus to the line.
struct MineBlock: View {
    let mine: AlbumMine
    let busy: Bool
    let refused: (any Error)?
    let act: (AlbumMine.Action) -> Void
    var noteFocused: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 10) {
            if let note = mine.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused(noteFocused)
            }
            if let action = mine.action {
                let words = Whose.button(action, busy: busy)
                Group {
                    switch action {
                    case .add:
                        Button(words) { if !busy { act(action) } }
                            .buttonStyle(.borderedProminent)
                    case .remove:
                        Button(words) { if !busy { act(action) } }
                            .buttonStyle(.borderless)
                    }
                }
                .opacity(busy ? 0.55 : 1)
            }
            if let refused {
                ErrorNote(refused)
                    .foregroundStyle(AlbumPalette.refused)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The mine block's place, held unseen while whose it is is still to come (Whose.placeholderShown): the line and the
/// button most likely to land, so the songs below don't move under a finger when they do.
struct MinePlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Text(Whose.addFromPage)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(Whose.placeholderButton) {}
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .hidden()
        .accessibilityHidden(true)
    }
}
