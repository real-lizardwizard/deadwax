"""
The iPhone and Mac app's Last.fm on an artist's page, slice A1 (notes/ios.md "Last.fm, slice A1"; deadwax-plans/lastfm.md
3.1-3.3, 3.6-3.8; James, 24 Nov: the 10 most popular songs on the artist page, from Last.fm, all time).

Read from the Swift source, as the other ios tests read theirs: what the page draws of Last.fm's is LastfmPage.shown's
alone (the hero's line, Top Songs, the foot line for whoever runs deadwax) and what lies below Play waits on the arrival
(LastfmPage.Arrival: Top Songs where it belongs, or after the albums for an answer that came late); the Top Songs page
draws no foot line; a waiting row does nothing; a song you have plays in the tap, nothing awaited; a song you don't
have asks nothing offline, and its album opens only where it was tapped; each page lets that ask go. Core's rules
(LastfmPage, TopSongs, LastfmMatch, LastfmWords) are held by the Swift tests under DeadwaxKit.
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
ARTIST = APP / "Artist" / "ArtistView.swift"
SECTION = APP / "Artist" / "TopSongsSection.swift"
SCREEN = APP / "Artist" / "TopSongsScreen.swift"
OPENER = APP / "Models" / "TopSongOpener.swift"
PAGE_MODEL = APP / "Models" / "ArtistPageModel.swift"
ROUTES = APP / "Shared" / "Routes.swift"
NEW = [SECTION, SCREEN, OPENER]


def code(path: Path) -> str:
    """A Swift file with its // comments blanked (none of these files' strings hold a //)."""
    return re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8"))


def block(text: str, start: str) -> str:
    """The braces' body opened by the first `{` at or after `start`."""
    at = text.index(start)
    opening = text.index("{", at)
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1:index]
    raise AssertionError(f"{start} never closes")


def test_the_artist_page_draws_only_what_lastfm_page_shown_says():
    artist = code(ARTIST)
    # one judgement of what is drawn, with the foot line for whoever runs deadwax
    assert artist.count("LastfmPage.shown(") == 1
    assert ("online: online, answer: model.lastfm, seesDetail: server.access.seesDetail,\n"
            "                                      reserved: model.lineKept(page: taskKey))") in artist
    # the hero's line, there from the first frame whenever it can be drawn, blank until the answer says - (R1c) in
    # both tops, the Mac's under its centred name and the phone's beside its round picture
    hero = block(artist, "private func hero(")
    assert re.sub(r"\s+", " ", hero).strip() == ("if Platform.mac { macHero(managing, lastfm: lastfm) } else { "
                                                 "phoneHero(managing, lastfm: lastfm) }")
    for top in ("private func macHero(", "private func phoneHero("):
        drawn = re.sub(r"\s+", " ", block(artist, top))
        assert 'if lastfm.heroLine { Text(lastfm.listeners ?? " ")' in drawn, top
        assert ".accessibilityHidden(lastfm.listeners == nil)" in drawn, top
    # Top Songs only with Last.fm on and an answer to draw, below Play - waiting on the arrival
    body = block(artist, "var body: some View {")
    held = block(body, "if !arrival.holding {")
    assert "let top = lastfm.topSongs ? topRows(mine, online: online) : []" in held
    first, albums, after = (held.index("if !top.isEmpty && arrival.place == .inPlace { topSongs(top) }"),
                            held.index("albumsList("),
                            held.index("if !top.isEmpty && arrival.place != .inPlace { topSongs(top) }"))
    assert first < albums < after
    assert held.count("topSongs(top)") == 2
    assert body.index("plays(rows: mine") < body.index("if !arrival.holding {")
    # the foot line: LastfmPage.shown's, and its button to Server settings > Connections, where LASTFM_API_KEY is
    assert "if let foot = lastfm.foot { lastfmFoot(foot) }" in body
    foot = block(artist, "private func lastfmFoot(")
    assert "Button(LastfmWords.serverSettings) {\n                navigation.open(.serverSettingsGroup(ServerSettings.connectionsGroup))" in foot


def test_the_top_songs_page_is_the_artist_pages_own_rows():
    screen = code(SCREEN)
    # the artist page showing under it, else its own - and never the foot line
    assert "private var model: ArtistPageModel { artists.page(route.id) ?? own }" in screen
    assert "seesDetail: false)" in screen and "lastfmFoot" not in screen
    assert "let rows = shown.topSongs ? model.topRows(mine, online: online, downloads: downloads) : []" in screen
    # its own asks only with no artist page showing
    assert "private var alone: Bool { artists.page(route.id) == nil }" in screen
    assert screen.count("guard alone else { return }") == 2
    assert ".navigationTitle(LastfmWords.topSongs)" in screen
    # See All is the section's, past five, onto the page, at the readable width on the Mac
    section = code(SECTION)
    assert "if rows.count > TopSongs.shown {" in section and "navigation.open(.topSongs(route))" in section
    assert "ForEach(rows.prefix(TopSongs.shown))" in section
    assert "case .topSongs(let artist): TopSongsScreen(route: artist).readableOnMac()" in code(ROUTES)


def test_a_row_does_only_what_its_kind_allows():
    row = block(code(SECTION), "struct TopSongRow: View {")
    # waiting, and maybe yours (an album of theirs not in hand): drawn, the latter dimmed, and nothing to tap
    waiting = row[row.index("case .waiting:"):row.index("Divider()")]
    assert "Button" not in waiting and "onTapGesture" not in waiting
    assert "case .unknown:" in waiting and ".opacity(Palette.off)" in waiting[waiting.index("case .unknown:"):]
    # a song you have: played in the tap, nothing awaited first (the gesture rule)
    play = block(row, "private func play() {")
    assert "player.play(playlist: plan.songs, at: plan.at)" in play
    assert "await" not in play and "Task" not in play
    assert "guard let plan = TopSongs.play(all, from: row.rank, playable:" in play
    # offline only a song on the device plays
    assert "let playable = reachability.online || downloads.isHere(song.id)" in row
    assert ".disabled(!playable)" in row
    # a song you don't have: asks nothing offline, nor twice at once
    missing = block(row, "private var missing: some View {")
    assert ".disabled(!reachability.online || busy)" in missing
    assert "admin: server.access.seesDetail" in missing


def test_a_missing_songs_album_opens_only_where_it_was_tapped():
    opener = code(OPENER)
    ask = block(opener, "asking = Task {")
    guard = "guard navigation.tab == tab, navigation.shownStack == pages, !navigation.nowPlayingShown else { return }"
    assert ask.index(guard) < ask.index("navigation.open(.group(GroupRoute(album)))")
    assert "guard !Task.isCancelled, let self, self.opening == row else { return }" in ask
    # searched for by the title as keyed (TopSongs.searchQuery: LastfmMatch.strip), never Last.fm's raw one
    assert "client.searchSongs(TopSongs.searchQuery(title: top.title, artist: name))" in ask
    assert "fieldedQuery" not in opener
    # each page lets the ask go: another tab, Now Playing, leaving
    for path in (ARTIST, SCREEN):
        page = code(path)
        assert ".onChange(of: navigation.tab) { _, _ in model.opener.standDown() }" in page, path.name
        assert "if shown { model.opener.standDown() }" in page, path.name
        assert ".onDisappear { model.opener.standDown() }" in page, path.name


def test_lastfm_is_asked_unless_the_page_cannot_use_it():
    model = code(PAGE_MODEL)
    ask = block(model, "func askLastfm(")
    # nothing asked unless Last.fm is on and deadwax is in reach
    assert "guard state == .on, online, let client else {" in ask
    assert "client.lastfmArtist(mbid: ask.mbid, name: ask.name)" in ask
    # the hero's line kept once drawn for the page: noted as each ask begins and as each answer lands, by the rule
    # the page draws by
    assert ask.index("beginLastfm(page: page") < ask.index("keepLine(page: page, state: state, online: online)") \
        < ask.index("guard state == .on")
    assert "self.keepLine(page: page, state: state, online: true)" in ask
    keep = block(model, "private func keepLine(")
    assert "LastfmPage.drawsLine(state: LastfmPage.state(me: state, answer: lastfm), online: online, answer: lastfm)" in keep
    # a failure with nothing drawn is kept to be said (the Top Songs page's own)
    assert "self.lastfmFailure = failure" in ask
    # an album of theirs whose songs aren't in hand never makes a song "Not in your library" (TopSongs.library)
    rows = block(model, "func topRows(")
    assert "TopSongs.library(order: order, asks: asks, online: online)" in rows
    assert "downloads.keptAlbum(id)" in rows
    assert "TopSongs.rows(top, albums: albums, unknown: unknown)" in rows


def test_a_top_songs_page_on_its_own_says_its_troubles_and_tries_again():
    screen = code(SCREEN)
    body = block(screen, "var body: some View {")
    empty = block(body, "if rows.isEmpty {")
    # the artist's failure as their page says it, Last.fm's said the same way, each with Try again - then the spinner
    assert empty.index("if model.gone {") < empty.index("ErrorNote(failure, gone: ErrorWords.artistGone, retry: true)") \
        < empty.index("ErrorNote(failure, retry: true)") < empty.index("ProgressView()")
    assert "} else if alone, let failure = model.failure, model.answer == nil, online {" in empty
    assert "} else if alone, let failure = model.lastfmFailure, model.lastfm == nil, online {" in empty
    assert "Button(LibraryWords.tryAgain) { reload() }" in empty
    assert "Button(LibraryWords.tryAgain) { askLastfm(again: true) }" in empty
    # its own ask asks a failure the session keeps again at once
    assert "again: again,\n                      retryFailed: true)" in block(screen, "private func askLastfm(")
    # the session's answers timed by a clock that only goes forward
    artists = code(APP / "Models" / "ArtistsModel.swift")
    assert "private static var now: Double { Monotonic.seconds() * 1000 }" in artists and "Date()" not in artists


def test_the_new_views_say_only_their_words_and_draw_the_same_on_both():
    for path in NEW:
        text = path.read_text(encoding="utf-8")
        assert "#if" not in text, path.name
        assert "AnyView" not in text, path.name
    for path in (SECTION, SCREEN):
        # the words are LastfmWords' (and the rows' own lines): no literal of its own
        assert not re.search(r'(?:Text|Button|Label)\("', code(path)), path.name
