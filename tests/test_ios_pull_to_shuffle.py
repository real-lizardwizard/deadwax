"""
The iPhone app's pull to shuffle on an album's and a playlist's page (notes/ios.md "Pull to shuffle on an album's and a
playlist's page"; James: "also let's add pull to shuffle to the album and playlists pages").

Read from the Swift source, as the other ios tests read theirs: each page keeps one ShufflePull and puts the Library's
own modifier on its List - pulling only while it is the page on top (a playlist's not while Edit is open), and never
refreshing - with the Library's graphic over its hero, its foot at the hero's top, saying a page's words; what the pull
can do is Core's ShuffleCan.page, from the very songs the hero's Shuffle takes; the release is the hero's Shuffle, the
same call, nothing awaited first; the pull's old refresh is the bar •••'s Refresh (offline, a probe) and, on an album
with nothing drawn, Try again; the pull adds no gesture of its own; and the Library's pages pull as they did. Core's
rules (ShuffleCan.page, the page's words) are held by PullShuffleTests.swift.
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
ALBUM = APP / "Album" / "AlbumView.swift"
PLAYLIST = APP / "Playlists" / "PlaylistView.swift"
QUEUE_MENU = APP / "Player" / "QueueMenu.swift"
PULL_VIEW = APP / "Library" / "PullShuffleView.swift"
LIBRARY_PAGES = [
    APP / "Library" / "AlbumsScreen.swift",
    APP / "Library" / "ArtistsScreen.swift",
    APP / "Library" / "SongsScreen.swift",
    APP / "Playlists" / "PlaylistsScreen.swift",
]
# each page, and when it pulls
PAGES = [(ALBUM, "AlbumHero(", "on: shown"), (PLAYLIST, "PlaylistHero(", "on: shown && !editing")]


def code(path: Path) -> str:
    """A Swift file with its // comments blanked (none of these files' strings hold a //)."""
    return re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8"))


def partner(text: str, opening: int) -> int:
    """Where the brace at `opening` closes."""
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    raise AssertionError("unbalanced braces")


def block(text: str, opening: int) -> str:
    """What the brace at `opening` holds, up to its partner."""
    return text[opening + 1:partner(text, opening)]


def func(text: str, name: str) -> str:
    found = list(re.finditer(r"\bfunc\s+" + name + r"\b[^{]*\{", text))
    assert len(found) == 1, f"func {name} is declared {len(found)} times"
    return block(text, found[0].end() - 1)


def variable(text: str, name: str) -> str:
    found = list(re.finditer(r"\bvar\s+" + name + r"\b[^{]*\{", text))
    assert len(found) == 1, f"var {name} is declared {len(found)} times"
    return block(text, found[0].end() - 1)


def the_list(source: str) -> tuple[str, str]:
    """The page's List: what it holds, and the modifiers after it (to the next blank line)."""
    opening = source.index("{", source.index("List {"))
    closing = partner(source, opening)
    after = source[closing + 1:]
    return source[opening + 1:closing], after


def test_each_page_pulls_on_its_list_and_never_refreshes():
    for path, _, on in PAGES:
        source = code(path)
        assert source.count("@State private var pull = ShufflePull()") == 1, path.name
        # the pull is the shuffle's now, as the Library's is: no refresh on the List to fight it (nor the iPhone's
        # pull to refresh through Platform.swift's helper, since the Mac app's slice 1)
        assert ".refreshable" not in source and ".pullToRefresh" not in source, path.name
        assert source.count(".pullsToShuffle(") == 1, path.name
        _, after = the_list(source)
        # the List's own first two modifiers (a comment's line blanked)
        modifiers = [line.strip() for line in after.splitlines() if line.strip()][:2]
        assert modifiers == [
            ".listStyle(.plain)",
            f".pullsToShuffle(PullShuffling(state: pull, can: can, {on}, start: pulled))",
        ], path.name
    # the playlist knows it is the page on top, as the album page does
    playlist = code(PLAYLIST)
    assert "@State private var shown = false" in playlist
    assert ".onAppear { shown = true }" in playlist
    # the page's own (the hero's is the bar's title)
    disappear = block(playlist, playlist.index("{", playlist.index(".onDisappear {\n")))
    assert "shown = false" in disappear and "navigation.pageGone(route.id)" in disappear


def test_the_graphic_sits_over_the_hero_saying_a_pages_words():
    for path, hero, _ in PAGES:
        source = code(path)
        rows, _ = the_list(source)
        # the hero is the List's first row, and the graphic its overlay, before its separator is hidden
        assert rows.lstrip().startswith(hero), path.name
        overlay_at = rows.index(".overlay(alignment: .top) {")
        assert overlay_at < rows.index(".listRowSeparator(.hidden)"), path.name
        overlay = block(rows, rows.index("{", overlay_at))
        assert "PullShuffleGraphic(state: pull, can: can, of: .page)" in overlay, path.name
        assert ".fixedSize(horizontal: false, vertical: true)" in overlay, path.name
        # its foot at the hero's top: drawn from its bottom up into the room the pull opens
        assert ".alignmentGuide(.top) { (drawn: ViewDimensions) -> CGFloat in drawn[.bottom] }" in overlay, path.name
        assert source.count("PullShuffleGraphic(") == 1, path.name
    graphic = code(PULL_VIEW)
    assert "var of: PullShuffleOf = .library" in graphic
    assert "PullShuffleWords.line(phase, can: can, of: of)" in graphic


def test_what_it_can_do_is_from_the_songs_the_heros_shuffle_takes():
    album = code(ALBUM)
    body = album[album.index("var body: some View {"):]
    assert "let playable = self.playable" in body and "let can = pullCan(playable)" in body
    assert "playable: !playable.isEmpty," in body
    # phone-only exactly when the hero's Shuffle takes only the songs on this phone
    assert "guard !reachability.online || model.goneButHere else { return model.songs }" in variable(album, "playable")
    can = func(album, "pullCan")
    assert re.sub(r"\s+", " ", can).strip() == (
        "ShuffleCan.page(songs: model.songs.count, phoneOnly: !reachability.online || model.goneButHere, "
        "onPhone: playable.count)"
    )
    playlist = code(PLAYLIST)
    body = playlist[playlist.index("var body: some View {"):]
    assert "let playable = self.playable" in body and "let can = pullCan(playable)" in body
    assert "playable: !playable.isEmpty && !editing," in body
    assert "guard !reachability.online else { return model.songs }" in variable(playlist, "playable")
    can = func(playlist, "pullCan")
    assert re.sub(r"\s+", " ", can).strip() == (
        "ShuffleCan.page(songs: model.songs.count, phoneOnly: !reachability.online, onPhone: playable.count)"
    )


def test_the_release_is_the_heros_shuffle_in_the_lift():
    for path, _, _ in PAGES:
        source = code(path)
        # the hero's Shuffle, and the pull's release, are the one call
        assert "shuffle: { play(at: nil, shuffle: true) })" in source, path.name
        pulled = func(source, "pulled")
        assert pulled.strip().endswith("play(at: nil, shuffle: true)"), path.name
        # nothing awaited before the player is called (the gesture rule)
        assert "await" not in pulled and "Task" not in pulled, path.name
        # the songs on this phone gone since it armed: said, as the Library's pull says it, and nothing played
        said = pulled.index("player.say(PullShuffleWords.nothingHere)")
        assert pulled.index("if playable.isEmpty,") < said < pulled.index("return") < pulled.index("play(at: nil")
    # the player's own calls, unchanged: the album as the album, the playlist's songs each with its own album
    for path, call in ((ALBUM, "player.play(songs: songs, album: album, at: index, shuffle: shuffle)"),
                       (PLAYLIST, "player.play(playlist: songs, at: index, shuffle: shuffle)")):
        source = code(path)
        found = list(re.finditer(r"private func play\(at index: Int\?, shuffle: Bool = false\) \{", source))
        assert len(found) == 1, path.name
        assert call in block(source, found[0].end() - 1), path.name


def test_the_pull_adds_no_gesture_of_its_own():
    # it reads the List's own scroll (geometry and phase): Back's swipe, the ••• menus and Album info are untouched
    for path in (ALBUM, PLAYLIST, PULL_VIEW):
        source = code(path)
        for word in ("DragGesture", ".gesture(", "highPriorityGesture", "simultaneousGesture"):
            assert word not in source, f"{path.name} has {word}"
    view = code(PULL_VIEW)
    assert ".onScrollGeometryChange(for: Double.self)" in view and ".onScrollPhaseChange {" in view


def test_refresh_is_the_bar_menus_now():
    menu = code(QUEUE_MENU)
    request = block(menu, menu.index("{", menu.index("struct QueueMenuRequest {")))
    assert "var refresh: (@MainActor () -> Void)?" in request
    assert "if request.albumInfo != nil || editAlbum != nil || request.refresh != nil {" in menu
    item = menu.index("if let refresh = request.refresh {")
    # the last section's last item, the Library's word and symbol
    assert menu.index("if let editAlbum {") < item
    assert 'Button(LibrarySwitchWords.refresh, systemImage: "arrow.clockwise") {' in menu[item:item + 160]
    for path, model_call in (
        (ALBUM, "model.refresh(client: server.client, player: player, downloads: downloads)"),
        (PLAYLIST, "model.load(key: taskKey, client: server.client, playlists: playlists)"),
    ):
        source = code(path)
        assert "request.refresh = { refresh() }" in source, path.name
        refresh = func(source, "refresh")
        # offline, whether deadwax is back - as the pull did, and the Library's Refresh does
        assert refresh.index("guard reachability.online else {") < refresh.index("reachability.tryNow()")
        assert refresh.index("return") < refresh.index(model_call), path.name


def test_an_album_that_failed_with_nothing_drawn_has_try_again():
    album = code(ALBUM)
    failure = album.index("} else if let failure = model.failure {")
    branch = album[failure:album.index("} else if model.album == nil, let note {", failure)]
    assert "let retry = model.album == nil && !model.gone" in branch
    assert "ErrorNote(failure, gone: ErrorWords.albumGone, retry: retry)" in branch
    retry = block(branch, branch.index("{", branch.index("if retry {")))
    assert "Button(LibraryWords.tryAgain, action: refresh)" in retry


def test_the_librarys_pages_pull_as_they_did():
    for path in LIBRARY_PAGES:
        source = code(path)
        graphics = re.findall(r"PullShuffleGraphic\([^)]*\)", source)
        assert len(graphics) == 1, path.name
        # the library's words: no `of:`, the default
        assert "of:" not in graphics[0], path.name
        assert ".pullsToShuffle(" in source, path.name
