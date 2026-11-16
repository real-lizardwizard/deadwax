import DeadwaxCore
import SwiftUI

/// Settings > Getting albums (16 Nov, a page of its own - You's Getting albums section before; Phase 6 -
/// phase6-get-requests.md 2.12; the web's You.tsx, GettingChoices.tsx and ConfirmCancelChoice.tsx). Its section, and
/// the asking: deadwax is asked for the three each time the page shows (changed on another device, they show here), on
/// its pull and as deadwax comes back into reach - the web asks them each time You's tab opens, and on Check again. What
/// is in hand stands meanwhile. Nothing else asks for them on Settings now: the root draws none of them (and Get asks
/// for itself - the album you don't have as it shows, the Sources sheet before every search).
struct GettingAlbumsPage: View {
    @Environment(GetSettingsModel.self) private var getting
    @Environment(Reachability.self) private var reachability

    var body: some View {
        List {
            GettingAlbumsSection()
        }
        .navigationTitle(RequestWords.gettingAlbums)
        .refreshable {
            await getting.ask().value
        }
        .onAppear { getting.ask() }
        .onChange(of: reachability.online) { _, back in
            if back { getting.ask() }
        }
    }
}

/// Getting albums' choices, top to bottom:
///
/// - (Slice 3) **When I tap Get** (Show me the sources, Pick the best source for me), **Quality floor** (Any, 320 kbps,
///   Lossless, 24-bit) and **Format** (Any, Prefer lossless, Lossless only): (16 Nov) each one row, its name and the
///   choice at its right, a menu of the choices (`.pickerStyle(.menu)`) - lists of ticks until then; James: "maybe
///   some dropdowns instead of big lists". Kept for the person on deadwax (GetSettingsModel), so they follow them to
///   every device. Until deadwax has first answered, nothing shows as chosen (the row's value is empty) and nothing can
///   be chosen: showing the defaults as chosen would claim what nobody knows yet. After that a choice shows at once and
///   is saved behind it. While deadwax can't be reached, nothing can be chosen (the rows are off), and the section says
///   why. VoiceOver reads each row's name and its choice.
/// - Under the three, the web's note on what they mean - none of their choices has a line of its own, so nothing moved
///   into it; deadwax's database unable to keep them ("Tell whoever runs deadwax." for anyone but whoever runs it); and
///   a choice not kept, said to VoiceOver as the choice goes back.
/// - **Confirm before cancelling** (slice 1), this phone's own - Requests' ✕ reads it at the tap - kept in UserDefaults
///   under the web's key, on unless turned off. After the three's note, so neither reads as being about the other.
struct GettingAlbumsSection: View {
    @AppStorage(ConfirmCancel.storageKey) private var stored: String?
    @Environment(GetSettingsModel.self) private var getting
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability

    var body: some View {
        let settings = getting.settings
        let live = settings != nil && reachability.online
        Section {
            choice(GettingWords.modeTitle, GetMode.allCases, chosen: settings?.mode, live: live,
                   name: { (mode: GetMode) -> String in mode.label }) { (mode: GetMode) -> Void in
                getting.choose(GetChoice(mode: mode))
            }
            choice(GettingWords.floorTitle, QualityFloor.allCases, chosen: settings?.floor, live: live,
                   name: { (floor: QualityFloor) -> String in floor.label }) { (floor: QualityFloor) -> Void in
                getting.choose(GetChoice(floor: floor))
            }
            choice(GettingWords.formatTitle, FormatPreference.youOrder, chosen: settings?.format, live: live,
                   name: { (format: FormatPreference) -> String in format.label }) { (format: FormatPreference) -> Void in
                getting.choose(GetChoice(format: format))
            }
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

    /// One of the three: a menu of its choices, the chosen one at the row's right (GettingChoices.tsx's radio group, as
    /// a menu) - off, and showing none, until deadwax has answered; off, showing the choice in hand, while it can't be
    /// reached. A choice already chosen chooses nothing.
    private func choice<Choice: Hashable>(_ title: String, _ choices: [Choice], chosen: Choice?, live: Bool,
                                          name: @escaping (Choice) -> String,
                                          pick: @escaping (Choice) -> Void) -> some View {
        Picker(title, selection: Binding<Choice?>(get: { chosen }, set: { (now: Choice?) -> Void in
            guard live, let now, now != chosen else { return }
            pick(now)
        })) {
            // nothing known yet: the one value the row can show is none - never a default claimed as chosen
            if chosen == nil {
                Text(verbatim: "").tag(Choice?.none)
            }
            ForEach(choices, id: \.self) { (option: Choice) in
                Text(name(option)).tag(Choice?.some(option))
            }
        }
        .pickerStyle(.menu)
        .disabled(!live)
    }
}
