import DeadwaxCore
import SwiftUI

/// Requests' root (Phase 6, slice 1 - notes/ios-specs/phase6-get-requests.md 3.2-3.3; the web's app/Requests.tsx):
/// every download you asked for, under Downloading, Waiting, Needs attention and Done - each heading only with rows -
/// and Clear done in the bar. RequestsModel keeps the board and makes every request; this draws it and hands each tap
/// over.
///
/// - Until deadwax first answers, a spinner - never "Nothing requested yet", which would be a guess.
/// - A look deadwax answered with an error: the card saying the list can't be updated, the error in a listener's words
///   (its own under them for whoever runs deadwax), the rows below as the last answer had them.
/// - deadwax can't keep track of downloads: the card saying so - DB_PATH named for whoever runs deadwax.
/// - deadwax out of reach (question 4): "Requests show once deadwax is back." and none of the last answer; Clear done
///   waits.
/// - The ✕ cancels at once, or with Confirm before cancelling on (You > Getting albums, this phone's) asks in its card
///   first; one card asks at a time, and a second tap on its ✕ closes the question.
/// - A Done row's ▶ plays its album in the tap when its songs are in hand (question 6), else does what the row's tap
///   does: open the album, here, once the id bridge finds it.
/// - (Manual search, slice A1 - notes/ios.md "Manual search, slice A1"; James, 24 Nov: "A row at the top") Search
///   Soulseek…, the list's first row, above the headings and whatever stands in their place - only with Get albums, and
///   dimmed while deadwax is out of reach, as Clear done is. It opens the form (ManualSearchSheet). A manual search's
///   download reads "… · manual search" where the edition goes, and its Done row, once filed, says it was filed by its
///   own tags.
struct RequestsScreen: View {
    @Environment(RequestsModel.self) private var requests
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(PlayerModel.self) private var player

    /// The card asking "cancel it?", by its row's key - one at a time.
    @State private var asking: String?
    /// (Manual search) Search Soulseek's form is up.
    @State private var searching = false

    private static let top = "requests-top"
    /// (Manual search) The Search Soulseek… row's: the list's top whenever it is drawn.
    private static let searchRow = "requests-search"

    var body: some View {
        let board = requests.board
        ScrollViewReader { proxy in
            List {
                content(board)
            }
            .onChange(of: navigation.requestsScrollToTop) { _, _ in
                withAnimation { proxy.scrollTo(topRow(board), anchor: .top) }
            }
        }
        .navigationTitle(RequestWords.tab)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(RequestWords.clearDone) {
                    asking = nil
                    requests.clear()
                }
                .disabled(!board.clearable || !reachability.online)
            }
        }
        .appSheet(isPresented: $searching) {
            // a Get from its results: the sheet goes, onto Requests - already showing
            ManualSearchSheet { searching = false }
                .macSheet()
        }
    }

    /// What the list's top is: (manual search) Search Soulseek…, else a card above the rows, or the first row.
    private func topRow(_ board: RequestsView) -> String {
        if server.access.can(.request) { return Self.searchRow }
        guard reachability.online, requests.failure == nil, requests.trackingEnabled, !board.empty else { return Self.top }
        for section in RequestSection.allCases {
            if let first = board.rows(section).first { return first.key }
        }
        return Self.top
    }

    @ViewBuilder private func content(_ board: RequestsView) -> some View {
        if server.access.can(.request) {
            Section {
                manualSearch
                    .id(Self.searchRow)
            }
        }
        if !reachability.online {
            ShelfNote(RequestWords.offline)
                .id(Self.top)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        } else {
            let failed = requests.failure != nil
            if let failure = requests.failure {
                Section {
                    unreached(failure, empty: board.empty)
                        .id(Self.top)
                }
            }
            if !requests.trackingEnabled {
                Section {
                    untracked
                        .id(failed ? "requests-untracked" : Self.top)
                }
            } else if board.empty {
                if !requests.answered {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(AlbumPageLines.loading)
                        .id(Self.top)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if !failed {
                    Section {
                        nothingYet
                            .id(Self.top)
                    }
                }
            } else {
                ForEach(RequestSection.allCases, id: \.self) { (section: RequestSection) in
                    let rows = board.rows(section)
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { (row: RequestRow) in
                                card(section, row)
                                    .id(row.key)
                            }
                        } header: {
                            Text(RequestWords.title(section))
                                .font(Typeface.footnote)
                        }
                    }
                }
            }
        }
    }

    /// (Manual search) Search Soulseek…: the form, in a sheet. Dimmed while deadwax is out of reach.
    private var manualSearch: some View {
        Button {
            asking = nil
            searching = true
        } label: {
            Label(ManualSearch.row, systemImage: "plus.magnifyingglass")
        }
        .disabled(!reachability.online)
        .accessibilityLabel(ManualSearch.title)
    }

    /// A look that failed: what went wrong in a listener's words - no "try again", it asks again by itself, as the line
    /// under it says.
    private func unreached(_ failure: any Error, empty: Bool) -> some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, service: .downloads)
        return VStack(alignment: .leading, spacing: 6) {
            Text(RequestWords.unreached)
                .font(Typeface.headline)
                .fixedSize(horizontal: false, vertical: true)
            ErrorNote(text: line.text, detail: line.detail)
            Text(RequestWords.keepsAsking(empty: empty))
                .font(Typeface.callout)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var untracked: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RequestWords.untracked)
                .font(Typeface.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(server.access.seesDetail ? RequestWords.untrackedRuns : RequestWords.untrackedText)
                .font(Typeface.callout)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var nothingYet: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RequestWords.nothingYet)
                .font(Typeface.headline)
                .fixedSize(horizontal: false, vertical: true)
            // "tap Get" only to someone who can Get - anyone else's list holds what they join
            Text(RequestWords.emptyLine(gets: server.access.can(.request), device: Platform.device))
                .font(Typeface.callout)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func card(_ section: RequestSection, _ row: RequestRow) -> some View {
        switch section {
        case .downloading, .waiting:
            JobCardView(row: row, downloading: section == .downloading,
                        asking: asking == row.key && row.cancel == .ready,
                        onCancel: { tappedCancel(row) }, onKeep: { asking = nil }, onConfirm: { cancelNow(row) })
        case .attention:
            AttentionCardView(row: row, gets: server.access.can(.request), runs: server.access.seesDetail) { same in
                requests.retry(row, same: same)
            }
        case .done:
            DoneRowView(row: row, opening: requests.opening == row.key,
                        note: row.opens.flatMap { requests.notes[$0.key] },
                        filed: ManualSearch.doneLine(row, edits: server.access.can(.edit)), runs: server.access.seesDetail,
                        onOpen: { requests.open(row) }, onPlay: { play(row) })
        }
    }

    /// The ✕: cancel, or ask first; a second tap on the ✕ asking closes the question.
    private func tappedCancel(_ row: RequestRow) {
        guard row.jobId != nil, row.cancel == .ready else { return }
        if asking == row.key {
            asking = nil
        } else if ConfirmCancel.read(UserDefaults.standard.string(forKey: ConfirmCancel.storageKey)) {
            asking = row.key
        } else {
            cancelNow(row)
        }
    }

    private func cancelNow(_ row: RequestRow) {
        asking = nil
        requests.cancel(row)
    }

    /// A Done row's ▶: its album from the first song, in the tap with nothing awaited, when its songs are in hand -
    /// otherwise the row's tap.
    private func play(_ row: RequestRow) {
        if let plays = requests.plays(row) {
            player.play(songs: plays.songs, album: plays.album, at: 0)
        } else {
            requests.open(row)
        }
    }
}
