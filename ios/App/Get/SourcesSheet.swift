import DeadwaxCore
import SwiftUI

/// A Get: what it downloads, and what the sheet's heading says it is for (Sources.tsx `GetRequest`) - a new number for
/// every Get, so the same album got twice searches twice.
struct GetRequest: Identifiable {
    let id: Int
    /// The release a download files as (GetRelease.build - releasePayload.ts).
    let release: GetRelease
    /// "Third · CD · 2008 · GB · Island".
    let subtitle: String
}

/// Choose a source (Phase 6, slice 2 - phase6-get-requests.md 2.10, 3.5; the web's app/Sources.tsx as a phone's sheet):
/// the sheet Get the album opens. Soulseek is searched for the pressing the Get was for (SourcesSearch), and each folder
/// found is a card (SourceCardView); a card's Get asks for the download in the tap - its row up in Requests from that
/// moment - and the sheet goes, Requests showing at its root.
///
/// - THE CHIPS: Lossless, 24-bit, Starts now, Complete albums only (and 320 kbps, only with that floor or pressed), and
///   the sort - in a row that scrolls sideways. They start as your quality floor (You > Getting albums, on deadwax),
///   re-made from it when its word lands after the sheet opened, unless you have tapped one since; the sort at Best
///   match.
/// - THE BEST MATCH - the highest score through the chips - has the edge and the one primary Get, wherever the sort
///   puts it.
/// - THE STATES: asking ("Looking for “Third” by Portishead…", "This takes a few seconds."); slskd unable to search, in a
///   listener's words, with Try again; the store's answer - held whole or downloading whole stands where the cards would
///   be (the server searched nothing), a part held, a part downloading and other pressings are notes above them;
///   nothing found (or nothing lossless, with Lossless only named), with the query to edit and Search; folders found
///   and none passing the chips, with Clear filters; and the cards, with what was searched under them.
/// - SEARCH AGAIN, under folders found: the query to edit opens under it (a second tap closes it), focused; only an
///   EDITED query is searched as typed. A search starting closes it again.
/// - For VoiceOver, each outcome said in a line as it lands (Sources.announcement), so someone waiting hears the search
///   end.
///
/// Cancel - or the sheet swiped away - lets the search go (its request cancelled, which stops it in slskd too). Not in
/// slice 2: Join, Add to my library and Pick the best source for me (slice 3) - the store's box says neither "Join it"
/// nor "add it" (StoreLine.drawn), and every Get shows the sources, whatever When I tap Get says.
struct SourcesSheet: View {
    let request: GetRequest
    /// A download asked for: the sheet goes, and Requests shows.
    let onQueued: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerModel.self) private var server
    @Environment(RequestsModel.self) private var requests
    @Environment(GetSettingsModel.self) private var settings
    @State private var model = SourcesSearch()
    @State private var filters = SourceFilters.none
    /// A chip was tapped since this Get began: the floor landing late doesn't re-make them then.
    @State private var touched = false
    @State private var sort = CandidateSort.score
    /// Search again, opened under folders found.
    @State private var again = false
    @FocusState private var againFocused: Bool

    private var floor: QualityFloor { settings.floorNow }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if !request.subtitle.isEmpty {
                    Text(request.subtitle)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                }
                chips
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        content
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.top, 4)
            .navigationTitle(SourcesWords.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SourcesWords.cancel) {
                        // the search let go in the tap, then the sheet closes
                        model.stop()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // a Get: its chips the quality floor, the sort Best match, searched afresh
            filters = GetSettings.floorFilters(floor)
            begin(request.release)
        }
        // the backstop: however the sheet went (swiped away, a Get handing over), the search goes with it
        .onDisappear { model.stop() }
        // the floor's word landing after the sheet opened: the chips become it, unless already tapped
        .onChange(of: settings.settings?.floor) { _, landed in
            guard let landed, !touched else { return }
            filters = GetSettings.floorFilters(landed)
        }
        .onChange(of: announcement) { _, said in
            if !said.isEmpty { Notice.announce(said) }
        }
    }

    // MARK: the search

    /// A search for `release` - a Get, or Try again - Search again closed.
    private func begin(_ release: GetRelease) {
        again = false
        model.start(release, client: server.client, settings: settings)
    }

    /// The same pressing again, with the field's query where it was edited - Search again closed as it starts.
    private func requery() {
        again = false
        againFocused = false
        model.requery(client: server.client, settings: settings)
    }

    /// The folders through the chips, in the server's order (best match first).
    private func passing(_ answer: FindCandidatesAnswer?) -> [Candidate] {
        let chosen = GetSettings.candidateFilters(filters)
        return (answer?.candidates ?? []).filter { Sources.passes($0, chosen) }
    }

    /// What the sheet says to VoiceOver as each outcome lands.
    private var announcement: String {
        guard let search = model.search else { return "" }
        let error = search.error.map { (error: any Error) -> String in
            ErrorWords.of(error, admin: server.access.seesDetail, service: .downloads,
                          failed: ErrorWords.down[.downloads], retry: true).said
        }
        let status = search.answer.flatMap { StoreLine.drawn($0.store, floor: floor) }
        return Sources.announcement(pending: search.pending, release: search.release, error: error, status: status,
                                    answer: search.answer, shown: passing(search.answer).count, format: search.format)
    }

    // MARK: the chips

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GetSettings.chips(floor, filters)) { (chip: GetSettings.Chip) in
                    Button(chip.label) {
                        touched = true
                        filters[chip.key].toggle()
                    }
                    .buttonStyle(ChipFace(on: chip.on))
                    .accessibilityAddTraits(chip.on ? .isSelected : [])
                }
                Menu {
                    Picker(SourcesWords.sortLabel, selection: $sort) {
                        ForEach(CandidateSort.allCases) { (order: CandidateSort) in
                            Text(order.label).tag(order)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(sort.label)
                        Image(systemName: "chevron.down")
                            .font(Typeface.symbol(.caption2).weight(.semibold))
                            .accessibilityHidden(true)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(ChipFace(on: false))
                .accessibilityLabel(SourcesWords.sortLabel)
                .accessibilityValue(sort.label)
            }
            .padding(.horizontal, 16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SourcesWords.chipsLabel)
    }

    // MARK: what the list shows

    @ViewBuilder private var content: some View {
        if let search = model.search {
            if search.pending {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(Sources.searchingLine(search.release))
                        .font(Typeface.subheadline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Sources.searchTakes)
                        .font(Typeface.footnote)
                        .foregroundStyle(Palette.text2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .accessibilityElement(children: .combine)
            } else if let error = search.error {
                VStack(spacing: 12) {
                    ErrorNote(error, service: .downloads, failed: ErrorWords.down[.downloads], retry: true)
                    Button(SourcesWords.tryAgain) { begin(search.release) }
                        .buttonStyle(SecondaryPill())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if let answer = search.answer {
                found(answer, release: search.release, format: search.format)
            }
        }
    }

    @ViewBuilder private func found(_ answer: FindCandidatesAnswer, release: GetRelease,
                                    format: FormatPreference?) -> some View {
        let notes = StoreLine.notes(answer.store)
        if let status = StoreLine.drawn(answer.store, floor: floor) {
            // held whole, or downloading whole: where the sources would be - the server searched nothing
            StoreLineView(status: status, notes: notes)
        } else {
            StoreLineView(status: nil, notes: notes)
            let through = self.passing(answer)
            let shown = Sources.sorted(through, sort)
            let best = Sources.best(through)
            if answer.candidates.isEmpty {
                if Sources.nothingLossless(answer, format) {
                    // Lossless only, and Soulseek answered: nothing lossless, and the setting that left the rest out
                    // named - the query still there to edit, a lossless copy may be filed under other words
                    queryForm {
                        stateText(Sources.nothingLosslessLine(answer))
                        Text(Sources.nothingLosslessNote)
                            .font(Typeface.footnote)
                            .foregroundStyle(Palette.text2)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    queryForm {
                        stateText(Sources.nothingFoundLine(answer))
                    }
                }
            } else if shown.isEmpty {
                VStack(spacing: 12) {
                    stateText(Sources.noneMatchLine(answer.candidates.count))
                    if GetSettings.pressedCount(filters) > 0 {
                        Button(SourcesWords.clearFilters) {
                            touched = true
                            filters = .none
                        }
                        .buttonStyle(SecondaryPill())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                searchAgain
            } else {
                ForEach(shown) { (candidate: Candidate) in
                    SourceCardView(candidate: candidate, best: Sources.key(candidate) == best) {
                        get(candidate, release: release, shown: shown)
                    }
                }
                Text(Sources.searchedLine(answer, shown: shown.count))
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                searchAgain
            }
        }
    }

    /// A card's Get, in the tap: the download asked for as the release this search was for, with the list as shown for
    /// the next peers - once per search - and the sheet handing over to Requests.
    private func get(_ candidate: Candidate, release: GetRelease, shown: [Candidate]) {
        guard model.download() else { return }
        requests.enqueue(EnqueueBody(candidate: candidate, release: release, shown: shown))
        onQueued()
    }

    private func stateText(_ words: String) -> some View {
        Text(words)
            .font(Typeface.subheadline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Search again" under folders found: a disclosure - the query to edit opens under it, focused, and a second tap
    /// closes it.
    @ViewBuilder private var searchAgain: some View {
        Button(SourcesWords.searchAgain) { again.toggle() }
            .font(Typeface.body)
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityValue(again ? SourcesWords.expanded : SourcesWords.collapsed)
        if again {
            queryForm(focus: true) {
                EmptyView()
            }
        }
    }

    /// The query to edit and search Soulseek with again: the field holds what was searched, and only an edited query
    /// is searched as typed. The keyboard's Search searches too.
    private func queryForm<Said: View>(focus: Bool = false, @ViewBuilder said: () -> Said) -> some View {
        @Bindable var model = model
        return VStack(spacing: 12) {
            said()
            VStack(alignment: .leading, spacing: 6) {
                Text(SourcesWords.searchFor)
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.label)
                    .accessibilityHidden(true)
                TextField(SourcesWords.searchFor, text: $model.query)
                    .focused($againFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit(requery)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Palette.well, in: Corners.controlShape)
                    .overlay(Corners.controlShape.strokeBorder(Palette.border))
                    .accessibilityLabel(SourcesWords.searchFor)
                    .task {
                        // focused once it is drawn: a focus asked before the field exists is lost
                        if focus { againFocused = true }
                    }
            }
            Button(SourcesWords.search, action: requery)
                .buttonStyle(SecondaryPill())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, focus ? 0 : 40)
    }
}

/// A filter chip, and the sort's (app.css .app-chip): the secondary face, 30 points tall in a 44-point target - pressed,
/// --dw-toggled-bg under --dw-accent-text in semibold, its edge --dw-toggled-border.
struct ChipFace: ButtonStyle {
    let on: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChipFaceBody(configuration: configuration, on: on)
    }
}

private struct ChipFaceBody: View {
    let configuration: ButtonStyleConfiguration
    let on: Bool

    private static let height: CGFloat = 30
    private static let target: CGFloat = 44

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(on ? Typeface.footnote.weight(.semibold) : Typeface.footnote)
            .foregroundStyle(on ? Palette.accentText : Palette.onSecondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: Self.height)
            .background {
                if on {
                    Corners.controlShape.fill(Palette.toggledFill)
                } else {
                    Corners.controlShape.fill(pressed ? Palette.secondaryFillPressed : Palette.secondaryFill)
                }
            }
            .overlay(Corners.controlShape.strokeBorder(on ? Palette.toggledEdge : Palette.secondaryEdge))
            .frame(minHeight: Self.target)
            .contentShape(Rectangle())
    }
}
