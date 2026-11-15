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
    /// (Slice 3's review, finding 4) This Get's search - held by the Get rather than the sheet, so the page that opened
    /// it can let it go the moment the sheet is let go (GroupView's binding), not once the slide away has ended.
    let search: SourcesSearch
}

/// Choose a source (Phase 6, slices 2 and 3 - phase6-get-requests.md 2.10, 2.11, 3.5; the web's app/Sources.tsx as a
/// phone's sheet):
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
/// - SEARCH AGAIN, under folders found - and above the cards, at the right of how many there are (James, 2026-11-15:
///   "search again should be somewhere near the top as well"), so a long list needn't be scrolled to the end to try
///   other words: the query to edit opens under the one tapped (a second tap closes it, the other's tap moves it
///   there), focused; only an EDITED query is searched as typed. A search starting closes it again.
/// - For VoiceOver, each outcome said in a line as it lands (Sources.announcement), so someone waiting hears the search
///   end.
/// - OUT OF REACH (slice 2's review, finding 1): while deadwax can't be reached, "Getting albums works once deadwax is
///   back." over whatever the sheet shows, the cards found before dimmed and every Get, Try again and Search off - a Get
///   would close onto a Requests that can't show it. Back, they are live again; a search that failed for want of deadwax
///   searches again by itself, and Search again is still above and under the cards. A Get that couldn't be asked at all keeps
///   the sheet up, with why (`getFailure`).
///
/// - (Slice 3) PICK THE BEST SOURCE FOR ME (You > Getting albums' When I tap Get): on a fresh Get - or Try again - the
///   best match through the chips as they are when the answer lands, at 75 or more, is downloaded as a card's Get is,
///   and the sheet hands over to Requests; never for a pressing held or on its way, nor one that can't be judged. When
///   nothing qualifies, why is said above the sources ("… - choose a source yourself."), and to VoiceOver with the
///   outcome. A search again by hand never picks.
/// - (Slice 3) JOIN AND ADD, in the store's box: a download somebody else asked for, judged against your floor, is
///   yours to join (Join this download - with Get albums, which the sheet needs to open at all), and joining hands over
///   to Requests as a Get does, only while the sheet still shows the Get that joined; a pressing the store holds that
///   isn't yours is added from the box (Add to my library), which then says it's yours (StoreLine.addedStatus) and
///   tells your library and Search's marks.
///
/// - (Slice 3's review) OUT OF REACH, Join and Add are off with every Get (the box dimmed with the rest), and a pick
///   landing then isn't asked for - said above the sources (Sources.notPickedOffline), and never made later by itself:
///   the choice is yours once deadwax is back. Coming back, a search that failed for want of deadwax runs again as the
///   very search it was (SourcesSearch.rerunOnReturn): a search again by hand stays one, with your words and chips,
///   and never picks.
/// - (Slice 3's review) A JOIN OR AN ADD DEADWAX DIDN'T ANSWER IN TIME may have gone through: the store is asked
///   again, and one that landed is taken as done (Requests for a Join, yours for an Add); otherwise the box says it may
///   have (StoreWords.joinUnanswered, addUnanswered), never that it was refused, and Requests is asked again either way.
///
/// Cancel - or the sheet swiped away - lets the search go (its request cancelled, which stops it in slskd too): as the
/// sheet starts going for good (SheetGoing, and GroupView's binding), not once it has slid away, so nothing is picked
/// or asked for once you have let it go.
struct SourcesSheet: View {
    let request: GetRequest
    /// A download asked for: the sheet goes, and Requests shows.
    let onQueued: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerModel.self) private var server
    @Environment(RequestsModel.self) private var requests
    @Environment(GetSettingsModel.self) private var settings
    @Environment(Reachability.self) private var reachability
    @Environment(LibraryModel.self) private var library
    @Environment(SearchModel.self) private var searchModel
    /// This Get's search (GetRequest.search).
    private var model: SourcesSearch { request.search }
    @State private var filters = SourceFilters.none
    /// A chip was tapped since this Get began: the floor landing late doesn't re-make them then.
    @State private var touched = false
    @State private var sort = CandidateSort.score
    /// Search again, opened above the cards or under folders found - one at a time, nil closed.
    @State private var again: AgainPlace?
    @FocusState private var againFocused: Bool
    /// A card's Get that couldn't be asked at all (no deadwax to ask): the sheet stays, saying so.
    @State private var getFailure: (any Error)?
    /// (Slice 3) The answer Add to my library added from (SourcesSearch.landed): its box says it's yours now.
    @State private var addedFrom: Int?

    private var floor: QualityFloor { settings.floorNow }
    private var online: Bool { reachability.online }

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
            // the sheet going for good - a swipe let go, not one pulled back: the search goes with it, there and then
            .background(SheetGoing { model.close() })
            .navigationTitle(SourcesWords.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SourcesWords.cancel) {
                        // the search let go in the tap, then the sheet closes
                        model.close()
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
        .onDisappear { model.close() }
        // the floor's word landing after the sheet opened: the chips become it, unless already tapped
        .onChange(of: settings.settings?.floor) { _, landed in
            guard let landed, !touched else { return }
            filters = GetSettings.floorFilters(landed)
        }
        .onChange(of: announcement) { _, said in
            if !said.isEmpty { Notice.announce(said) }
        }
        // deadwax back: a search that failed for want of it searches again; a Get that couldn't be asked may be again
        .onChange(of: online) { _, back in
            guard back else {
                // why every Get just went dim, for VoiceOver
                Notice.announce(StoreLine.offline)
                return
            }
            getFailure = nil
            //? nothing answered it, or not in time (this fires only on deadwax coming back): the very search again - a
            //? search again by hand stays one, its words and the chips as you left them, and never picks
            model.rerunOnReturn(client: server.client, settings: settings)
        }
    }

    // MARK: the search

    /// A search for `release` - a Get, or Try again - Search again closed, and a pick made as it lands when When I tap
    /// Get says so: the chips read then, the pick downloaded as a card's Get is.
    private func begin(_ release: GetRelease) {
        again = nil
        let picking = SourcesSearch.Picking(
            filters: { GetSettings.candidateFilters(filters) },
            picked: { (candidate: Candidate, release: GetRelease, list: [Candidate]) -> SourcesSearch.Sent in
                // out of reach as it landed: not asked - and not later either (the search says why)
                guard online else { return .offline }
                return get(candidate, release: release, shown: list) ? .asked : .notAsked
            })
        model.start(release, client: server.client, settings: settings, picking: picking)
    }

    /// The same pressing again, with the field's query where it was edited - Search again closed as it starts.
    private func requery() {
        again = nil
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
        let status = search.answer.flatMap { storeBox($0) }
        return Sources.announcement(pending: search.pending, release: search.release, error: error, status: status,
                                    answer: search.answer, shown: passing(search.answer).count,
                                    notPicked: model.notPicked, format: search.format)
    }

    /// The store's box for an answer, as the web's sheet draws it: Join with Get albums, and once Add has added from
    /// this very answer, yours.
    private func storeBox(_ answer: FindCandidatesAnswer) -> StoreStatus? {
        let found = StoreLine.drawn(answer.store, floor: floor, joins: server.access.can(.request))
        guard let found, addedFrom == model.landed else { return found }
        return StoreLine.addedStatus(found)
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
            if !online {
                // what's below is from before; nothing here can be asked of deadwax until it's back
                ShelfNote(StoreLine.offline)
                    .padding(.bottom, 4)
            } else if let getFailure {
                ErrorNote(getFailure, service: .downloads, failed: RequestWords.enqueueBroke)
                    .padding(.bottom, 4)
            }
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
                        .disabled(!online)
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
        if let status = storeBox(answer) {
            // held whole, or downloading whole: where the sources would be - the server searched nothing
            // out of reach, Join and Add are off as every Get is
            StoreLineView(status: status, notes: notes,
                          onJoin: server.access.can(.request) ? { (jobId: Int) in try await join(jobId, release: release) } : nil,
                          onAdd: { try await add(release) }, live: online)
                .opacity(online ? 1 : Palette.dimmed)
        } else {
            StoreLineView(status: nil, notes: notes)
            if let notPicked = model.notPicked {
                // When I tap Get said pick, and nothing qualified: why, above the sources
                Text(notPicked)
                    .font(Typeface.footnote)
                    .foregroundStyle(Palette.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                searchAgain(.bottom)
            } else {
                // above the cards as well as under them: a long list needn't be scrolled to its end to try other words
                searchAgain(.top, shown: shown.count)
                ForEach(shown) { (candidate: Candidate) in
                    SourceCardView(candidate: candidate, best: Sources.key(candidate) == best, gets: online) {
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
                searchAgain(.bottom)
            }
        }
    }

    /// A card's Get, in the tap - or a pick, as its answer lands: the download asked for as the release this search was
    /// for, with the list as shown (a pick's, the list it tops) for the next peers - once per search - and the sheet
    /// handing over to Requests only once the request is out. Refused while deadwax is out of reach; one that couldn't
    /// be asked keeps the sheet, saying why. True once it is asked for.
    @discardableResult
    private func get(_ candidate: Candidate, release: GetRelease, shown: [Candidate]) -> Bool {
        guard online, model.download() else { return false }
        guard requests.enqueue(EnqueueBody(candidate: candidate, release: release, shown: shown)) else {
            model.downloadAgain()
            getFailure = URLError(.notConnectedToInternet)
            return false
        }
        getFailure = nil
        onQueued()
        return true
    }

    /// (Slice 3) Join this download, from the box: once deadwax has it, Requests - as a Get - but only while the sheet
    /// still shows the Get that joined (GroupView's hand-over checks it is still up). (Slice 3's review) One deadwax
    /// didn't answer in time is looked for in the store: landed, it is a Join done; else it throws, for the box to say
    /// it may have joined.
    private func join(_ jobId: Int, release: GetRelease) async throws {
        do {
            try await requests.join(jobId)
        } catch {
            guard RequestOverlays.unanswered(error),
                  await landed(release, { (answer: StoreStateAnswer) in StoreLine.joinLanded(jobId, in: answer) })
            else { throw error }
        }
        onQueued()
    }

    /// (Slice 3) Add to my library, from the box: the pressing this search is for, as a Get would download it. Once
    /// deadwax has it, the box says it's yours (if it still shows the answer added from), and your library and Search's
    /// marks are told. (Slice 3's review) One deadwax didn't answer in time is looked for in the store, as a Join is.
    private func add(_ release: GetRelease) async throws {
        let from = model.landed
        do {
            try await library.add(release)
        } catch {
            guard RequestOverlays.unanswered(error) else { throw error }
            // it may have landed: Search's marks asked again either way (LibraryModel.add tells your library)
            searchModel.refreshOwned()
            guard await landed(release, { (answer: StoreStateAnswer) in StoreLine.addLanded(in: answer) }) else {
                throw error
            }
            addedFrom = from
            return
        }
        addedFrom = from
        searchModel.refreshOwned()
    }

    /// (Slice 3's review, finding 3) A Join or an Add deadwax didn't answer in time: the store asked again whether it
    /// landed anyway - false when it can't be asked, or doesn't say so.
    private func landed(_ release: GetRelease, _ said: (StoreStateAnswer) -> Bool) async -> Bool {
        guard let client = server.client, let answer = try? await client.storeState(release) else { return false }
        return said(answer)
    }

    private func stateText(_ words: String) -> some View {
        Text(words)
            .font(Typeface.subheadline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Where Search again sits: above the cards, and under folders found.
    private enum AgainPlace { case top, bottom }

    /// "Search again", above the cards and under folders found: a disclosure - the query to edit opens under the one
    /// tapped, focused; a second tap closes it, and the other's tap moves it there. Above the cards it sits at the right
    /// of how many are shown (the count and the button one above the other when the text is too large for both on a
    /// line), a 44-point target either way.
    @ViewBuilder private func searchAgain(_ place: AgainPlace, shown: Int = 0) -> some View {
        if place == .top {
            againAbove(shown: shown)
        } else {
            Button(SourcesWords.searchAgain) { toggleAgain(.bottom) }
                .font(Typeface.body)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityValue(again == .bottom ? SourcesWords.expanded : SourcesWords.collapsed)
        }
        if again == place {
            queryForm(focus: true) {
                EmptyView()
            }
        }
    }

    /// Search again opened under `place`, or closed if it was open there already.
    private func toggleAgain(_ place: AgainPlace) {
        again = again == place ? nil : place
    }

    /// Search again above the cards: "12 sources" at the left, Search again at the right.
    private func againAbove(shown: Int) -> some View {
        let button = Button { toggleAgain(.top) } label: {
            Text(SourcesWords.searchAgain)
                .font(Typeface.subheadline)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityValue(again == .top ? SourcesWords.expanded : SourcesWords.collapsed)
        let count = Text(Sources.sourcesCount(shown))
            .font(Typeface.footnote)
            .foregroundStyle(Palette.text2)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                count
                Spacer(minLength: 0)
                button.fixedSize()
            }
            VStack(alignment: .leading, spacing: 0) {
                count.fixedSize(horizontal: false, vertical: true)
                button
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
                    .onSubmit {
                        if online { requery() }
                    }
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
                .disabled(!online)
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
