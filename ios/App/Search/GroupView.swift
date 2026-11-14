import DeadwaxCore
import SwiftUI

/// The album you don't have (Phase 5, slice 2 - phase5-search.md 3.6; the web's ReleaseGroupPage.tsx on a phone, with
/// pressings.ts' rules in Core's Pressings and GroupPage): a MusicBrainz album's page, pushed on the tab's stack from
/// Search. Top to bottom: its cover (the chosen pressing's front, else the album's - through deadwax's relay), its title,
/// its credit (a link to the library's artist when exactly one answers to its sole credited artist - question 19), the
/// meta line ("1994 · Album · not in your library", or a dashed "maybe in your library"); the pressing picker (a sheet,
/// question 17) and the chosen pressing's facts; where Phase 6's Get will go, nothing; the maybe said in words; then
/// the chosen pressing's tracklist - the summary against the usual tracklist, each track with what differs marked, and
/// what it leaves out. Loading… while the pressings come, their trouble with Try again, "There are no pressings of this
/// album to get." for none.
///
/// Drawn at once from the album Search showed (`route.preview`); what it says of the library is from `/library/owned`,
/// asked again as the page shows. No description and no links out (question 20). Nothing is asked while deadwax can't be
/// reached: a list kept from earlier in the session is drawn, else the page says it loads once deadwax is back.
struct GroupView: View {
    let route: GroupRoute

    @Environment(ServerModel.self) private var server
    @Environment(SearchModel.self) private var search
    @Environment(ArtistsModel.self) private var artists
    @Environment(Reachability.self) private var reachability
    @Environment(AppNavigation.self) private var navigation
    @State private var model: GroupPageModel
    @State private var picking = false
    /// The hero's title has scrolled away: the bar shows it.
    @State private var titleInBar = false

    private static let edge: CGFloat = 16

    init(route: GroupRoute) {
        self.route = route
        _model = State(initialValue: GroupPageModel(route: route))
    }

    /// The page as drawn from what is in hand (Core's GroupPage).
    private var page: GroupPage {
        GroupPage(id: route.id, answer: model.answer, preview: route.preview, index: search.ownedIndex,
                  picked: model.picked, personal: server.access.hasLibrary, editors: false)
    }

    var body: some View {
        let page = self.page
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                hero(page)
                    .onAppear { titleInBar = false }
                    .onDisappear { titleInBar = true }
                actions(page)
                below(page)
            }
            .padding(.horizontal, Self.edge)
            .padding(.bottom, 24)
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(page.title)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(titleInBar ? 1 : 0)
                    .accessibilityHidden(!titleInBar)
            }
        }
        .sheet(isPresented: $picking) {
            if let view = page.view {
                PressingPickerSheet(view: view) { (id: String) -> Void in
                    // the default chosen again is the default: nothing kept of it
                    model.picked = id == view.defaultId ? nil : id
                }
            }
        }
        .task(id: server.person) {
            search.refreshOwned()
            await model.load(client: server.client, online: reachability.online)
        }
        .onChange(of: reachability.online) { _, online in
            // back: what couldn't be asked is asked now
            guard online, model.answer == nil else { return }
            reload()
        }
    }

    private func reload() {
        Task { await model.load(client: server.client, online: reachability.online) }
    }

    // MARK: the hero

    private func hero(_ page: GroupPage) -> some View {
        VStack(spacing: 0) {
            ArchiveCover(addresses: ArchiveCoverID.addresses(release: page.chosenId, group: route.id),
                         size: ArchiveCoverSize.hero)
                .frame(maxWidth: AlbumHero.coverSide)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .padding(.top, 8)

            Text(page.title)
                .font(page.title.count > 60 ? .title3.bold() : .title2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)

            if !page.artist.isEmpty {
                artistLine(page)
                    .padding(.top, 2)
            }

            metaLine(page)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    /// The credit: the library's artist's page when exactly one answers to the album's sole credited artist, else words.
    @ViewBuilder private func artistLine(_ page: GroupPage) -> some View {
        if let artist = libraryArtist(page) {
            Button {
                navigation.open(.artist(ArtistRoute(artist)))
            } label: {
                Text(page.artist)
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .buttonStyle(.plain)
        } else {
            Text(page.artist)
                .font(.title3)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    /// The library's artist for the album's sole credit (the group's, else the chosen pressing's) - ReleaseGroupPage's
    /// `artistLink`, on the phone a library artist only: a MusicBrainz artist's page is slice 3's.
    private func libraryArtist(_ page: GroupPage) -> Artist? {
        let releases = model.answer?.releases ?? []
        let credited = route.preview ?? releases.first(where: { (release: PageRelease) -> Bool in release.releaseGroup != nil })?.releaseGroup
        let chosen = releases.first { (release: PageRelease) -> Bool in release.id == page.chosenId }
        let credit = (credited?.artistCredit ?? []).isEmpty ? chosen?.artistCredit : credited?.artistCredit
        guard let sole = Credits.sole(credit), let list = artists.list else { return nil }
        return SearchAlbums.libraryArtist(list, mbid: sole.mbid, index: search.ownedIndex, name: sole.name)
    }

    /// "1994 · Album · not in your library" - or its first parts and a dashed "maybe in your library". Its line held
    /// while it is empty, so nothing below moves as it fills.
    @ViewBuilder private func metaLine(_ page: GroupPage) -> some View {
        if page.maybe.isEmpty {
            Text(page.meta.isEmpty ? " " : page.meta)
                .font(.footnote)
                .foregroundStyle(Palette.quiet)
                .multilineTextAlignment(.center)
                .accessibilityHidden(page.meta.isEmpty)
        } else {
            HStack(spacing: 6) {
                if !page.meta.isEmpty {
                    Text(page.meta + " \u{00B7}")
                }
                Text(page.maybe)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(Palette.quiet, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .font(.footnote)
            .foregroundStyle(Palette.quiet)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: the pressing, and Get's place

    /// Where the album page has Play and Shuffle: the pressing picker and its facts, then where Phase 6's Get will go
    /// (nothing, in slice 2), then the maybe in words.
    @ViewBuilder private func actions(_ page: GroupPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let view = page.view {
                Button {
                    picking = true
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Pressings.picker)
                                .font(.caption)
                                .foregroundStyle(Palette.quiet)
                            Text(view.chosen?.label ?? "")
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.quiet)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 1, opacity: 0.06)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(Pressings.picker), \(view.chosen?.label ?? "")")
                .accessibilityHint(view.chosen?.facts ?? "")
                // the chosen pressing's facts, two lines held whatever it says, so another chosen moves nothing under it
                Text(page.facts.isEmpty ? " " : page.facts)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(2, reservesSpace: true)
                    .accessibilityHidden(true)
            }
            // Phase 6's Get the album goes here
            if !page.maybeNote.isEmpty {
                Text(page.maybeNote)
                    .font(.footnote)
                    .foregroundStyle(Palette.quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 18)
    }

    // MARK: the tracklist

    @ViewBuilder private func below(_ page: GroupPage) -> some View {
        if let trouble = model.trouble {
            troubleNote(trouble)
        } else if model.answer == nil {
            if reachability.online {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(Pressings.loading)
                        .foregroundStyle(Palette.quiet)
                }
                .accessibilityElement(children: .combine)
                .padding(.top, 18)
            } else {
                ShelfNote(Pressings.offline)
                    .padding(.top, 10)
            }
        } else if (model.answer?.releases ?? []).isEmpty {
            ShelfNote(Pressings.none)
                .padding(.top, 10)
        } else {
            tracklist(page)
        }
    }

    private func troubleNote(_ trouble: GroupPageModel.Trouble) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch trouble {
            case .unavailable:
                ErrorNote(text: Pressings.trouble)
            case .failed(let error):
                ErrorNote(error, gone: Pressings.gone, retry: true)
            case .notAnAlbum:
                ErrorNote(text: Pressings.notAnAlbum)
            }
            if trouble.asksAgain {
                Button(Pressings.tryAgain) {
                    if reachability.online { reload() } else { reachability.tryNow() }
                }
                .disabled(reachability.probing)
            }
        }
        .padding(.top, 18)
    }

    @ViewBuilder private func tracklist(_ page: GroupPage) -> some View {
        Text(Pressings.tracklist)
            .font(.title3.weight(.semibold))
            .padding(.top, 22)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
        if let summary = page.summary, !summary.text.isEmpty {
            Text(summary.text)
                .font(.footnote)
                .foregroundStyle(summary.differs ? Palette.amber : Palette.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
        }
        ForEach(page.tracks) { (track: PressingTrack) in
            if let heading = track.heading {
                Text(heading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.quiet)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            PressedTrackRow(number: track.number, title: track.title, length: track.length, mark: track.mark)
        }
        if !page.missing.isEmpty {
            Text(Pressings.notOnThisPressing)
                .font(.headline)
                .padding(.top, 20)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(page.missing.indices, id: \.self) { (at: Int) in
                PressedTrackRow(number: "\u{2013}", title: page.missing[at].title, length: page.missing[at].length,
                                mark: nil, left: true)
            }
        }
    }
}

/// One track of a pressing's tracklist (ReleaseGroupPage.tsx's `app-rg-track`): its number, its title with what marks
/// it under it ("Only on this pressing"), the mark's chip ("Bonus"), its length. Read as one.
private struct PressedTrackRow: View {
    let number: String
    let title: String
    let length: String
    let mark: PressingTrack.Mark?
    var left = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.quiet)
                    .frame(minWidth: 22, alignment: .trailing)
                    .accessibilityHidden(left)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(left ? Palette.quiet : .primary)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                    if let mark {
                        Text(mark.note)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                }
                Spacer(minLength: 8)
                if let mark {
                    Text(mark.chip)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Palette.amber)
                        .background(Capsule().fill(Palette.amberFill))
                        .overlay(Capsule().strokeBorder(Palette.amberEdge))
                }
                Text(length)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.quiet)
            }
            .padding(.vertical, 8)
            Divider()
        }
        .accessibilityElement(children: .combine)
    }
}
