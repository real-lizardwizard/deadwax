import DeadwaxCore
import SwiftUI

/// You > Getting albums (Phase 6 - phase6-get-requests.md 2.12; the web's You.tsx, GettingChoices.tsx and
/// ConfirmCancelChoice.tsx), top to bottom:
///
/// - (Slice 3) **When I tap Get** (Show me the sources, Pick the best source for me), **Quality floor** (Any, 320 kbps,
///   Lossless, 24-bit) and **Format** (Any, Prefer lossless, Lossless only): each a list of rows, the chosen one
///   checked, one tap a choice - kept for the person on deadwax (GetSettingsModel), so they follow them to every
///   device. Until deadwax has first answered, nothing shows as chosen and nothing can be chosen: showing the defaults
///   as chosen would claim what nobody knows yet. After that a choice shows at once and is saved behind it. While
///   deadwax can't be reached, nothing can be chosen, and the section says why.
/// - Under the three, the web's note on what they mean; deadwax's database unable to keep them ("Tell whoever runs
///   deadwax." for anyone but whoever runs it); and a choice not kept, said to VoiceOver as the choice goes back.
/// - **Confirm before cancelling** (slice 1), this phone's own - Requests' ✕ reads it at the tap - kept in UserDefaults
///   under the web's key, on unless turned off. After the three's note, so neither reads as being about the other.
///
/// You asks deadwax for the three each time its tab shows and on its pull (YouView).
struct GettingAlbumsSection: View {
    @AppStorage(ConfirmCancel.storageKey) private var stored: String?
    @Environment(GetSettingsModel.self) private var getting
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let settings = getting.settings
        let live = settings != nil && reachability.online
        Section {
            ForEach(GetMode.allCases, id: \.self) { (mode: GetMode) in
                row(mode.label, chosen: settings?.mode == mode, live: live) { getting.choose(GetChoice(mode: mode)) }
            }
        } header: {
            VStack(alignment: .leading, spacing: 10) {
                Text(RequestWords.gettingAlbums)
                    .accessibilityAddTraits(.isHeader)
                Text(GettingWords.modeTitle)
            }
            .font(Typeface.footnote)
        }

        Section {
            ForEach(QualityFloor.allCases, id: \.self) { (floor: QualityFloor) in
                row(floor.label, chosen: settings?.floor == floor, live: live) { getting.choose(GetChoice(floor: floor)) }
            }
        } header: {
            Text(GettingWords.floorTitle)
                .font(Typeface.footnote)
        }

        Section {
            ForEach(FormatPreference.youOrder, id: \.self) { (format: FormatPreference) in
                row(format.label, chosen: settings?.format == format, live: live) {
                    getting.choose(GetChoice(format: format))
                }
            }
        } header: {
            Text(GettingWords.formatTitle)
                .font(Typeface.footnote)
        } footer: {
            footer
        }

        Section {
            Toggle(RequestWords.confirmCancel, isOn: Binding<Bool>(get: { ConfirmCancel.read(stored) },
                                                                  set: { (on: Bool) -> Void in
                                                                      stored = ConfirmCancel.stored(on)
                                                                  }))
        } footer: {
            Text(RequestWords.confirmCancelNote)
                .font(Typeface.footnote)
        }
    }

    /// The note under the three, and what stands in the way of keeping them.
    private var footer: some View {
        let problem = getting.problem(admin: server.access.seesDetail)
        return VStack(alignment: .leading, spacing: 8) {
            if !reachability.online {
                // why none can be chosen just now - the Sources sheet's and the album page's words
                Text(StoreLine.offline)
            }
            Text(GettingWords.note)
            if !getting.canSave {
                Text(GettingWords.unsavedLine(runsDeadwax: server.access.seesDetail))
                    .foregroundStyle(Palette.danger)
            }
            if reachability.online, let problem {
                Text(problem)
                    .foregroundStyle(Palette.danger)
            }
        }
        .font(Typeface.footnote)
        .fixedSize(horizontal: false, vertical: true)
        // a choice that wasn't kept, heard as it goes back
        .onChange(of: problem) { _, said in
            if let said, reachability.online { Notice.announce(said) }
        }
    }

    /// A choice: its name, the checkmark on the chosen one (GettingChoices.tsx's radio) - off, unchecked, until deadwax
    /// has answered, and while it can't be reached.
    private func row(_ label: String, chosen: Bool, live: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            guard live, !chosen else { return }
            pick()
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(Typeface.symbol(.body).weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .opacity(chosen ? 1 : 0)
            }
            .opacity(live ? 1 : Palette.off)
            .contentShape(Rectangle())
        }
        .disabled(!live)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}
