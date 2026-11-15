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
struct RequestsScreen: View {
    @Environment(RequestsModel.self) private var requests
    @Environment(ServerModel.self) private var server
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @Environment(PlayerModel.self) private var player

    /// The card asking "cancel it?", by its row's key - one at a time.
    @State private var asking: String?

    private static let top = "requests-top"

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
    }

    /// What the list's top is: a card above the rows, or the first row.
    private func topRow(_ board: RequestsView) -> String {
        guard reachability.online, requests.failure == nil, requests.trackingEnabled, !board.empty else { return Self.top }
        for section in RequestSection.allCases {
            if let first = board.rows(section).first { return first.key }
        }
        return Self.top
    }

    @ViewBuilder private func content(_ board: RequestsView) -> some View {
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
                        }
                    }
                }
            }
        }
    }

    /// A look that failed: what went wrong in a listener's words - no "try again", it asks again by itself, as the line
    /// under it says.
    private func unreached(_ failure: any Error, empty: Bool) -> some View {
        let line = ErrorWords.of(failure, admin: server.access.seesDetail, service: .downloads)
        return VStack(alignment: .leading, spacing: 6) {
            Text(RequestWords.unreached)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            ErrorNote(text: line.text, detail: line.detail)
            Text(RequestWords.keepsAsking(empty: empty))
                .font(.callout)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var untracked: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RequestWords.untracked)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(server.access.seesDetail ? RequestWords.untrackedRuns : RequestWords.untrackedText)
                .font(.callout)
                .foregroundStyle(Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var nothingYet: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(RequestWords.nothingYet)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            // "tap Get" only to someone who can Get - anyone else's list holds what they join
            Text(RequestWords.emptyLine(gets: server.access.can(.request)))
                .font(.callout)
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
                        note: row.release.flatMap { requests.notes[$0] }, runs: server.access.seesDetail,
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
