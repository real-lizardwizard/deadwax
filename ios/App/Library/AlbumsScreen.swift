import DeadwaxCore
import SwiftUI

/// One Albums screen (app/LibrarySection.tsx AlbumSection, D2): every album of a scope - yours, or the store's - in
/// the order chosen, under its headers, as tiles or rows; Find in place; the index down the edge; the New marks.
/// What it draws is Core's: the body by AlbumListBody, the order, headers, Find, count and index by Shelf.view
/// (through LibraryModel.drawn, made once per list, sort and Find), the words LibraryWords'.
///
/// The list is the model's, shared by every screen of the scope and kept on disk; this screen asks for it as it
/// shows and again whenever its generation moves (an Add or a Remove, the starred count, older than a minute), pull
/// to refresh asks now. A list asked again swaps in where the old one was - never emptied, the scroll kept.
/// Choosing a sort or typing into Find goes back to the top. Tapping the Library tab again scrolls the root to its
/// top; the store's screen is a page of the tab's own (AppRoute.albums), so the tab's tap pops it with whatever
/// album is over it. Nothing here plays (the gesture rule): a tile opens its album.
struct AlbumsScreen: View {
    let scope: AlbumScope
    /// The tab's root - All music's row above your albums, and the tab's tap scrolls it to the top.
    let root: Bool

    @Environment(LibraryModel.self) private var library
    @Environment(ServerModel.self) private var server
    @Environment(AppNavigation.self) private var navigation
    /// What is typed into Find - the screen's own: leaving it clears it.
    @State private var typed = ""
    /// On screen (not covered by a page pushed over it).
    @State private var shown = false

    /// The tiles' gap, and the screen's side margins.
    private static let gap: CGFloat = 14
    private static let edge: CGFloat = 16

    /// What the screen's ask is keyed on: a new person or a new generation is a new look.
    private struct LoadKey: Equatable {
        let person: Int
        let generation: Int
    }

    var body: some View {
        let personal = server.access.hasLibrary
        let drawn = library.drawn(scope, typed: typed)
        let failure = library.failures[scope]
        let finding = Find.finding(typed)
        let entries = drawn?.view.index ?? []
        let years = ShelfIndex.kind(library.sort) == .decades

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear
                        .frame(height: 0)
                        .id(ShelfAnchor.top)
                    if root && scope == .yours && personal && !finding {
                        AllMusicRow()
                    }
                    if let drawn, !drawn.view.countText.isEmpty {
                        Text(drawn.view.countText)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                    }
                    if drawn != nil, let failure {
                        RefreshProblemNote(failure: failure) { Task { await library.load(scope) } }
                    }
                    if drawn?.truncated == true {
                        Text(LibraryWords.truncated)
                            .font(.footnote)
                            .foregroundStyle(Palette.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content(drawn, failure: failure, personal: personal)
                }
                .padding(.leading, Self.edge)
                .padding(.trailing, entries.isEmpty ? Self.edge : ShelfIndexStrip.width(years: years) + 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(entries.isEmpty ? .automatic : .hidden)
            .overlay(alignment: .trailing) {
                if !entries.isEmpty {
                    ShelfIndexStrip(entries: entries, years: years) { group in
                        jump(proxy, to: .group(group))
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                }
            }
            .onChange(of: typed) { _, _ in jump(proxy, to: .top) }
            .onChange(of: library.sort) { _, _ in jump(proxy, to: .top) }
            .onChange(of: navigation.libraryScrollToTop) { _, _ in
                // the Library tab tapped at its root: the root list goes to its top
                guard shown, root else { return }
                jump(proxy, to: .top, animated: true)
            }
        }
        .navigationTitle(LibraryWords.title(scope, personal: personal))
        .searchable(text: $typed, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(LibraryWords.findPlaceholder))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                LibrarySortMenu()
                LibraryLayoutSwitch()
            }
        }
        .refreshable { await library.refresh(scope) }
        .task(id: LoadKey(person: server.person, generation: library.generations[scope] ?? 0)) {
            await library.load(scope)
        }
        .onAppear {
            shown = true
            library.refreshIfOld(scope)
        }
        .onDisappear { shown = false }
    }

    // MARK: the body (AlbumListBody)

    @ViewBuilder
    private func content(_ drawn: DrawnShelf?, failure: APIFailure?, personal: Bool) -> some View {
        switch AlbumListBody.of(scope, list: drawn?.albums, failed: failure != nil,
                                found: drawn?.view.found.count ?? 0, typed: typed) {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
                .accessibilityLabel(LibraryWords.loading)
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                if let failure { ErrorNote(failure, retry: true) }
                Button(LibraryWords.tryAgain) { Task { await library.load(scope) } }
            }
            .padding(.top, 8)
        case .emptyLibrary:
            EmptyLibraryNote()
        case .noAlbums:
            ShelfNote(LibraryWords.noAlbums)
        case .noMatch(let words):
            ShelfNote(words)
        case .albums:
            if let drawn { albums(drawn, personal: personal) }
        }
    }

    @ViewBuilder
    private func albums(_ drawn: DrawnShelf, personal: Bool) -> some View {
        let marks = library.marks
        switch library.layout {
        case .grid:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Self.gap, alignment: .top),
                                GridItem(.flexible(), spacing: Self.gap, alignment: .top)],
                      alignment: .leading, spacing: 18) {
                ForEach(drawn.groups) { group in
                    Section {
                        ForEach(group.albums) { album in
                            LibraryTile(album: album, isNew: personal && marks.isNew(album)) { open(album) }
                        }
                    } header: {
                        header(group)
                    }
                }
            }
        case .list:
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(drawn.groups) { group in
                    Section {
                        ForEach(group.albums) { album in
                            LibraryRow(album: album, isNew: personal && marks.isNew(album)) { open(album) }
                            Divider().padding(.leading, LibraryRow.textInset)
                        }
                    } header: {
                        header(group)
                    }
                }
            }
        }
    }

    /// A group's header, in the flow (never pinned: Shelf.tsx) - what the index scrolls to.
    @ViewBuilder
    private func header(_ group: DrawnGroup) -> some View {
        if let label = group.label {
            LibraryHeader(label: label)
                .id(ShelfAnchor.group(group.id))
        }
    }

    // MARK: doing

    /// A tile's tap: its album's page, the New mark gone (MyLibraryState.opened - deadwax told).
    private func open(_ album: IndexAlbum) {
        library.opened(album)
        navigation.open(.album(AlbumRoute(album)))
    }

    private func jump(_ proxy: ScrollViewProxy, to anchor: ShelfAnchor, animated: Bool = false) {
        if animated {
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
        } else {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { proxy.scrollTo(anchor, anchor: .top) }
        }
    }
}

/// What a screen scrolls to: its top, or a group's header by its place among the groups.
enum ShelfAnchor: Hashable {
    case top
    case group(Int)
}

/// The Albums screens' order (ALBUM_SORTS, the web's labels), one choice for both scopes, saved per device.
private struct LibrarySortMenu: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        @Bindable var library = library
        Menu {
            Picker(LibraryWords.sortLabel, selection: $library.sort) {
                ForEach(AlbumSort.allCases, id: \.self) { sort in
                    Text(sort.label).tag(sort)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(LibraryWords.sortLabel, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel(LibraryWords.sortLabel)
        .accessibilityValue(library.sort.label)
    }
}

/// Tiles or rows, per device (the phone's own: the web has only tiles).
private struct LibraryLayoutSwitch: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        Button {
            library.layout = library.layout == .grid ? .list : .grid
        } label: {
            Label(library.layout.switchLabel, systemImage: library.layout.switchSymbol)
        }
    }
}

/// With a library of your own, above your albums: All music's one row, All albums - the store's list, pushed
/// (app/LibraryHome.tsx's group, its one Phase 1 row).
private struct AllMusicRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LibraryWords.allMusic)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            StoreAlbumsLink {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack")
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text(LibraryWords.allAlbums)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
        }
    }
}

/// The way to the store's albums - All music's row, and an empty library's See All music: the store's Albums screen
/// pushed on the tab's path (AppRoute.albums), so the tab's tap pops it like any page.
private struct StoreAlbumsLink<Content: View>: View {
    @ViewBuilder let label: () -> Content

    var body: some View {
        NavigationLink(value: AppRoute.albums(.store)) {
            label()
        }
    }
}

/// Your library empty (EmptyLibrary): what is empty, how to fill it, and See All music.
private struct EmptyLibraryNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LibraryWords.emptyLibrary)
            Text(LibraryWords.emptyLibraryHow)
                .foregroundStyle(Palette.quiet)
            StoreAlbumsLink {
                Text(LibraryWords.seeAllMusic)
            }
            .buttonStyle(.bordered)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 8)
    }
}

/// A list that couldn't be asked again, drawn as it was (COULDNT_REFRESH), with the error and Try again.
private struct RefreshProblemNote: View {
    let failure: APIFailure
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LibraryWords.couldntRefresh)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            ErrorNote(failure, retry: true)
            Button(LibraryWords.tryAgain, action: retry)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// One line in place of the albums ("No albums yet.", "No albums match “…”.").
private struct ShelfNote: View {
    let words: String

    init(_ words: String) {
        self.words = words
    }

    var body: some View {
        Text(words)
            .foregroundStyle(Palette.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }
}
