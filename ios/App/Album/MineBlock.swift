import DeadwaxCore
import SwiftUI

/// "Yours or the collection's" under the hero (screens.md 4's mine block; logins on with a library of your own only):
/// Whose's line, its Add to my library (filled) or Remove from my library (a text button), and a refusal in ErrorWords'
/// words under it. While the button's ask is out it says "Adding…" / "Removing…" and takes no second tap, but stays a
/// button, so VoiceOver's focus stays on it (the web's aria-disabled). The line takes VoiceOver's focus when an Add or
/// Remove is taken (`noteFocused`), as the web hands its focus to the line.
///
/// (R18 - notes/ios.md "The panel review, R18: sheets, faces and banners (2026-11-26)") The look's buttons: Add the
/// purple one (DWButtonStyle's, for PrimaryFace's 17 pt label), Remove a flat button's accent words (for the system's
/// borderless); the line in the small greys, the refusal in the red chip's words. Its words take three lines at the
/// accessibility sizes, where the button fills the page's width.
struct MineBlock: View {
    let mine: AlbumMine
    let busy: Bool
    let refused: (any Error)?
    let act: (AlbumMine.Action) -> Void
    var noteFocused: AccessibilityFocusState<Bool>.Binding
    /// (Phase 3) Remove from my library takes the album's download from this phone too: said with the line.
    var goesToo = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        VStack(spacing: 10) {
            if let note = line, !note.isEmpty {
                Text(note)
                    .font(SheetLook.small)
                    .foregroundStyle(DWPalette.t2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused(noteFocused)
            }
            if let action = mine.action {
                let words = Whose.button(action, busy: busy)
                Group {
                    switch action {
                    case .add:
                        Button { if !busy { act(action) } } label: { SheetButtonWords(words) }
                            .buttonStyle(DWButtonStyle(kind: .pri, fills: stacked))
                    case .remove:
                        Button { if !busy { act(action) } } label: { SheetButtonWords(words) }
                            .buttonStyle(DWButtonStyle(fills: stacked))
                    }
                }
                .opacity(busy ? DWPalette.off : 1)
            }
            if let refused {
                ErrorNote(refused)
                    .foregroundStyle(DWPalette.redChipText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Whose's line - with "Its download goes from this phone too." while its button is Remove from my library and the
    /// album's download is your library's alone (phase3-autodownload.md 3.4).
    private var line: String? {
        guard goesToo, mine.action == .remove else { return mine.note }
        return [mine.note, AutoDownloadWords.goesToo(Platform.device)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The mine block's place, held unseen while whose it is is still to come (Whose.placeholderShown): the line and the
/// button most likely to land, so the songs below don't move under a finger when they do - (R18) in the very words,
/// sizes and button MineBlock draws them in.
struct MinePlaceholder: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 10) {
            Text(Whose.addFromPage)
                .font(SheetLook.small)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {} label: { SheetButtonWords(Whose.placeholderButton) }
                .buttonStyle(DWButtonStyle(kind: .pri, fills: typeSize.isAccessibilitySize))
        }
        .frame(maxWidth: .infinity)
        .hidden()
        .accessibilityHidden(true)
    }
}
