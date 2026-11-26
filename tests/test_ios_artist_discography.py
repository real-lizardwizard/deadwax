"""
The iPhone app's library artist page lists their albums you don't have (notes/ios.md "The artist's albums you don't
have"; James: "also on the artists page I'd like to also see albums I don't have yet").

Which albums, in what order and under which words is DeadwaxCore's ArtistJoin, held to the web's lib/artistPage.ts by
ArtistJoinTests and the `joined` and `mbids` vectors. What only the view decides is read here from the Swift source:
Play and Shuffle take your albums alone; offline nothing of MusicBrainz's is drawn, said or asked; a row of theirs is
the MusicBrainz artist page's own, opened by that page's model (its id bridge, let go as the page stops showing); and
MusicBrainz's trouble is said once, under the rows, in a listener's words.
"""

import re
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / "ios" / "App"
VIEW = APP / "Artist" / "ArtistView.swift"
MODEL = APP / "Models" / "ArtistPageModel.swift"
MB_VIEW = APP / "Search" / "MBArtistView.swift"


def code(path: Path) -> str:
    """A Swift file with its // and /// comments blanked."""
    return re.sub(r"//[^\n]*", "", path.read_text(encoding="utf-8"))


def block(text: str, opening: int) -> str:
    """What the brace at `opening` holds, up to its partner."""
    depth = 0
    for index in range(opening, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[opening + 1:index]
    raise AssertionError("unbalanced braces")


def function(text: str, signature: str) -> str:
    start = text.index(signature)
    return block(text, text.index("{", start))


def test_play_and_shuffle_take_your_albums_alone():
    view = code(VIEW)
    body = function(view, "var body: some View")
    # your rows as they were, for Play and Shuffle and the page's empty states; the joined rows only for the list
    assert "let mine = ArtistPage.rows(albums)" in body
    assert "plays(rows: mine, online: online, personal: personal)" in body
    assert "albumsList(rows, albums: albums, online: online, personal: personal)" in body
    assert "model.rows(albums: albums, groups: theirGroups(online: online)" in body
    plays = function(view, "private func plays(rows: [ArtistPage.Row]")
    assert "ArtistPage.playOrder(rows)" in plays
    assert "ArtistJoin" not in plays
    # the albums whose songs are asked are Navidrome's, as before
    model = code(MODEL)
    assert "ArtistPage.playOrder(ArtistPage.rows(answer?.album ?? []))" in function(model, "private func askAlbums(")


def test_offline_nothing_of_musicbrainzs_is_drawn_said_or_asked():
    view = code(VIEW)
    groups = function(view, "private func theirGroups(online: Bool)")
    assert "ArtistJoin.drawsTheirs(online: online, indexKnown: search.ownedIndex != nil, waited: ownedWaited)" in groups
    listed = function(view, "private func albumsList(")
    assert "let theirs = online ? model.discography : nil" in listed
    # the foot - MusicBrainz's every word - only with theirs, so never offline
    assert re.search(r"if let theirs \{\s*theirFoot\(theirs,", listed)
    # the model asks only online, and through the MusicBrainz page's own model (no route of its own)
    model = code(MODEL)
    asking = function(model, "func theirAlbums(mbid: String?")
    assert "guard online, let client, let discography, !discography.asking, discography.shown == nil" in asking
    assert "discography.browse(client: client, online: true" in asking
    assert "client.discography" not in model


def test_a_row_of_theirs_is_opened_by_the_musicbrainz_pages_model():
    view = code(VIEW)
    listed = function(view, "private func albumsList(")
    assert "ForEach(rows) { (row: ArtistJoin.Row) in" in listed
    assert "case .yours(let mine):" in listed and "ArtistAlbumRow(row: mine, line: ArtistPage.line(mine" in listed
    assert "case .theirs(let other):" in listed
    # (R6) the page's own flat row, the MusicBrainz page's words and its model's open - Get only where nobody holds it
    assert "ArtistTheirRow(row: other, line: MBArtistPage.line(other, personal: personal)" in listed
    assert ("get: ArtistPageFacts.offersGet(other, mayGet: server.access.can(.request)),\n"
            "                                   busy: theirs?.opening == other.key)") in listed
    assert "theirs?.open(other, client: server.client, online: reachability.online, navigation: navigation)" in listed
    # its cover through deadwax's relay, as the MusicBrainz page's row has it
    row = function(view, "private struct ArtistTheirRow: View {")
    assert "ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: row.group.id)" in row
    mb = code(MB_VIEW)
    assert "ArchiveCover(addresses: ArchiveCoverID.addresses(release: nil, group: row.group.id)" in mb
    # a row asking the id bridge lets go once the page stops showing, as on that page
    assert ".onChange(of: navigation.tab) { _, _ in model.discography?.standDown() }" in view
    assert re.search(r"\.onChange\(of: navigation\.nowPlayingShown\) \{ _, shown in\s*if shown \{ model\.discography\?\.standDown\(\) \}", view)
    assert ".onDisappear { model.discography?.standDown() }" in view


def test_musicbrainzs_trouble_is_said_once_in_a_listeners_words():
    view = code(VIEW)
    listed = function(view, "private func albumsList(")
    # under the rows, once - never in a row
    each = function(listed, "ForEach(rows) { (row: ArtistJoin.Row) in")
    assert "ErrorNote" not in each and "theirFoot" not in each
    assert listed.count("theirFoot(") == 1
    # (R6) the foot a view of its own, the Mac's page's too - its Try again the page's ask
    asks = function(view, "private func theirFoot(")
    assert "model.theirAlbums(mbid: mbid, client: server.client, online: reachability.online, retry: true)" in asks
    foot = function(view, "struct ArtistTheirFoot: View {")
    assert "switch ArtistJoin.foot(" in foot
    assert "ErrorNote(text: MBArtistPage.away)" in foot
    assert "ErrorNote(error, retry: true)" in foot
    assert "Button(SearchWords.tryAgain, action: again)" in foot
    # no words of its own: each comes from Core
    assert not re.search(r'Text\("', foot)


def test_the_page_asks_the_library_as_it_opens_and_waits_for_it_a_moment():
    view = code(VIEW)
    opened = view[view.index(".task(id: taskKey) {"):]
    opened = block(opened, opened.index("{"))
    assert opened.index("search.refreshOwned()") < opened.index("await model.load(")
    assert "SearchPacing.ownedWaitMs" in view
    assert ".task(id: \"\\(taskKey)|\\(mbid ?? \"\")\")" in view
