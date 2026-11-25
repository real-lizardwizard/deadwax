"""
Descriptions, Last.fm first (2.1.42, S3 - notes/lastfm.md; the design's 2.8): src/descriptions.py from_lastfm() and
answer_lastfm_first(), and GET /deadwax/describe/artist and /album (src/routes/describe.py) with a LASTFM_API_KEY -
through the whole app, start(), on one event loop, with a real SQLite store, a real MusicBrainzClient, the module's
own Last.fm client and keeper, and the fakes of tests/test_describe.py (MusicBrainz, Wikidata and Wikipedia as
recorded on 2026-10-24, Navidrome from its source) beside tests/test_lastfm_routes.py's Last.fm.

LAST.FM'S ANSWERS ARE ITS OWN: tests/fixtures/lastfm/recorded/ (record.py, 2026-11-25), answered by
test_lastfm_routes.LastFm only for a request asked exactly as record.py asked it - so every request the descriptions
send must be one record.py records. What no recording holds is inline and marked: SHAPED (from Last.fm's API pages,
or MusicBrainz's documented lookups), WRITTEN FROM THE DESIGN and WRITTEN FROM THE REVIEW (the disambiguation wording
- no recording has a disambiguation page - the line breaks, and album.getInfo for albums record.py didn't ask), and
getInfo for an id Last.fm doesn't know (its recorded not-known answer for an unknown name,
NOT_KNOWN, as S2's tests give it).

What this holds:
  - THE RECORDINGS' TAILS: every bio's and album wiki's content ends "<link>Read more on Last.fm</a>. User-contributed
    text is available under the Creative Commons By-SA License; additional terms may apply.", every summary at the
    link - and none of it is ever said; a list after the prose (Dance Gavin Dance's discography) isn't either.
  - THE ORDER, with a key: Last.fm's words, else Wikipedia's, else Navidrome's; the subtitle Wikidata's always.
  - THE LOOKUPS: an artist's Last.fm side is S2's kept getInfo row, by id, then by the name get_artist gives (the
    Wikipedia side's own lookup); an album's is album.getInfo by its release group's title and artist credit, from
    ONE lookup with url-rels+artist-credits, shared by both sides - never asked twice, even when both want it at once -
    and kept under the release group, so albums whose names fold alike never share one.
  - THE SIGNALS: `unavailable` when Last.fm failed - down, limiting, refusing the key (the real 403), past the
    deadline, or its lookup failing - and the others' words all the same.
  - WITHOUT A KEY: nothing asked of Last.fm, the release group's lookup url-rels alone (tests/test_describe.py, run
    unchanged, holds the rest).
"""

import asyncio
import json
import sqlite3
import time

import httpx
import pytest

from src import descriptions as D
from src.api import lastfm_endpoint
from src.api.musicbrainz_endpoint import MusicBrainzClient, RateLimit, ResponseCache
from src.api.navidrome_endpoint import navidrome
from src.api.wikipedia_endpoint import wikipedia
from src.config import Config
from src.lastfm import LASTFM_SHAPE, album_info, artist_info, name_key
from src.lastfm_kept import artist_key, release_group_key
from src.routes import describe as describe_route
from src.routes import lastfm as lastfm_route
from src.store import JobStore
from tests.test_describe import (DUMMY, MB_DUMMY, ND_ALBUM_INFO, ND_ARTIST_INFO, ND_WORDS, NOBODY, PORTISHEAD,
                                 PORTISHEAD_WORDS, MusicBrainz, Wikimedia, found, relation)
from tests.test_lastfm import REFUSED_INVALID_KEY, answer
from tests.test_lastfm_routes import KEY, NOT_KNOWN, SHAPED_LIMITED, LastFm, serving, until
from tests.test_navidrome import failed, ok

TAME = "63aa26c3-d59b-4da4-84ac-716b54f1ef4d"
DGD = "16456fed-c9f2-4adf-b6ea-97b648c474d2"

#? the sentence Last.fm ends every content with, after its link - as the recordings have it, word for word
LICENCE = ("User-contributed text is available under the Creative Commons By-SA License; additional terms may "
           "apply.")
#? every recording with a bio or a wiki in it: (file, kind)
WORDED = (("tame-impala.info.mbid", "artist"), ("tame-impala.info.name", "artist"),
          ("dance-gavin-dance.info.mbid", "artist"), ("dance-gavin-dance.info.name", "artist"),
          ("portishead.info.mbid", "artist"), ("portishead.info.name", "artist"),
          ("misspelt.info", "artist"), ("misspelt.info.no-autocorrect", "artist"),
          ("portishead.dummy.album-info", "album"))


def raw_words(name: str) -> tuple[dict, dict]:
    """A recording's answer object (artist or album) and its bio or wiki, as Last.fm sent them."""
    body = answer(name)
    thing = body.get("artist") or body.get("album")
    return thing, thing.get("bio") or thing.get("wiki")


def kept_shape(name: str, kind: str) -> dict:
    """A recording as deadwax keeps it - what from_lastfm reads."""
    return (artist_info if kind == "artist" else album_info)(answer(name))


def one_line(text: str) -> str:
    return " ".join(text.split())


# ----- what the recordings show ------------------------------------------------------------------------------------

def test_the_recorded_words_end_with_last_fms_link_and_its_licence():
    """The design remembered the licence sentence and the "Read more" tail; the recordings (2026-11-25) say: every
    content ends with the link, a full stop and the licence; every summary with the link - an album's with a full
    stop after it, an artist's without. A page with no words (the misspelling's) is its link alone."""
    for name, kind in WORDED:
        thing, words = raw_words(name)
        link = f'<a href="{thing["url"]}">Read more on Last.fm</a>'
        if name.startswith("misspelt"):
            assert (words["summary"], words["content"]) == (f" {link}", ""), name
            continue
        assert words["content"].endswith(f" {link}. {LICENCE}"), name
        assert words["content"].count("Read more on Last.fm") == 1 and words["content"].count(LICENCE) == 1, name
        assert words["summary"].endswith(f" {link}." if kind == "album" else f" {link}"), name
        assert LICENCE not in words["summary"], name
    #? and no recording is a disambiguation page: that rule is written from the design (test_a_disambiguation_page...)
    for name, kind in WORDED:
        _, words = raw_words(name)
        assert not words["content"].lstrip().lower().startswith("there "), name


@pytest.mark.parametrize("name, kind", WORDED)
def test_last_fms_words_are_said_without_its_link_its_licence_or_any_markup(name, kind):
    said = D.from_lastfm(kept_shape(name, kind), kind)
    if name.startswith("misspelt"):
        assert said is None, "a page with no words says nothing"
        return
    thing, _ = raw_words(name)
    assert said["source"] == "lastfm" and said["url"] == thing["url"] and said["url"].startswith("https://www.last.fm/")
    text = said["text"]
    assert 0 < len(text) <= D.MAX_LETTERS
    for never in ("Read more on Last.fm", "User-contributed", "Creative Commons", "<", ">", "\n", "  "):
        assert never not in text, (name, never)
    assert text[-1] in ".!?\"'", "it ends where a sentence does"


@pytest.mark.parametrize("name, kind", [("portishead.info.mbid", "artist"), ("portishead.dummy.album-info", "album")])
def test_a_whole_content_is_said_whole(name, kind):
    """Portishead's bio and Dummy's wiki are short: all their words, from the content - everything before Last.fm's
    link, made one line."""
    _, words = raw_words(name)
    before_the_link = words["content"].split(" <a href=")[0]
    assert D.from_lastfm(kept_shape(name, kind), kind)["text"] == one_line(before_the_link)


def test_a_long_content_is_cut_where_a_sentence_ends():
    """Tame Impala's content is 10,843 letters, kept cut at BIO_MAX: what is said is its start, to the last sentence
    within MAX_LETTERS - its first paragraph, and as much of the second as ends a sentence."""
    _, words = raw_words("tame-impala.info.mbid")
    said = D.from_lastfm(kept_shape("tame-impala.info.mbid", "artist"), "artist")["text"]
    assert one_line(words["content"]).startswith(said)
    assert D.MAX_LETTERS // 2 <= len(said) <= D.MAX_LETTERS and said.endswith(".")
    assert said.startswith(one_line(words["content"].split("\n\n")[0]))


def test_a_list_after_the_prose_is_not_said():
    """Dance Gavin Dance's content is two paragraphs, then "Discography:", "Band members:" and the rest, a line each:
    the two paragraphs are said, never "... Discography: November 14, 2006 - Whatever I Say Is Royal Ocean ..."."""
    _, words = raw_words("dance-gavin-dance.info.mbid")
    paragraphs = words["content"].split("\n\n")
    assert paragraphs[2].startswith("Discography:\n")
    said = D.from_lastfm(kept_shape("dance-gavin-dance.info.mbid", "artist"), "artist")["text"]
    assert said == one_line(" ".join(paragraphs[:2]))
    assert "Discography" not in said


# ----- the rules, inline ---------------------------------------------------------------------------------------------

LINK = '<a href="https://www.last.fm/music/X">Read more on Last.fm</a>'


def bio(content=None, summary=None, url="https://www.last.fm/music/X") -> dict:
    """SHAPED: a kept getInfo row (src/lastfm.py artist_info's shape)."""
    return {"url": url, "listeners": 1, "bio": {"summary": summary, "content": content}}


def test_the_summary_when_there_is_no_content():
    assert D.from_lastfm(bio(None, f"Short &amp; sweet. {LINK}"), "artist")["text"] == "Short & sweet."
    assert D.from_lastfm(bio("", f"Short. {LINK}"), "artist")["text"] == "Short."
    #? a content with nothing before its link is no words: the summary's are said
    assert D.from_lastfm(bio(f" {LINK}. {LICENCE}", f"Short. {LINK}"), "artist")["text"] == "Short."
    assert D.from_lastfm(bio(f" {LINK}", f" {LINK}"), "artist") is None


def test_an_album_reads_its_wiki_and_an_artist_its_bio():
    both = {"url": "https://www.last.fm/music/X/Y", "bio": {"content": f"The artist. {LINK}"},
            "wiki": {"content": f"The album. {LINK}"}}
    assert D.from_lastfm(both, "album")["text"] == "The album."
    assert D.from_lastfm(both, "artist")["text"] == "The artist."
    for junk in (None, {}, [], "x", {"bio": "x"}, {"bio": {"content": 5, "summary": ["x"]}}):
        assert D.from_lastfm(junk, "artist") is None


def test_the_licence_is_dropped_in_any_case_and_anywhere():
    """SHAPED: the licence as the recordings have it, but in capitals, on lines of its own, before the link."""
    shouting = LICENCE.upper().replace(" ", "\n ")
    assert D.from_lastfm(bio(f"Words. {shouting} {LINK}"), "artist")["text"] == "Words."
    assert D.from_lastfm(bio(f"Words. {LINK}. {LICENCE}"), "artist")["text"] == "Words."


def test_a_content_the_keeping_cut_inside_its_licence_says_none_of_it():
    """A content of just past BIO_MAX letters is kept cut inside the licence that follows its link: whatever follows
    the link is Last.fm's footer, said not at all - not "... User-contributed text is avail"."""
    for footer in (". User-contributed text is avail", ". User-contributed", ". ", ""):
        assert D.from_lastfm(bio(f"Words (2011-2012) {LINK}{footer}"), "artist")["text"] == "Words (2011-2012)", footer


def test_only_a_last_fm_page_is_linked():
    for link in ("http://www.last.fm/music/X", "https://evil.example/last.fm", "javascript:alert(1)", None, 5):
        assert D.from_lastfm(bio(f"Words. {LINK}", url=link), "artist")["url"] is None, link


def test_words_the_keeping_cut_short_end_at_a_sentence():
    """A content kept cut (BIO_MAX letters, or its bytes) has no link at its end: its last words, half a sentence -
    and a tag the cut went through - never said."""
    cut = "First sentence of the bio. Second sentence of the bio. Third sentence, cut off in the mid"
    assert D.from_lastfm(bio(cut), "artist")["text"] == "First sentence of the bio. Second sentence of the bio."
    tag = 'First sentence of the bio. Second sentence of the bio. Then a <a href="https://www.last.fm/mu'
    assert D.from_lastfm(bio(tag), "artist")["text"] == "First sentence of the bio. Second sentence of the bio."
    #? no sentence end in its second half: the last word, and an ellipsis
    assert D.from_lastfm(bio("One. " + "word " * 30 + "wor"), "artist")["text"] == "One. " + " ".join(["word"] * 30) + chr(0x2026)
    #? cut where a sentence ends anyway: as it is
    assert D.from_lastfm(bio("One sentence. Two sentences."), "artist")["text"] == "One sentence. Two sentences."
    #? with its link, the words are whole: nothing cut back
    assert D.from_lastfm(bio(f"Words (2011-2012) {LINK}"), "artist")["text"] == "Words (2011-2012)"


#? SHAPED: two paragraphs' worth of prose - past PROSE_BEFORE_A_LIST, so a list after it is where the words stop
PROSE = ("They formed in Bristol in 1991 and made three albums in ten years. " * 2 +
         "Their second paragraph is about the records and the tours that followed them.\n\n"
         "They are still going, and play a few shows a year.")


def test_a_list_first_is_said_as_it_is_and_a_list_later_is_not():
    """SHAPED: a list after prose is where the words stop; a content that IS a list has no prose to say instead."""
    assert len(one_line(PROSE)) >= D.PROSE_BEFORE_A_LIST
    assert D.from_lastfm(bio(f"{PROSE}\n\nMembers:\nA - drums\nB - bass\n\nMore prose. {LINK}"), "artist")[
        "text"] == one_line(PROSE)
    assert D.from_lastfm(bio(f"Members:\nA - drums\nB - bass {LINK}"), "artist")["text"] == "Members: A - drums B - bass"
    assert D.from_lastfm(bio(f"One.\n\nTwo.\n\nThree. {LINK}"), "artist")["text"] == "One. Two. Three."


def test_a_line_break_inside_prose_is_no_list_and_a_line_or_two_is_never_all_that_is_said():
    """WRITTEN FROM THE REVIEW: a paragraph with a line break in it is prose unless it reads as a list - lines short
    and ending no sentence, three or more - and a list right after a line or two ("Mogwai.") isn't where the words
    end: that would say "Mogwai." alone, before any Wikipedia paragraph."""
    mogwai = ("Mogwai.\n\nMogwai are a Scottish post-rock band formed in Glasgow in 1995.\n"
              "They released their debut album, Young Team, in 1997.")
    assert D.from_lastfm(bio(f"{mogwai} {LINK}"), "artist")["text"] == one_line(mogwai)
    #? short lines, each a sentence: prose, after any amount of it
    soft = f"{PROSE}\n\nThey split in 2001.\nThey re-formed in 2010.\nThey toured in 2011.\n\nThe end."
    assert D.from_lastfm(bio(f"{soft} {LINK}"), "artist")["text"] == one_line(soft)
    #? a list after a line or two goes on with the rest
    short = "Mogwai.\n\nMembers:\nA - guitar\nB - bass\n\nThey are from Glasgow."
    assert D.from_lastfm(bio(f"{short} {LINK}"), "artist")["text"] == one_line(short)
    #? and one after a real amount still ends the words, as Dance Gavin Dance's recorded discography does
    assert D.from_lastfm(bio(f"{PROSE}\n\nMembers:\nA - guitar\nB - bass {LINK}"), "artist")["text"] == one_line(PROSE)


@pytest.mark.parametrize("words", [
    "There are at least 3 artists with this name: 1) A band from Bristol. 2) A rapper.",
    "There is more than one artist with this name.",
    "There are multiple artists named Nirvana.",
    "There are several bands called Low.",
    "There were two acts by this name.",
    "There are 4 artists with this name.",
    "there are many artists called this",
    #? WRITTEN FROM THE REVIEW
    "There are several different artists with this name: 1) A Scottish post-rock band. 2) An American rapper.",
    "1) A Scottish post-rock band from Glasgow.\n2) An American rapper from Atlanta.",
    "1) A Scottish post-rock band. 2) An American rapper.",
    "Several artists share this name:\n\n1) A Scottish post-rock band.\n\n2) An American rapper.",
    "1. A Scottish post-rock band.\n2. An American rapper.",
])
def test_a_disambiguation_page_says_nothing(words):
    """WRITTEN FROM THE DESIGN (deadwax-plans/lastfm.md 2.8) and THE REVIEW: no recording holds a page for several
    artists of one name, so its wording is the design's - with the singular taken too ("more than one artist") - and
    the review's: "several different artists with this name", and a page numbered "1) ... 2) ..." from its start."""
    assert D.from_lastfm(bio(f"{words} {LINK}"), "artist") is None
    assert D.from_lastfm({"url": None, "wiki": {"content": f"{words} {LINK}"}}, "album") is None


def test_a_page_that_only_begins_like_one_is_said():
    for words in ("There are many reasons Portishead matter.", "They are two artists from Bristol.",
                  "Portishead: there are several bands like them.",
                  #? WRITTEN FROM THE REVIEW: artists, bands and acts, but not of one name
                  "There were two band members in the first line-up, and both of them stayed.",
                  "There are 18 artists on this compilation, all of them from Bristol.",
                  "There are many acts of kindness in their songs.",
                  #? numbered, but not from the start
                  "Portishead made two albums in the nineties. 1) Dummy 2) Portishead"):
        assert D.from_lastfm(bio(f"{words} {LINK}"), "artist")["text"] == words


def test_the_order_with_a_key():
    heard = {"text": "L.", "source": "lastfm", "url": "https://www.last.fm/music/X"}
    said = {"text": "N.", "source": "lastfm", "url": None}
    row = {"text": "W.", "url": "https://en.wikipedia.org/wiki/X", "subtitle": "S"}
    assert D.answer_lastfm_first(heard, row, said) == found("L.", "lastfm", "https://www.last.fm/music/X", "S")
    assert D.answer_lastfm_first(None, row, said) == found("W.", "wikipedia", "https://en.wikipedia.org/wiki/X", "S")
    assert D.answer_lastfm_first(None, {**row, "text": None}, said, True) == found("N.", "lastfm", None, "S", True)
    assert D.answer_lastfm_first(None, None, None) == D.NONE


# ----- the routes, with a key ----------------------------------------------------------------------------------------

#? SHAPED, from MusicBrainz's release-group lookup with inc=artist-credits (its web service's documented `artist-credit`)
DUMMY_CREDIT = [{"name": "Portishead", "joinphrase": "", "artist": {
    "id": PORTISHEAD, "name": "Portishead", "sort-name": "Portishead", "type": "Group", "disambiguation": ""}}]


class SlowMusicBrainz(MusicBrainz):
    """test_describe's MusicBrainz, taking a moment over each answer - so two sides asking at once would both be out
    before either came back - and giving a release group's artist credit only when asked for it."""

    def __init__(self):
        super().__init__()
        self.delay = 0.2
        #? endpoint -> the artist credit it is given (DUMMY_CREDIT where none is named)
        self.credits: dict[str, list] = {}

    async def get(self, endpoint, params=None):
        await asyncio.sleep(self.delay)
        got = await super().get(endpoint, params)
        if endpoint.startswith("release-group/") and "artist-credits" in (params or {}).get("inc", "").split("+"):
            if got.status_code == 200:
                got.payload = {**got.payload, "artist-credit": self.credits.get(endpoint, DUMMY_CREDIT)}
        return got


class Env:
    pass


@pytest.fixture
def env(monkeypatch, tmp_path):
    monkeypatch.setattr(Config, "AUTH_MODE", None)
    monkeypatch.setattr(Config, "LASTFM_API_KEY", KEY)
    monkeypatch.setattr(lastfm_endpoint, "PER_SECOND", 1000)
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16))
    monkeypatch.setattr(MusicBrainzClient, "rate_limit", RateLimit())
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "james@example.com")
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
    e = Env()
    e.mb = SlowMusicBrainz()
    mb_client = MusicBrainzClient()

    async def get_client():
        return e.mb

    mb_client.get_client = get_client  # type: ignore[method-assign]
    e.wiki = Wikimedia()
    wikipedia._client = httpx.AsyncClient(transport=httpx.MockTransport(e.wiki.handle), follow_redirects=True)
    e.nd = {"handler": lambda request: httpx.Response(200, json=failed(70, "Artist not found"))}
    e.nd_seen = []

    def handle(request: httpx.Request) -> httpx.Response:
        e.nd_seen.append(request)
        return e.nd["handler"](request)

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest")
    e.fake = LastFm()
    e.db = tmp_path / "deadwax.db"
    e.store = JobStore(str(e.db))
    e.store.init()
    with serving(e.store, e.fake) as (app, client):
        app.state.musicbrainz_client = mb_client
        e.app, e.client = app, client
        yield e
    asyncio.run(navidrome.close_client())
    asyncio.run(wikipedia.close_client())
    wikipedia._client = None
    assert e.fake.unmatched == [], "asked Last.fm something record.py doesn't record"
    assert set(e.fake.keys) <= {KEY}


def describe(env, kind: str, **query) -> dict:
    response = env.client.get(f"/deadwax/describe/{kind}", params=query)
    assert response.status_code == 200, response.text
    return response.json()


def lastfm_rows(env) -> dict[str, str | None]:
    with sqlite3.connect(env.db) as connection:
        return dict(connection.execute("SELECT key, body FROM lastfm_kept").fetchall())


def said_of(name: str, kind: str) -> dict:
    """What from_lastfm makes of a recording - the route's words for it."""
    return D.from_lastfm(kept_shape(name, kind), kind)


def test_with_a_key_an_artist_s_words_are_last_fm_s_before_wikipedia_s_and_navidrome_s(env):
    env.nd["handler"] = lambda request: httpx.Response(200, json=ok(**ND_ARTIST_INFO))

    got = describe(env, "artist", mbid=PORTISHEAD, navidrome_id="ar-1")

    words = said_of("portishead.info.mbid", "artist")
    assert got == found(words["text"], "lastfm", "https://www.last.fm/music/Portishead", "English band")
    assert got["text"].startswith("Portishead is an English band formed in 1991 in Bristol.")
    #? Last.fm by the id alone - the artist page's own getInfo, as record.py asks it
    assert env.fake.requests == [("artist.getinfo", {"mbid": PORTISHEAD})]
    assert set(lastfm_rows(env)) == {artist_key("artist.getinfo", mbid=PORTISHEAD)}
    assert lastfm_rows(env)[artist_key("artist.getinfo", mbid=PORTISHEAD)] == json.dumps(
        artist_info(answer("portishead.info.mbid")), ensure_ascii=True, separators=(",", ":"))
    #? the other two sides as without a key: Navidrome asked, Wikipedia's words and subtitle kept
    assert len(env.nd_seen) == 1
    assert env.mb.calls == [(f"artist/{PORTISHEAD}", {"inc": MusicBrainzClient.ARTIST_INC, "fmt": "json"})]
    kept = asyncio.run(env.store.description_get(f"artist:{PORTISHEAD}"))
    assert (kept["text"], kept["subtitle"]) == (PORTISHEAD_WORDS, "English band")


def test_one_getinfo_serves_the_artist_page_and_the_description(env):
    """The design's "one ask serves both": the description reads the row GET /deadwax/lastfm/artist kept, and the
    artist page the row the description kept."""
    assert env.client.get("/deadwax/lastfm/artist", params={"mbid": TAME}).status_code == 200
    assert sorted(method for method, _ in env.fake.requests) == ["artist.getinfo", "artist.gettoptracks"]
    got = describe(env, "artist", mbid=TAME)
    assert got["text"] == said_of("tame-impala.info.mbid", "artist")["text"] and got["source"] == "lastfm"
    assert len(env.fake.requests) == 2, "the description asked Last.fm nothing more"

    describe(env, "artist", mbid=DGD)
    assert env.fake.asked("artist.getinfo")[-1] == {"mbid": DGD}
    asked = len(env.fake.requests)
    assert env.client.get("/deadwax/lastfm/artist", params={"mbid": DGD}).status_code == 200
    assert env.fake.requests[asked:] == [("artist.gettoptracks", {"mbid": DGD, "limit": "50"})]


def test_a_second_visit_asks_last_fm_nothing(env):
    first = describe(env, "artist", mbid=DGD)
    assert first["text"] == said_of("dance-gavin-dance.info.mbid", "artist")["text"]
    assert describe(env, "artist", mbid=DGD) == first
    assert len(env.fake.requests) == 1


def test_an_id_last_fm_doesnt_know_is_asked_by_the_name_musicbrainz_gives_it(env):
    """getInfo by the id answers "not known" (Last.fm's recorded answer for an unknown name, given for the id): asked
    again by name - the name get_artist gives, the very lookup the Wikipedia side makes, made once for both."""
    env.fake.add("artist.getinfo", {"mbid": NOBODY}, *NOT_KNOWN)
    env.mb.answers[f"artist/{NOBODY}"] = {"id": NOBODY, "name": "Tame Impala", "relations": [
        relation("wikidata", "https://www.wikidata.org/wiki/Q191352")]}

    got = describe(env, "artist", mbid=NOBODY)

    assert got == found(said_of("tame-impala.info.name", "artist")["text"], "lastfm",
                        "https://www.last.fm/music/Tame+Impala", "English band")
    assert env.fake.requests == [("artist.getinfo", {"mbid": NOBODY}),
                                 ("artist.getinfo", {"artist": "Tame Impala", "autocorrect": "1"})]
    assert env.mb.calls == [(f"artist/{NOBODY}", {"inc": MusicBrainzClient.ARTIST_INC, "fmt": "json"})]
    rows = lastfm_rows(env)
    assert rows[artist_key("artist.getinfo", mbid=NOBODY)] is None
    assert rows[artist_key("artist.getinfo", name="Tame Impala")] is not None


@pytest.mark.parametrize("name", ["", "!!!", "N" * 201, None])
def test_an_id_last_fm_doesnt_know_with_no_name_to_ask_by_is_none(env, name):
    """MusicBrainz giving no name, one that folds to nothing, or one past the artist page's NAME_MAX: nothing asked by
    name, and a definite none, not a failure."""
    env.fake.add("artist.getinfo", {"mbid": NOBODY}, *NOT_KNOWN)
    env.mb.answers[f"artist/{NOBODY}"] = {"id": NOBODY, "name": name, "relations": []}

    assert describe(env, "artist", mbid=NOBODY) == D.NONE
    assert env.fake.requests == [("artist.getinfo", {"mbid": NOBODY})]


def test_with_a_key_an_album_s_words_are_last_fm_s_by_its_names_from_one_lookup(env):
    got = describe(env, "album", mbid=DUMMY)

    words = said_of("portishead.dummy.album-info", "album")
    assert got == found(words["text"], "lastfm", "https://www.last.fm/music/Portishead/Dummy",
                        "1994 studio album by Portishead")
    assert got["text"].startswith("Dummy is the debut studio album by English band Portishead")
    #? by the release group's title and its artist credit's name - never an mbid - as record.py asks it
    assert env.fake.requests == [("album.getinfo", {"artist": "Portishead", "album": "Dummy", "autocorrect": "1"})]
    #? ONE MusicBrainz lookup, with its artist credit - the Wikipedia side's url-rels from the same answer, though
    #? both sides wanted it at once and MusicBrainz took 0.2 s
    assert env.mb.calls == [(f"release-group/{DUMMY}", {"inc": "url-rels+artist-credits", "fmt": "json"})]
    assert env.wiki.asked()[-1] == "en.wikipedia.org/api/rest_v1/page/summary/Dummy_(album)"
    rows = lastfm_rows(env)
    #? kept under the release group's id, not the names it was asked by
    assert set(rows) == {release_group_key("album.getinfo", DUMMY)} == {f"{LASTFM_SHAPE}|album.getinfo|group|{DUMMY}"}
    assert rows[release_group_key("album.getinfo", DUMMY)] == json.dumps(
        album_info(answer("portishead.dummy.album-info")), ensure_ascii=True, separators=(",", ":"))

    #? kept: a second visit asks Last.fm nothing, and MusicBrainz nothing (its answer kept an hour in memory)
    assert describe(env, "album", mbid=DUMMY) == got
    assert len(env.fake.requests) == 1 and len(env.mb.calls) == 1


def test_an_album_whose_wikipedia_side_is_kept_still_has_its_last_fm_side(env, monkeypatch):
    """The Wikipedia side kept, the Last.fm side not (a key added since): the lookup is made for Last.fm alone."""
    monkeypatch.setattr(Config, "LASTFM_API_KEY", None)
    before = describe(env, "album", mbid=DUMMY)
    assert before["source"] == "wikipedia" and env.fake.requests == []
    monkeypatch.setattr(Config, "LASTFM_API_KEY", KEY)

    got = describe(env, "album", mbid=DUMMY)

    assert got["source"] == "lastfm" and got["subtitle"] == before["subtitle"]
    assert [params["inc"] for _, params in env.mb.calls] == ["url-rels", "url-rels+artist-credits"]
    assert len(env.fake.requests) == 1


@pytest.mark.parametrize("credit, title", [
    ([], "Dummy"),
    (DUMMY_CREDIT, "   "),
    (DUMMY_CREDIT, "D" * 201),
    ([{"name": "", "joinphrase": "", "artist": {"name": ""}}], "Dummy"),
])
def test_an_album_without_names_to_ask_by_has_no_last_fm_side(env, credit, title):
    """No artist credit, a title of nothing but spaces, or a name past NAME_MAX: Last.fm isn't asked, and that is no
    failure - Wikipedia's words, said as they are."""
    env.mb.credits = {f"release-group/{DUMMY}": credit}
    env.mb.answers[f"release-group/{DUMMY}"] = {**MB_DUMMY, "title": title}

    got = describe(env, "album", mbid=DUMMY)

    assert got["source"] == "wikipedia" and got["unavailable"] is False
    assert env.fake.requests == []


def test_an_artist_or_album_by_navidrome_s_id_alone_has_no_last_fm_side(env):
    env.nd["handler"] = lambda request: httpx.Response(
        200, json=ok(**(ND_ALBUM_INFO if "getAlbumInfo2" in request.url.path else ND_ARTIST_INFO)))

    assert describe(env, "artist", navidrome_id="ar-1") == found(ND_WORDS, "lastfm", "https://www.last.fm/music/Portishead")
    assert describe(env, "album", navidrome_id="al-1")["text"] == "Dummy is the debut album by Portishead."
    assert env.fake.requests == [] and env.mb.calls == [] and env.wiki.requests == []


def test_last_fm_with_no_words_leaves_wikipedia_s_before_navidrome_s(env):
    """Last.fm's page for "Tame Impla" (recorded: no bio at all): Wikipedia's words, not Navidrome's."""
    env.nd["handler"] = lambda request: httpx.Response(200, json=ok(**ND_ARTIST_INFO))
    env.fake.add("artist.getinfo", {"mbid": NOBODY}, *NOT_KNOWN)
    env.mb.answers[f"artist/{NOBODY}"] = {"id": NOBODY, "name": "Tame Impla", "relations": [
        relation("wikidata", "https://www.wikidata.org/wiki/Q191352")]}

    got = describe(env, "artist", mbid=NOBODY, navidrome_id="ar-1")

    assert got == found(PORTISHEAD_WORDS, "wikipedia", "https://en.wikipedia.org/wiki/Portishead_(band)",
                        "English band")
    assert env.fake.asked("artist.getinfo")[-1] == {"artist": "Tame Impla", "autocorrect": "1"}


def test_last_fm_and_wikipedia_with_no_words_leave_navidrome_s(env):
    env.nd["handler"] = lambda request: httpx.Response(200, json=ok(**ND_ARTIST_INFO))
    env.fake.add("artist.getinfo", {"mbid": NOBODY}, *NOT_KNOWN)
    env.mb.answers[f"artist/{NOBODY}"] = {"id": NOBODY, "name": "Tame Impla", "relations": []}

    got = describe(env, "artist", mbid=NOBODY, navidrome_id="ar-1")

    assert got == found(ND_WORDS, "lastfm", "https://www.last.fm/music/Portishead")


@pytest.mark.parametrize("trouble", ["down", "refused", "limited"])
def test_last_fm_failing_leaves_the_others_words_and_says_unavailable(env, trouble):
    """Last.fm away (a 503), refusing the key (its real 403, error 10) or limiting (SHAPED: a 29): the description is
    Wikipedia's - or Navidrome's - all the same, said `unavailable` so the app asks again soon; nothing kept."""
    if trouble == "down":
        env.fake.down = True
    elif trouble == "refused":
        held = json.loads(REFUSED_INVALID_KEY.read_text(encoding="ascii"))
        env.fake.instead["artist.getinfo"] = (held["status"], held["answer"])
    else:
        env.fake.instead["artist.getinfo"] = SHAPED_LIMITED

    got = describe(env, "artist", mbid=PORTISHEAD)

    assert got == found(PORTISHEAD_WORDS, "wikipedia", "https://en.wikipedia.org/wiki/Portishead_(band)",
                        "English band", unavailable=True)
    assert lastfm_rows(env) == {}

    env.nd["handler"] = lambda request: httpx.Response(200, json=ok(**ND_ARTIST_INFO))
    env.wiki.down = True
    assert describe(env, "artist", mbid=DGD, navidrome_id="ar-1") == found(
        ND_WORDS, "lastfm", "https://www.last.fm/music/Portishead", None, unavailable=True)


def test_while_last_fm_refuses_the_key_what_was_kept_is_still_said(env):
    first = describe(env, "artist", mbid=PORTISHEAD)
    assert first["source"] == "lastfm"
    held = json.loads(REFUSED_INVALID_KEY.read_text(encoding="ascii"))
    env.fake.instead["artist.getinfo"] = (held["status"], held["answer"])
    #? a refusal for another artist: the client holds it, and asks nothing for an hour
    assert describe(env, "artist", mbid=DGD)["unavailable"] is True
    assert describe(env, "artist", mbid=PORTISHEAD) == first


def test_an_album_s_lookup_failing_is_unavailable_and_asks_last_fm_nothing(env):
    env.mb.down = True
    assert describe(env, "album", mbid=DUMMY) == {**D.NONE, "unavailable": True}
    assert env.fake.requests == []


def test_an_album_last_fm_doesnt_know_is_none_and_no_failure(env):
    #? SHAPED: album.getInfo's error 6, as its errors page words it - record.py records no unknown album
    env.mb.answers[f"release-group/{DUMMY}"] = {**MB_DUMMY, "title": "Dumy"}
    env.fake.add("album.getinfo", {"artist": "Portishead", "album": "Dumy", "autocorrect": "1"}, 200,
                 {"error": 6, "message": "Album not found", "links": []})

    got = describe(env, "album", mbid=DUMMY)

    assert got["source"] == "wikipedia" and got["unavailable"] is False
    assert lastfm_rows(env) == {release_group_key("album.getinfo", DUMMY): None}


#? two release groups (SHAPED, as test_describe's MB_DUMMY, with no relations: no Wikipedia side to stand in)
FIRST_GROUP = "11111111-1111-4111-8111-111111111111"
SECOND_GROUP = "22222222-2222-4222-8222-222222222222"


def group_of(env, mbid: str, artist: str, title: str) -> None:
    env.mb.answers[f"release-group/{mbid}"] = {**MB_DUMMY, "id": mbid, "title": title, "relations": []}
    env.mb.credits[f"release-group/{mbid}"] = [{"name": artist, "joinphrase": "", "artist": {"name": artist}}]


def written_album(artist: str, title: str) -> dict:
    """WRITTEN FROM THE REVIEW: album.getInfo's answer for an album record.py didn't record - Dummy's recorded answer,
    its names, address and words replaced (the words ending in the link and licence, as every recording's do)."""
    body = answer("portishead.dummy.album-info")
    url = f"https://www.last.fm/music/{artist.replace(' ', '+')}/{title.replace(' ', '+')}"
    words = f"Last.fm's page for {title} by {artist}."
    return {**body, "album": {**body["album"], "artist": artist, "name": title, "url": url, "wiki": {
        "published": "01 Jan 2020, 00:00", "summary": f'{words} <a href="{url}">Read more on Last.fm</a>.',
        "content": f'{words} <a href="{url}">Read more on Last.fm</a>. {LICENCE}'}}}


@pytest.mark.parametrize("artist, first, second", [
    ("Taylor Swift", "Fearless", "Fearless (Taylor's Version)"),
    ("Mogwai", "Live", "Live [Bonus]"),
    ("Pink Floyd", "The Wall", "Wall"),
])
def test_two_albums_whose_names_fold_alike_each_have_their_own_last_fm_words(env, artist, first, second):
    """The review's: name_key drops a bracketed aside and a leading "The", so these pairs fold to one name. Kept
    under the names, the first album asked would be shown for the other for a week - before its Wikipedia paragraph.
    Kept under each one's release group, each is asked by its own names and said as Last.fm has it."""
    assert name_key(first) == name_key(second)
    for mbid, title in ((FIRST_GROUP, first), (SECOND_GROUP, second)):
        group_of(env, mbid, artist, title)
        env.fake.add("album.getinfo", {"artist": artist, "album": title, "autocorrect": "1"}, 200,
                     written_album(artist, title))

    one = describe(env, "album", mbid=FIRST_GROUP)
    other = describe(env, "album", mbid=SECOND_GROUP)

    assert one["text"] == f"Last.fm's page for {first} by {artist}." and one["source"] == "lastfm"
    assert other["text"] == f"Last.fm's page for {second} by {artist}." and other["source"] == "lastfm"
    assert env.fake.asked("album.getinfo") == [{"artist": artist, "album": first, "autocorrect": "1"},
                                               {"artist": artist, "album": second, "autocorrect": "1"}]
    assert set(lastfm_rows(env)) == {release_group_key("album.getinfo", FIRST_GROUP),
                                     release_group_key("album.getinfo", SECOND_GROUP)}
    #? and each kept: asked again, nothing more of Last.fm
    assert describe(env, "album", mbid=FIRST_GROUP) == one and describe(env, "album", mbid=SECOND_GROUP) == other
    assert len(env.fake.requests) == 2


def test_an_album_whose_names_fold_to_nothing_is_still_asked_kept_under_its_group(env):
    """!!!'s names fold to nothing (name_key), which would have shared one kept row with every other such album; kept
    under its release group, it is asked like any other. SHAPED: album.getInfo's error 6, as its errors page words
    it."""
    group_of(env, FIRST_GROUP, "!!!", "!!!")
    env.fake.add("album.getinfo", {"artist": "!!!", "album": "!!!", "autocorrect": "1"}, 200,
                 {"error": 6, "message": "Album not found", "links": []})

    assert describe(env, "album", mbid=FIRST_GROUP) == D.NONE
    assert lastfm_rows(env) == {release_group_key("album.getinfo", FIRST_GROUP): None}


def test_a_last_fm_still_answering_at_the_deadline_leaves_the_others_words_and_is_kept_when_it_comes(env, monkeypatch):
    """A Last.fm that takes the connection and holds its answer (the stand-in, 1.5 s) holds the description back no
    longer than LASTFM_DEADLINE_S - S2's own deadline: Wikipedia's words, said `unavailable`. The side goes on, never
    cancelled by the page, and Last.fm's answer is kept when it comes: the next visit has its words, asking nothing."""
    assert describe_route.LASTFM_DEADLINE_S == lastfm_route.ARTIST_DEADLINE_S == 4.0
    monkeypatch.setattr(describe_route, "LASTFM_DEADLINE_S", 0.4)
    env.fake.slow = {"artist.getinfo": 1.5}

    began = time.monotonic()
    got = describe(env, "artist", mbid=PORTISHEAD)

    assert time.monotonic() - began < 1.2, "the description waited for Last.fm"
    assert got == found(PORTISHEAD_WORDS, "wikipedia", "https://en.wikipedia.org/wiki/Portishead_(band)",
                        "English band", unavailable=True)
    until(lambda: artist_key("artist.getinfo", mbid=PORTISHEAD) in lastfm_rows(env))
    env.fake.slow = {}
    again = describe(env, "artist", mbid=PORTISHEAD)
    assert again == found(said_of("portishead.info.mbid", "artist")["text"], "lastfm",
                          "https://www.last.fm/music/Portishead", "English band")
    assert env.fake.requests == [("artist.getinfo", {"mbid": PORTISHEAD})]


def test_an_album_whose_lookup_outlasts_the_deadline_has_wikipedia_s_words_and_last_fm_s_next_time(env, monkeypatch):
    """MusicBrainz slower than the deadline: the Last.fm side, still waiting on the lookup it shares with the Wikipedia
    side, is answered without - and isn't cancelled, which would cancel that shared lookup under the Wikipedia side
    too. Wikipedia's words, `unavailable`; the side goes on to ask Last.fm by the names and keep it."""
    monkeypatch.setattr(describe_route, "LASTFM_DEADLINE_S", 0.3)
    env.mb.delay = 0.6

    got = describe(env, "album", mbid=DUMMY)

    assert got["source"] == "wikipedia" and got["unavailable"] is True
    until(lambda: release_group_key("album.getinfo", DUMMY) in lastfm_rows(env))
    again = describe(env, "album", mbid=DUMMY)
    assert again["text"] == said_of("portishead.dummy.album-info", "album")["text"] and again["unavailable"] is False
    assert len(env.fake.requests) == 1 and len(env.mb.calls) == 1


def test_a_last_fm_side_that_raises_is_a_failure_not_the_description_s_end(env, monkeypatch):
    """A fault in deadwax's own Last.fm side (it never should raise): the others' words, `unavailable`."""
    async def broken(*_):
        raise RuntimeError("a fault")
    monkeypatch.setattr(describe_route, "lastfm_side", broken)

    got = describe(env, "artist", mbid=PORTISHEAD)

    assert got == found(PORTISHEAD_WORDS, "wikipedia", "https://en.wikipedia.org/wiki/Portishead_(band)",
                        "English band", unavailable=True)


def test_an_album_whose_wikipedia_side_is_kept_with_musicbrainz_down_is_unavailable(env, monkeypatch):
    """The review's gap: the Wikipedia side fresh in the database needs no lookup, so only the Last.fm side asks
    MusicBrainz for the album's names - and MusicBrainz is down. Wikipedia's kept words, said `unavailable` (Last.fm's
    side couldn't be had, so the app asks again soon); Last.fm asked nothing."""
    monkeypatch.setattr(Config, "LASTFM_API_KEY", None)
    before = describe(env, "album", mbid=DUMMY)
    assert before["source"] == "wikipedia" and before["unavailable"] is False
    monkeypatch.setattr(Config, "LASTFM_API_KEY", KEY)
    env.mb.down = True

    got = describe(env, "album", mbid=DUMMY)

    assert got == {**before, "unavailable": True}
    assert env.fake.requests == []
    assert [params["inc"] for _, params in env.mb.calls][-1] == "url-rels+artist-credits"


# ----- without a key -------------------------------------------------------------------------------------------------

@pytest.mark.parametrize("no_key", [None, "", "   "])
def test_without_a_key_last_fm_is_never_asked_and_the_lookups_are_as_they_were(env, monkeypatch, no_key):
    """tests/test_describe.py, run unchanged, holds what is answered without a key; this holds that nothing of S3's
    is reached: no Last.fm, no artist credit asked of MusicBrainz, Navidrome's words first again."""
    monkeypatch.setattr(Config, "LASTFM_API_KEY", no_key)
    env.nd["handler"] = lambda request: httpx.Response(
        200, json=ok(**(ND_ALBUM_INFO if "getAlbumInfo2" in request.url.path else ND_ARTIST_INFO)))

    artist = describe(env, "artist", mbid=PORTISHEAD, navidrome_id="ar-1")
    album = describe(env, "album", mbid=DUMMY, navidrome_id="al-1")

    assert artist == found(ND_WORDS, "lastfm", "https://www.last.fm/music/Portishead", "English band")
    assert album == found("Dummy is the debut album by Portishead.", "lastfm",
                          "https://www.last.fm/music/Portishead/Dummy", "1994 studio album by Portishead")
    assert env.fake.requests == [] and lastfm_rows(env) == {}
    assert env.mb.calls == [(f"artist/{PORTISHEAD}", {"inc": MusicBrainzClient.ARTIST_INC, "fmt": "json"}),
                            (f"release-group/{DUMMY}", {"inc": "url-rels", "fmt": "json"})]
