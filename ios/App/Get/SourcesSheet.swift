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

    /// (R7's review) A number no Get has had in this run of the app - the album page's Gets' `id`: a page's own count
    /// started again on every page, so a Get from another album's page could carry the number of the Get before it, and
    /// the Mac's dock (its tab keyed on the Get's number) could keep that Get's page, the new Get's search never begun.
    @MainActor static func numbered() -> Int {
        issued += 1
        return issued
    }

    @MainActor private static var issued = 0
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
/// - SEARCH AGAIN, under folders found - and in the bar, at the right of "Choose a source" (James, 2026-11-15: "search
///   again should be somewhere near the top as well", then "maybe on the right of 'choose a source'"), so a long list
///   needn't be scrolled to the end to try other words. The bar's opens the query to edit above the chips, where no
///   scroll can take it away; the list's, under it. A second tap closes it, the other's moves it; focused either way;
///   only an EDITED query is searched as typed. A search starting closes it again. The bar's is there only while
///   folders found are shown, in words up to the default text size and as a magnifying glass above it, where the words
///   would cut the title short.
/// - For VoiceOver, each outcome said in a line as it lands (Sources.announcement), so someone waiting hears the search
///   end.
/// - OUT OF REACH (slice 2's review, finding 1): while deadwax can't be reached, "Getting albums works once deadwax is
///   back." over whatever the sheet shows, the cards found before dimmed and every Get, Try again and Search off - a Get
///   would close onto a Requests that can't show it. Back, they are live again; a search that failed for want of deadwax
///   searches again by itself, and Search again is still in the bar and under the cards. A Get that couldn't be asked
///   at all keeps the sheet up, with why (`getFailure`).
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
///
/// - (Manual search, slice A1 - notes/ios.md "Manual search, slice A1") This is the PAGE, SourcesPage: the album page's
///   sheet is it in a NavigationStack of its own (SourcesSheet, below - exactly as it was), and Requests' Search
///   Soulseek pushes it from its form (ManualSearchSheet, `pushed`), where Back stands in Cancel's place and the search
///   goes as the page does (onDisappear; SheetGoing still when the whole sheet goes). For a manual search the chips
///   have no Complete albums only (no tracklist to judge by), nothing is picked (Sources.autoPick), and a server that
///   didn't echo the question (before deadwax 2.1.38, which would file it by the typed words) has every Get off, with
///   why above the cards (ManualSearch.tooOldLine) - said to VoiceOver with the outcome.
///
/// - (The redesign, slice R7 - notes/ios.md "The redesign, slice R7: Search, Get and Sources (2026-11-25)") As
///   iSources.dc.html draws it on the phone, flat: Close (where it said Cancel), the subtitle at the left, the chips a
///   strip of words (FilterStrip - each its own toggle, the pressed ones white over the accent's line), "Sort" with its
///   pop-up and how many were found, and the cards (SourceCardView) on the page's ground. On the Mac it is the dock's
///   Sources tab (MacSourcesTab, `kept`): the Get's own chips and sort, so they outlast its tab switched away from and
///   back, its search begun once and let go only as the Get ends (AppNavigation.endSources) - its Close the Get over and
///   the panel put away.
/// - (The panel review's R19 - notes/ios.md "The panel review, R19: Get, and old type left in redrawn pages
///   (2026-11-27)") In the Mac's dock there is no bar: the page starts under the folder tabs with the dock's own header
///   (DockHeader) - the subtitle, and Search again as a `.btn.sm`, no row while it holds neither - and its Close is the
///   dock's (Escape, or a click on the open tab, the panel put away: MacSourcesTab ends the Get then, as Close did).
///   The states (asking, nothing found, refused) are in the look's type on both devices, and the query's field the
///   look's well - square on the phone, `.in`'s corners on the Mac.
struct SourcesPage: View {
    let request: GetRequest
    /// Pushed from Search Soulseek's form: no Cancel - Back is there.
    let pushed: Bool
    /// (R7) The Mac's dock's Get's own chips and sort (MacSourcesGet): drawn in the dock, the page begins its search once
    /// and never lets it go itself. nil: a sheet's page, its chips its own.
    var kept: SourcesChoices? = nil
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
    /// The chips, the sort and whether one was tapped: the page's own, or the dock's Get's (`kept`).
    @State private var own = SourcesChoices()
    private var choices: SourcesChoices { kept ?? own }
    /// (R7) Drawn in the Mac's dock.
    private var docked: Bool { kept != nil }
    private var filters: SourceFilters {
        get { choices.filters }
        nonmutating set { choices.filters = newValue }
    }
    /// A chip was tapped since this Get began: the floor landing late doesn't re-make them then.
    private var touched: Bool {
        get { choices.touched }
        nonmutating set { choices.touched = newValue }
    }
    private var sort: CandidateSort {
        get { choices.sort }
        nonmutating set { choices.sort = newValue }
    }
    /// (R7's review) Sample rate ▾: the least a folder's worst file may be, in Hz - 0 for any.
    private var minSampleRate: Double {
        get { choices.minSampleRate }
        nonmutating set { choices.minSampleRate = newValue }
    }
    /// The chips and the sample-rate floor as the candidates' filters: what the cards, the best match and a pick go by.
    private var chosenFilters: CandidateFilters {
        SourcesLook.filters(filters, minSampleRate: minSampleRate)
    }
    /// Search again, opened from the bar (above the chips) or under folders found - one at a time, nil closed.
    @State private var again: AgainPlace?
    /// The bar's Search again in words up to the default text size, a magnifying glass above it.
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var againFocused: Bool
    /// A card's Get that couldn't be asked at all (no deadwax to ask): the sheet stays, saying so.
    @State private var getFailure: (any Error)?
    /// (Slice 3) The answer Add to my library added from (SourcesSearch.landed): its box says it's yours now.
    @State private var addedFrom: Int?

    private var floor: QualityFloor { settings.floorNow }
    private var online: Bool { reachability.online }

    var body: some View {
        VStack(spacing: 0) {
            if kept != nil, Platform.mac {
                // (R19) the dock's own header in the bar's place: the subtitle, and Search again at its right - (R19's
                // review) no row at all while it would hold neither
                if !request.subtitle.isEmpty || foundFolders {
                    dockHeader
                }
            } else if !request.subtitle.isEmpty {
                // iSources: .s.q, at the left, 2 above and 10 under
                Text(request.subtitle)
                    .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SourcesPageLook.side)
                    .padding(.top, SourcesPageLook.subtitleAbove)
                    .padding(.bottom, SourcesPageLook.subtitleBelow)
            }
            if again == .top && foundFolders {
                // the bar's Search again: the words to change above the chips, where no scroll takes them away
                queryForm(focus: true) {
                    EmptyView()
                }
                .padding(.horizontal, SourcesPageLook.side)
                .padding(.bottom, SourcesPageLook.subtitleBelow)
            }
            chips
            sortLine
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SourcesPageLook.cardGap) {
                    content
                }
                .padding(.horizontal, SourcesPageLook.side)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            if Platform.mac {
                // (R7's review) Get.dc.html's panel foot, while there are cards: what their speeds are
                if let shown = shownCards {
                    speedsFoot(shown)
                }
            }
        }
        .background(Platform.mac ? DWPalette.panel : DWPalette.page)
        // the sheet going for good - a swipe let go, not one pulled back: the search goes with it, there and then
        .background(SheetGoing { model.close() })
        .navigationTitle(SourcesWords.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // (manual search) pushed from Search Soulseek's form, Back is there in its place - (R19) and in the Mac's
            // dock no bar at all: its Close is the dock's own, Search again in its header
            if !pushed && !docked {
                ToolbarItem(placement: .cancellationAction) {
                    Button(SourcesLook.close) {
                        // the search let go in the tap, then the sheet closes
                        model.close()
                        dismiss()
                    }
                    // (the Mac app, slice 2) Escape is Close only with the search's words as searched: Close throws
                    // edited words away without asking
                    .escapeCloses(!model.edited)
                }
            }
            if foundFolders && !docked {
                // (James) at the right of the title, so a long list needn't be scrolled to its end to search again
                ToolbarItem(placement: .topBarTrailing) {
                    againInBar
                }
            }
        }
        // (R19) the dock's page starts under its folder tabs: the stack's bar hidden there
        .toolbar(docked ? .hidden : .automatic, for: .navigationBar)
        .onAppear {
            // (R7) the dock's page drawn again as its tab comes back: its Get as it was, never searched afresh
            guard !docked || model.search == nil else { return }
            // a Get: its chips the quality floor, the sort Best match, searched afresh
            filters = GetSettings.floorFilters(floor)
            begin(request.release)
        }
        // the backstop: however the sheet went (swiped away, a Get handing over), the search goes with it - (R7) never
        // the dock's, whose tab switched away comes back to it: its Get's end lets it go (AppNavigation.endSources)
        .onDisappear { if !docked { model.close() } }
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
            filters: { chosenFilters },
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

    /// The folders through the chips and the sample-rate floor, in the server's order (best match first).
    private func passing(_ answer: FindCandidatesAnswer?) -> [Candidate] {
        let chosen = chosenFilters
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
                                    notPicked: model.notPicked ?? tooOld(search), format: search.format)
    }

    /// (Manual search) A server that dropped the manual question's flag: why every Get is off, or nil.
    private func tooOld(_ search: SourcesSearch.Search) -> String? {
        ManualSearch.tooOldLine(search.release, search.answer, runs: server.access.seesDetail)
    }

    /// The store's box for an answer, as the web's sheet draws it: Join with Get albums, and once Add has added from
    /// this very answer, yours.
    private func storeBox(_ answer: FindCandidatesAnswer) -> StoreStatus? {
        let found = StoreLine.drawn(answer.store, floor: floor, joins: server.access.can(.request))
        guard let found, addedFrom == model.landed else { return found }
        return StoreLine.addedStatus(found)
    }

    // MARK: the chips

    /// The filters (iSources' .chips, Get.dc.html's small buttons): each its own toggle - a strip of words on the phone,
    /// the look's small buttons on the Mac, the pressed ones `.on`.
    private var chips: some View {
        FilterStrip(chips: GetSettings.chips(floor, filters, manual: request.release.manual)) { (key: SourceFilters.Key) in
            touched = true
            filters[key].toggle()
        }
        .accessibilityLabel(SourcesWords.chipsLabel)
    }

    /// "Sort" and its pop-up (Best match ▾), (R7's review) Sample rate ▾, and how many folders Soulseek gave - once it
    /// has answered with some, and how many of them the filters let through while they hide some ("3 of 14"). Where
    /// they don't fit one line, the count under the pop-ups; capped at xxxLarge, as the filters' strip is.
    private var sortLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: SourcesPageLook.sortGap) {
                sortChoices
                Spacer(minLength: SourcesPageLook.sortGap)
                if let found = foundCount {
                    Text(SourcesLook.found(found.all, shown: found.shown))
                        .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.extraSmall))
                        .foregroundStyle(DWPalette.t3)
                        .lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: SourcesPageLook.sortFold) {
                HStack(alignment: .firstTextBaseline, spacing: SourcesPageLook.sortGap) {
                    sortChoices
                }
                if let found = foundCount {
                    Text(SourcesLook.found(found.all, shown: found.shown))
                        .font(Platform.mac ? Typeface.Look.mono(.smallButton) : Typeface.Phone.mono(.extraSmall))
                        .foregroundStyle(DWPalette.t3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SourcesPageLook.side)
        .padding(.bottom, SourcesPageLook.subtitleBelow)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// "Sort", its pop-up, and Sample rate ▾ - each pop-up a menu of the very choices, said with what is chosen.
    @ViewBuilder private var sortChoices: some View {
        Text(SourcesLook.sort)
            .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
            .foregroundStyle(DWPalette.t2)
            .accessibilityHidden(true)
        DWPopUp(words: sort.label, size: .small) {
            Picker(SourcesWords.sortLabel, selection: Binding(get: { sort }, set: { (order: CandidateSort) in
                sort = order
            })) {
                ForEach(CandidateSort.allCases) { (order: CandidateSort) in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        }
        .fixedSize()
        .accessibilityLabel(SourcesWords.sortLabel)
        .accessibilityValue(sort.label)
        DWPopUp(words: SourcesLook.sampleRate(minSampleRate).chip, size: .small) {
            Picker(SourcesLook.sampleRateLabel, selection: Binding(get: { minSampleRate }, set: { (rate: Double) in
                minSampleRate = rate
            })) {
                ForEach(SourcesLook.sampleRates) { (floor: SourcesLook.SampleRate) in
                    Text(floor.label).tag(floor.value)
                }
            }
            .pickerStyle(.inline)
        }
        .fixedSize()
        .accessibilityLabel(SourcesLook.sampleRateLabel)
        .accessibilityValue(SourcesLook.sampleRate(minSampleRate).label)
    }

    /// How many folders Soulseek gave for the search shown, and how many of them pass the filters - nil while none has
    /// answered with any.
    private var foundCount: (all: Int, shown: Int)? {
        guard let search = model.search, !search.pending, let answer = search.answer, !answer.candidates.isEmpty,
              storeBox(answer) == nil else { return nil }
        return (answer.candidates.count, passing(answer).count)
    }

    /// The cards shown for the search shown - nil while there are none (searching, the store's box, none found or none
    /// through the filters).
    private var shownCards: [Candidate]? {
        guard let search = model.search, !search.pending, search.error == nil, let answer = search.answer,
              storeBox(answer) == nil else { return nil }
        let shown = passing(answer)
        return shown.isEmpty ? nil : shown
    }

    /// (R7's review) The Mac's foot under the cards (Get.dc.html's panel foot, 34 tall over the line): what their speeds
    /// are (SourcesLook.speeds).
    private func speedsFoot(_ shown: [Candidate]) -> some View {
        Text(SourcesLook.speeds(shown))
            .font(Typeface.Look.text(.smallButton))
            .foregroundStyle(DWPalette.t3)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(SourcesLook.speeds(shown))
            .padding(.horizontal, SourcesPageLook.footSide)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lookHeight(SourcesPageLook.foot)
            .overlay(alignment: .top) { DWRule(colour: DWPalette.line) }
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
                        .font(Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.row))
                        .foregroundStyle(DWPalette.text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Sources.searchTakes)
                        .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                        .foregroundStyle(DWPalette.t2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .accessibilityElement(children: .combine)
            } else if let error = search.error {
                VStack(spacing: 12) {
                    ErrorNote(error, service: .downloads, failed: ErrorWords.down[.downloads], retry: true)
                    Button(SourcesWords.tryAgain) { begin(search.release) }
                        .buttonStyle(DWButtonStyle())
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
                .opacity(online ? 1 : DWPalette.off)
        } else {
            StoreLineView(status: nil, notes: notes)
            if let notPicked = model.notPicked ?? model.search.flatMap({ tooOld($0) }) {
                // When I tap Get said pick, and nothing qualified: why, above the sources - (manual search) or why
                // every Get is off
                Text(notPicked)
                    .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
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
                            .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                            .foregroundStyle(DWPalette.t2)
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
                    if SourcesLook.pressed(filters, minSampleRate: minSampleRate) > 0 {
                        Button(SourcesWords.clearFilters) {
                            touched = true
                            filters = .none
                            minSampleRate = 0
                        }
                        .buttonStyle(DWButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                searchAgain
            } else {
                let gets = online && !ManualSearch.needsNewer(release, answer)
                ForEach(shown) { (candidate: Candidate) in
                    SourceCardView(candidate: candidate, best: Sources.key(candidate) == best, gets: gets) {
                        get(candidate, release: release, shown: shown)
                    }
                }
                Text(Sources.searchedLine(answer, shown: shown.count))
                    .font(Platform.mac ? Typeface.Look.text(.smallButton) : Typeface.Phone.text(.small))
                    .foregroundStyle(DWPalette.t2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                searchAgain
            }
        }
    }

    /// A card's Get, in the tap - or a pick, as its answer lands: the download asked for as the release this search was
    /// for, with the list as shown (a pick's, the list it tops) for the next peers - once per search - and the sheet
    /// handing over to Requests only once the request is out. Refused while deadwax is out of reach; one that couldn't
    /// be asked keeps the sheet, saying why. True once it is asked for.
    /// (Manual search) Never one a server too old to file it by its own tags would file by the typed words.
    @discardableResult
    private func get(_ candidate: Candidate, release: GetRelease, shown: [Candidate]) -> Bool {
        guard online, !ManualSearch.needsNewer(release, model.search?.answer), model.download() else { return false }
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
            .font(Platform.mac ? Typeface.Look.text(.field) : Typeface.Phone.text(.row))
            .foregroundStyle(DWPalette.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Where Search again's words to change open: from the bar, above the chips (`top`); under folders found (`bottom`).
    private enum AgainPlace { case top, bottom }

    /// Folders were found and are shown - the cards, or none passing the chips - so Search again is offered: in the bar,
    /// and under them. Not while searching, for an error, for the store's box, or when nothing was found (whose words to
    /// change are already shown).
    private var foundFolders: Bool {
        guard let search = model.search, !search.pending, search.error == nil, let answer = search.answer else {
            return false
        }
        return storeBox(answer) == nil && !answer.candidates.isEmpty
    }

    /// Search again opened at `place`, or closed if it was open there already.
    private func toggleAgain(_ place: AgainPlace) {
        again = again == place ? nil : place
    }

    /// "Search again" at the right of the title: in words up to the default text size - beside Cancel and "Choose a
    /// source" that fits a phone's bar - and above it a magnifying glass, where the words would cut the title short.
    private var againInBar: some View {
        Button { toggleAgain(.top) } label: {
            if typeSize > .large {
                Image(systemName: "magnifyingglass")
            } else {
                Text(SourcesWords.searchAgain)
            }
        }
        .accessibilityLabel(SourcesWords.searchAgain)
        .accessibilityValue(again == .top ? SourcesWords.expanded : SourcesWords.collapsed)
    }

    /// (R19) The Mac's dock's header, in the bar's place (Get.dc.html's panel has no bar): the subtitle at the left in
    /// `.s .q`, wrapping, and - while folders found are shown, as the bar's was - Search again at the right as a `.btn.sm`,
    /// lit (`.on`) while its words to change are open above the chips. One button, one toggle: the bar's own Search again
    /// isn't drawn in the dock.
    private var dockHeader: some View {
        DockHeader {
            if !request.subtitle.isEmpty {
                Text(request.subtitle)
                    .font(Typeface.Look.text(.smallButton))
                    .foregroundStyle(DWPalette.t2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            if foundFolders {
                Button(SourcesWords.searchAgain) { toggleAgain(.top) }
                    .buttonStyle(DWButtonStyle(kind: again == .top ? .on : .normal, size: .small))
                    .fixedSize()
                    .accessibilityValue(again == .top ? SourcesWords.expanded : SourcesWords.collapsed)
            }
        }
    }

    /// "Search again" under folders found: a disclosure - the query to edit opens under it, focused; a second tap closes
    /// it, and the bar's moves it up there.
    @ViewBuilder private var searchAgain: some View {
        Button(SourcesWords.searchAgain) { toggleAgain(.bottom) }
            .buttonStyle(DWButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityValue(again == .bottom ? SourcesWords.expanded : SourcesWords.collapsed)
        if again == .bottom {
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
                    .font(Platform.mac ? Typeface.Look.text(.chip) : Typeface.Phone.text(.extraSmall))
                    .foregroundStyle(DWPalette.label)
                    .accessibilityHidden(true)
                // (R19) the look's field: its well under it (`.in`) - square on the phone, a button's 4 on the Mac -
                // its edge the accent's while it has the cursor, and a tap on the well's target puts the cursor in it
                TextField(SourcesWords.searchFor, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Typeface.Look.text(.field))
                    .foregroundStyle(DWPalette.fieldText)
                    .focused($againFocused)
                    .focusEffectDisabled()
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        if online { requery() }
                    }
                    .padding(.horizontal, SourcesPageLook.fieldInside)
                    .lookHeight(DWLook.here.fieldHeight)
                    .background {
                        DWWell(focused: againFocused)
                            .contentShape(DWTarget(face: DWCorners.buttonShape))
                            .onTapGesture { againFocused = true }
                    }
                    .accessibilityLabel(SourcesWords.searchFor)
                    .task {
                        // focused once it is drawn: a focus asked before the field exists is lost
                        if focus { againFocused = true }
                    }
            }
            Button(SourcesWords.search, action: requery)
                .buttonStyle(DWButtonStyle())
                .disabled(!online)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, focus ? 0 : 40)
    }
}

/// Choose a source as the album page's Get opens it: SourcesPage in a sheet of its own - its Cancel, Search again in its
/// bar, a swipe down letting the search go - exactly as it was before the page was split out for Requests' Search
/// Soulseek (manual search, slice A1).
struct SourcesSheet: View {
    let request: GetRequest
    /// A download asked for: the sheet goes, and Requests shows.
    let onQueued: () -> Void

    var body: some View {
        NavigationStack {
            SourcesPage(request: request, pushed: false, onQueued: onQueued)
        }
    }
}

/// (R7) A Get's chips, its sort and whether a chip was tapped since it began - the page's own in a sheet, the dock's
/// Get's on the Mac (MacSourcesGet), so they outlast its tab switched away from and back.
@MainActor
@Observable
final class SourcesChoices {
    var filters = SourceFilters.none
    var touched = false
    var sort = CandidateSort.score
    /// (R7's review) Sample rate ▾'s floor, in Hz - 0 for any.
    var minSampleRate: Double = 0
}

/// (R7) The numbers iSources.dc.html draws (each line's `drawn:` comment says where).
enum SourcesPageLook {
    static let side: CGFloat = 16           // drawn: iSources subtitle padding-left
    static let subtitleAbove: CGFloat = 2   // drawn: iSources subtitle padding-top
    static let subtitleBelow: CGFloat = 10  // drawn: iSources subtitle padding-bottom
    static let sortGap: CGFloat = 8         // drawn: iSources sort line gap
    static let sortFold: CGFloat = 4        // own: the count folded under the pop-ups
    /// (R19) The query's field's words in from its well's edge.
    static let fieldInside: CGFloat = 8     // drawn: .in padding-left
    static let cardGap: CGFloat = 10        // drawn: iSources cards gap
    /// (R7's review) The Mac's foot under the cards: 34 tall, its words 12 in.
    static let foot: Double = 34            // drawn: Get panel foot height
    static let footSide: CGFloat = 12       // drawn: Get panel foot padding-left
}

/// (R7) The filters, each its own toggle (iSources' .chips, Get.dc.html's small buttons). On the phone a strip of words
/// with no face, as PhoneStrip draws a choice of parts - at 15 in the second colour, 22 apart over the strip's hairline,
/// a pressed one white and semibold over the accent's 2 pt line, as wide as its words - but any of them pressed at once,
/// each said as selected; scrolling sideways where they don't fit, a finger's target 44 round each. On the Mac the
/// look's small buttons, a pressed one `.on`, in a row that scrolls sideways where the dock is too narrow for them.
private struct FilterStrip: View {
    let chips: [GetSettings.Chip]
    let toggle: (SourceFilters.Key) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) {
                // (R7's review) room for each word's whole target inside the scroll view, which takes no touch
                // outside itself - PhoneStrip's way
                row
                    .padding(.vertical, reach)
            }
            // drawn as tall as its words again: the targets' reach laid over what is above and below it
            .padding(.vertical, -reach)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            if !Platform.mac { DWRule(colour: DWPalette.stripRule) }
        }
        .padding(.bottom, Platform.mac ? SourcesPageLook.subtitleBelow : CGFloat(PhoneLook.stripFoot))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var row: some View {
        if Platform.mac {
            HStack(spacing: 6) {
                ForEach(chips) { (chip: GetSettings.Chip) in
                    Button(chip.label) { toggle(chip.key) }
                        .buttonStyle(DWButtonStyle(kind: chip.on ? .on : .normal, size: .small))
                        .fixedSize()
                        .accessibilityAddTraits(chip.on ? .isSelected : [])
                }
            }
            .padding(.horizontal, SourcesPageLook.side)
        } else {
            HStack(spacing: 0) {
                ForEach(chips) { (chip: GetSettings.Chip) in
                    word(chip)
                }
            }
            .padding(.horizontal, CGFloat(PhoneLook.stripSide) - room)
        }
    }

    /// A button's room either side of its words: half the strip's gap.
    private var room: CGFloat {
        CGFloat(PhoneLook.stripGap) / 2
    }

    /// (R7's review) How far a word's target reaches above and below its 40 pt height (PhoneStrip's `reach`): 2 on the
    /// phone, none on the Mac.
    private var reach: CGFloat {
        CGFloat(DWLook.here.reach(PhoneLook.strip))
    }

    private func word(_ chip: GetSettings.Chip) -> some View {
        Button {
            toggle(chip.key)
        } label: {
            Text(chip.label)
                .font(Typeface.Phone.text(.strip).weight(chip.on ? .semibold : .medium))
                .foregroundStyle(chip.on ? DWPalette.text : DWPalette.t2)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, CGFloat(PhoneLook.stripPadding))
                .lookHeight(PhoneLook.strip)
                .overlay(alignment: .bottom) {
                    if chip.on {
                        Rectangle()
                            .fill(DWPalette.acc)
                            .frame(height: CGFloat(DWFlat.chosenLine))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, room)
                .frame(minWidth: CGFloat(DWLook.here.target))
                .contentShape(DWTarget(face: DWCorners.buttonShape))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chip.on ? .isSelected : [])
    }
}
