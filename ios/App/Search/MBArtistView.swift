import DeadwaxCore
import SwiftUI

/// A MusicBrainz artist's page (Phase 5, slice 3 - question 9; the web's ArtistPage.tsx for an artist known by
/// MusicBrainz, with artistPage.ts' rules in Core's MBArtistPage): pushed on the tab's stack from Search's MusicBrainz
/// artists and the album you don't have's credit. Top to bottom: their picture's place (round, empty - MusicBrainz's
/// artists have no picture route) and their name; who they are in a line ("Group · Bristol · since 1991"), its line held
/// while it loads; Albums with Studio only (on unless turned off for them); their albums, newest first, each its cover,
/// title and "1994 · in your library" with the tick for one held (yours, with a library of your own) - a row opens the
/// album you don't have, or yours through the id bridge. "Loading their albums…" while they come, their trouble with Try
/// again, "Showing their first 500 albums." at the cut, and why there are none.
///
/// No description, no links and no Play (question 9: Phase 7's). Nothing is asked, and none of their albums drawn, while
/// deadwax can't be reached: "Their albums show once deadwax is back." - the page asks once it is.
struct MBArtistView: View {
    let route: MBArtistRoute

    @Environment(ServerModel.self) private var server
    @Environment(SearchModel.self) private var search
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @State private var model: MBArtistModel
    /// The hero's name has scrolled away: the bar shows it.
    @State private var nameInBar = false

    private static let pictureSide: CGFloat = 200
    private static let edge: CGFloat = 16

    init(route: MBArtistRoute) {
        self.route = route
        _model = State(initialValue: MBArtistModel(route: route))
    }

    /// Who and which artist: a new person asks everything again.
    private var taskKey: String { "\(server.person)|\(route.mbid)" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                hero
                    .onAppear { nameInBar = false }
                    .onDisappear { nameInBar = true }
                albumsHead
                albums
            }
            .padding(.horizontal, Self.edge)
            .padding(.bottom, 24)
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(route.name)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(nameInBar ? 1 : 0)
                    .accessibilityHidden(!nameInBar)
            }
        }
        .task(id: taskKey) {
            search.refreshOwned()
            await model.load(client: server.client, online: reachability.online)
        }
        .onChange(of: reachability.online) { _, online in
            // back: what couldn't be asked is asked now
            guard online else { return }
            Task { await model.load(client: server.client, online: true) }
        }
        .onChange(of: navigation.tab) { _, _ in model.standDown() }
        .onChange(of: navigation.nowPlayingShown) { _, shown in
            if shown { model.standDown() }
        }
        .onDisappear { model.standDown() }
    }

    // MARK: the hero

    private var hero: some View {
        let about: String = MBArtistPage.factsLine(model.facts)
        return VStack(spacing: 0) {
            ArtistPicture(id: nil, side: Self.pictureSide, pixels: CoverSize.hero)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 8)
                .accessibilityHidden(true)
            Text(route.name)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            // who they are: its line held while it loads, so nothing below moves as it lands
            Text(about.isEmpty ? " " : about)
                .font(.subheadline)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 4)
                .accessibilityHidden(about.isEmpty)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: their albums

    private var albumsHead: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ArtistWords.albumsHeading)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if reachability.online {
                Toggle(MBArtistPage.studioOnly, isOn: Binding(get: { model.studioOnly }, set: { (_: Bool) -> Void in
                    model.toggleStudio(client: server.client, online: reachability.online)
                }))
                .toggleStyle(.button)
                .font(.footnote)
            }
        }
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    @ViewBuilder private var albums: some View {
        let personal = server.access.hasLibrary
        if !reachability.online {
            ShelfNote(MBArtistPage.offline)
        } else {
            if let shown = model.shown ?? model.albums {
                let rows = MBArtistPage.rows(shown.groups, index: search.ownedIndex)
                ForEach(rows) { (row: MBArtistPage.Row) in
                    MBArtistAlbumRow(row: row, line: MBArtistPage.line(row, personal: personal),
                                     marked: MBArtistPage.marked(row, personal: personal),
                                     busy: model.opening == row.key) {
                        model.open(row, client: server.client, online: reachability.online, navigation: navigation)
                    }
                }
                foot(shown: model.shown, rows: rows)
            } else {
                foot(shown: nil, rows: [])
            }
        }
    }

    /// Under the rows: asking, the trouble with Try again, the cut, or why there are none.
    @ViewBuilder private func foot(shown: MBArtistModel.Albums?, rows: [MBArtistPage.Row]) -> some View {
        if model.asking || (shown == nil && model.trouble == nil) {
            HStack(spacing: 10) {
                ProgressView()
                Text(MBArtistPage.loading)
                    .foregroundStyle(Palette.quiet)
            }
            .accessibilityElement(children: .combine)
            .padding(.top, 12)
        } else if let trouble = model.trouble {
            VStack(alignment: .leading, spacing: 10) {
                switch trouble {
                case .unavailable:
                    ErrorNote(text: MBArtistPage.away)
                case .failed(let error):
                    ErrorNote(error, retry: true)
                }
                Button(SearchWords.tryAgain) {
                    if reachability.online {
                        Task { await model.browse(client: server.client, online: true, again: true) }
                    } else {
                        reachability.tryNow()
                    }
                }
                .disabled(reachability.probing)
            }
            .padding(.top, 12)
        } else if shown?.truncated == true {
            ShelfNote(MBArtistPage.truncated)
        } else if rows.isEmpty {
            ShelfNote(MBArtistPage.none(studio: model.studioOnly))
        }
    }
}

/// One of their albums (ArtistPage.tsx's row, MusicBrainz's): its cover through deadwax's relay, its title, and "1994 ·
/// in your library · 2 pressings" with the tick for one marked (MBArtistPage.marked). Read as one; busy while the id
/// bridge is asked.
private struct MBArtistAlbumRow: View {
    let row: MBArtistPage.Row
    let line: String
    let marked: Bool
    let busy: Bool
    let open: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 12) {
                    ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: row.group.id),
                                 size: ArchiveCoverSize.row)
                        .frame(width: LibraryRow.cover, height: LibraryRow.cover)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .foregroundStyle(.primary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if marked {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Palette.held)
                                    .accessibilityHidden(true)
                            }
                            Text(line.isEmpty ? " " : line)
                                .font(.subheadline)
                                .foregroundStyle(Palette.quiet)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    if busy {
                        ProgressView()
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityElement(children: .combine)
            .accessibilityLabel([row.title, line].filter { (part: String) -> Bool in !part.isEmpty }.joined(separator: ", "))
            .accessibilityValue(busy ? SearchWords.loading : "")
            Divider().padding(.leading, LibraryRow.textInset)
        }
    }
}
