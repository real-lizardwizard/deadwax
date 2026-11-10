"""
A short description of an artist or an album (2.0.13) - src/descriptions.py (pure), src/api/wikipedia_endpoint.py
and the routes `GET /deadwax/describe/artist` and `/album` (src/routes/describe.py), through the whole app, start(),
with a real MusicBrainzClient, a real SQLite store, and fakes for MusicBrainz, Wikidata, Wikipedia and Navidrome.

The fakes are shaped from answers recorded on 2026-10-24 with deadwax's user agent - MusicBrainz's Portishead
(url-rels) and Dummy's release group (url-rels), Wikidata's wbgetentities (sitelinks and descriptions, enwiki and en)
for both and for an id it doesn't have, Wikipedia's REST summary of both pages and of one it doesn't have (404 `{"status":404}`) -
and Navidrome's getArtistInfo2 / getAlbumInfo2 from its source as read at 0.64.2 (server/subsonic/browsing.go,
responses.go; the biography's HTML as core/external/provider.go and adapters/lastfm/agent.go leave it). The suite
never calls out.

What these hold:

  - WHERE THE WORDS COME FROM (James: "Last.fm FIRST, Wikipedia (via MusicBrainz) as the fallback"): Navidrome's
    own (biography / notes), asked with the id alone (getArtistInfo2 with count 0), read as TEXT with Last.fm's
    "Read more" tail gone, linked to Last.fm's page only; else Wikipedia, by the MusicBrainz entity's `wikidata`
    link -> its English page -> that page's summary (`extract`, never `extract_html`), its page linked; an English
    `wikipedia` link when there is no Wikidata one (a French one never); neither, every field null.
  - THE SUBTITLE: Wikidata's English one-line description of the same item, from the same request, whichever the
    paragraph is - none when it has none.
  - THE LEAST ASKED: an artist's MusicBrainz lookup is get_artist's own (the facts' cache entry); an album's its
    release group with url-rels alone; Wikidata asked for the enwiki sitelink and the English description alone;
    every request to Wikimedia with deadwax's user agent; an id MusicBrainz has nothing at asked once, kept as none.
  - KEPT: a found description a month, "none" three days, in the database - asked nothing again meanwhile, after
    a restart too; older, asked again and replaced, and still answered if asking fails; a failure never kept
    (asked again next time), never an error for the page (a 200 with what there is), and said `unavailable`.
  - BOUNDED: no id at all a 422; an mbid that isn't one, or a Navidrome id past ID_MAX, a 422 with nothing asked.
"""

import asyncio
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import httpx
import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from src import descriptions as D  # noqa: E402
from src.api.app import start  # noqa: E402
from src.api.musicbrainz_endpoint import MusicBrainzClient, RateLimit, ResponseCache  # noqa: E402
from src.api.navidrome_endpoint import navidrome  # noqa: E402
from src.api.wikipedia_endpoint import wikipedia  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import describe as describe_route  # noqa: E402
from src.routes.navidrome import ID_MAX  # noqa: E402
from src.store import JobStore  # noqa: E402
from test_navidrome import failed, ok  # noqa: E402

PORTISHEAD = "8f6bd1e4-fbe1-4f50-aa9b-94c450ec0f11"
DUMMY = "48140466-cff6-3222-bd55-63c27e43190d"
NOBODY = "aaaaaaaa-0000-4000-8000-000000000001"

# ----------------------------------------------------------------- the recorded shapes (trimmed, otherwise as sent)

def relation(kind: str, resource: str) -> dict:
    return {"type": kind, "target-type": "url", "direction": "forward", "ended": False, "attributes": [],
            "url": {"resource": resource, "id": "00000000-0000-4000-8000-00000000000a"}}


MB_PORTISHEAD = {"id": PORTISHEAD, "name": "Portishead", "type": "Group", "relations": [
    relation("official homepage", "https://portishead.co.uk/"),
    relation("wikidata", "https://www.wikidata.org/wiki/Q191352"),
    #? Portishead's own `wikipedia` relation is to the FRENCH page - never said
    relation("wikipedia", "https://fr.wikipedia.org/wiki/Portishead_(groupe)"),
]}
MB_DUMMY = {"id": DUMMY, "title": "Dummy", "primary-type": "Album", "first-release-date": "1994-08-22",
            "secondary-types": [], "disambiguation": "", "relations": [
                relation("allmusic", "https://www.allmusic.com/album/mw0000626613"),
                relation("discogs", "https://www.discogs.com/master/5542"),
                relation("wikidata", "https://www.wikidata.org/wiki/Q911143"),
            ]}

WD_PORTISHEAD = {"entities": {"Q191352": {"type": "item", "id": "Q191352", "descriptions": {
    "en": {"language": "en", "value": "English band"}}, "sitelinks": {
    "enwiki": {"site": "enwiki", "title": "Portishead (band)", "badges": []}}}}, "success": 1}
WD_DUMMY = {"entities": {"Q911143": {"type": "item", "id": "Q911143", "descriptions": {
    "en": {"language": "en", "value": "1994 studio album by Portishead"}}, "sitelinks": {
    "enwiki": {"site": "enwiki", "title": "Dummy (album)", "badges": []}}}}, "success": 1}
WD_NO_ENGLISH = {"entities": {"Q5": {"type": "item", "id": "Q5", "descriptions": {}, "sitelinks": {}}}, "success": 1}
WD_NO_SUCH = {"error": {"code": "no-such-entity", "info": "Could not find an entity with the ID \"Q999999999999\".",
                        "id": "Q999999999999"}, "servedby": "mw-api-ext.eqiad.main"}

PORTISHEAD_WORDS = ("Portishead are an English electronic band formed in 1991 in Bristol. The band comprises Beth "
                    "Gibbons (vocals), Geoff Barrow, and Adrian Utley (guitar). Dave McDonald, an audio engineer who "
                    "helped produce their first two albums, is sometimes regarded as the fourth member.")
DUMMY_WORDS = ("Dummy is the debut studio album by English electronic music band Portishead, released on 22 August "
               "1994 by Go! Beat Records.")


def summary(title: str, words: str, kind: str = "standard") -> dict:
    canonical = title.replace(" ", "_")
    page = f"https://en.wikipedia.org/wiki/{canonical}"
    return {
        "type": kind, "title": title,
        "displaytitle": f"<span lang=\"en\" dir=\"ltr\"><span class=\"mw-page-title-main\">{title}</span></span>",
        "namespace": {"id": 0, "text": ""}, "wikibase_item": "Q191352",
        "titles": {"canonical": canonical, "normalized": title, "display": title},
        "pageid": 87731, "lang": "en", "dir": "ltr", "revision": "1379955213", "timestamp": "2026-10-12T22:39:33Z",
        "description": "English band", "description_source": "local",
        "content_urls": {"desktop": {"page": page, "revisions": f"{page}?action=history"},
                         "mobile": {"page": page}},
        "extract": words,
        #? the HTML twin, which is never what is said
        "extract_html": f"<p><b>{title}</b> <script>alert(1)</script>{words}</p>",
    }


WP_PORTISHEAD = summary("Portishead (band)", PORTISHEAD_WORDS)
WP_DUMMY = summary("Dummy (album)", DUMMY_WORDS)
WP_MISSING = {"status": 404, "type": "Internal error"}

#? Navidrome 0.63's biography, as provider.go leaves it: Last.fm's summary, "<a " made "<a target='_blank' ", its
#? "Read more on Last.fm" still on (0.64's lastfm agent takes it off itself)
ND_BIOGRAPHY = ("Portishead are an English band formed in 1991 in Bristol &amp; named after the nearby town. "
                "<a target='_blank' href=\"https://www.last.fm/music/Portishead\">Read more on Last.fm</a>")
ND_ARTIST_INFO = {"artistInfo2": {"biography": ND_BIOGRAPHY, "musicBrainzId": PORTISHEAD,
                                  "lastFmUrl": "https://www.last.fm/music/Portishead",
                                  "smallImageUrl": "http://navidrome:4533/share/img/x?size=300"}}
ND_ALBUM_INFO = {"albumInfo": {"notes": "Dummy is the debut album by <b>Portishead</b>.", "musicBrainzId": "",
                               "lastFmUrl": "https://www.last.fm/music/Portishead/Dummy"}}


# ----------------------------------------------------------------- the pure rules

def test_the_wikidata_item_comes_from_the_wikidata_link_alone():
    assert D.wikidata_entity(MB_PORTISHEAD["relations"]) == "Q191352"
    assert D.wikidata_entity(MB_DUMMY["relations"]) == "Q911143"
    assert D.wikidata_entity([relation("wikidata", "https://www.wikidata.org/wiki/Q191352/")]) == "Q191352"
    assert D.wikidata_entity([relation("wikidata", "https://www.wikidata.org/wiki/P18"),
                              relation("discogs", "https://www.discogs.com/Q5")]) is None
    assert D.wikidata_entity(None) is None


def test_only_an_english_wikipedia_article_is_a_page():
    assert D.page_title("https://en.wikipedia.org/wiki/Dummy_(album)") == "Dummy (album)"
    assert D.page_title("https://en.wikipedia.org/wiki/Sigur_R%C3%B3s") == "Sigur Rós"
    assert D.page_title("https://en.m.wikipedia.org/wiki/Third_(Portishead_album)") == "Third (Portishead album)"
    #? another language, another site, not an article
    assert [D.page_title(url) for url in (
        "https://fr.wikipedia.org/wiki/Portishead_(groupe)", "https://en.wikipedia.org.evil.example/wiki/X",
        "https://en.wikipedia.org/w/index.php?title=X", "https://en.wikipedia.org/wiki/File:Portishead.jpg",
        "https://en.wikipedia.org/wiki/Special:Random", "https://en.wikipedia.org/wiki/", "not a url", "")] == [None] * 8
    #? a title with a colon in it is still an article
    assert D.page_title("https://en.wikipedia.org/wiki/Mezzanine:_Remastered") == "Mezzanine: Remastered"
    assert D.wikipedia_relation(MB_PORTISHEAD["relations"]) is None
    assert D.wikipedia_relation([relation("wikipedia", "https://en.wikipedia.org/wiki/Dummy_(album)")]) == "Dummy (album)"


def test_the_english_page_is_read_from_wbgetentities():
    assert D.enwiki_title(WD_PORTISHEAD, "Q191352") == "Portishead (band)"
    assert D.enwiki_title(WD_NO_ENGLISH, "Q5") is None
    assert D.enwiki_title(WD_NO_SUCH, "Q999999999999") is None
    assert D.enwiki_title({"entities": {"Q1": {"id": "Q1", "missing": ""}}}, "Q1") is None
    #? a redirected item is answered under the id it became
    assert D.enwiki_title({"entities": {"Q42": WD_DUMMY["entities"]["Q911143"]}}, "Q41") == "Dummy (album)"
    assert D.enwiki_title(None, "Q1") is None and D.enwiki_title({"entities": []}, "Q1") is None


def test_the_subtitle_is_wikidata_s_english_one_line():
    assert D.english_description(WD_PORTISHEAD, "Q191352") == "English band"
    assert D.english_description(WD_DUMMY, "Q911143") == "1994 studio album by Portishead"
    assert D.english_description(WD_NO_ENGLISH, "Q5") is None
    assert D.english_description(WD_NO_SUCH, "Q999999999999") is None and D.english_description(None, "Q1") is None
    #? one line of text, never longer than a line should be
    odd = {"entities": {"Q1": {"id": "Q1", "descriptions": {"en": {"value": " American\nmusical\x07 group "}}}}}
    assert D.english_description(odd, "Q1") == "American musical group"
    long = {"entities": {"Q1": {"id": "Q1", "descriptions": {"en": {"value": "word " * 100}}}}}
    assert len(D.english_description(long, "Q1")) <= D.SUBTITLE_LETTERS + 1
    assert D.english_description({"entities": {"Q1": {"id": "Q1", "descriptions": {"en": {"value": 5}}}}}, "Q1") is None


def test_wikipedia_s_summary_is_its_plain_extract_and_its_page():
    assert D.from_summary(WP_PORTISHEAD, "Portishead (band)") == {
        "text": PORTISHEAD_WORDS, "source": "wikipedia", "url": "https://en.wikipedia.org/wiki/Portishead_(band)"}
    #? not an article - nothing
    assert D.from_summary(summary("Nirvana (disambiguation)", "Nirvana may refer to:", "disambiguation"), "x") is None
    assert D.from_summary({**WP_DUMMY, "extract": "   "}, "Dummy (album)") is None
    assert D.from_summary(WP_MISSING, "x") is None and D.from_summary(None, "x") is None
    #? a page link that isn't English Wikipedia's is made from the title instead
    odd = {**WP_DUMMY, "content_urls": {"desktop": {"page": "javascript:alert(1)"}}}
    assert D.from_summary(odd, "Dummy (album)")["url"] == "https://en.wikipedia.org/wiki/Dummy_(album)"
    assert D.summary_url("Portishead (band)") == "https://en.wikipedia.org/api/rest_v1/page/summary/Portishead_(band)"
    assert D.summary_url("AC/DC") == "https://en.wikipedia.org/api/rest_v1/page/summary/AC%2FDC"


def test_navidrome_s_html_is_read_as_text():
    assert D.plain_text(ND_BIOGRAPHY) == ("Portishead are an English band formed in 1991 in Bristol & named after the "
                                          "nearby town.")
    #? Last.fm's own link, as 0.64's agent matches it, and the tail with a full stop after it
    assert D.plain_text('Words. <a href="https://www.last.fm/music/X">Read more on Last.fm</a>.') == "Words."
    assert D.plain_text("One<br>two<p>three</p><script>alert(1)</script><style>p{}</style>four") == "One two three four"
    assert D.plain_text("<img src=x onerror=alert(1)>Safe &lt;b&gt; text") == "Safe <b> text"
    assert D.plain_text("tab\tand\x07bell\n\nnewlines") == "tab andbell newlines"
    assert D.plain_text("") == "" and D.plain_text(None) == ""
    #? an empty Last.fm stub - only its link - says nothing
    assert D.plain_text('<a href="https://www.last.fm/music/Nobody">Read more on Last.fm</a>') == ""


def test_a_long_text_is_cut_at_a_sentence_else_a_word():
    sentence = "This is one sentence of words. "
    long = sentence * 100
    cut = D.trimmed(long.strip())
    assert len(cut) <= D.MAX_LETTERS and cut.endswith("words.")
    words = "word " * 400
    cut = D.trimmed(words.strip())
    assert len(cut) <= D.MAX_LETTERS + 1 and cut.endswith("word…")
    assert D.trimmed("Short.") == "Short."


def test_navidrome_s_answer_is_its_words_and_last_fm_s_page_only():
    assert D.from_navidrome(ok(**ND_ARTIST_INFO)["subsonic-response"], "biography") == {
        "text": "Portishead are an English band formed in 1991 in Bristol & named after the nearby town.",
        "source": "lastfm", "url": "https://www.last.fm/music/Portishead"}
    assert D.from_navidrome(ND_ALBUM_INFO, "notes") == {
        "text": "Dummy is the debut album by Portishead.", "source": "lastfm", "url": "https://www.last.fm/music/Portishead/Dummy"}
    #? a link anywhere else is not drawn
    for link in ("http://www.last.fm/music/X", "https://evil.example/last.fm", "javascript:alert(1)", ""):
        assert D.from_navidrome({"albumInfo": {"notes": "Words.", "lastFmUrl": link}}, "notes")["url"] is None, link
    assert D.from_navidrome({"artistInfo2": {"biography": ""}}, "biography") is None
    assert D.from_navidrome({}, "biography") is None and D.from_navidrome(None, "notes") is None


def test_a_found_description_stands_a_month_and_none_three_days():
    assert D.is_fresh(True, 0, 30 * 24 * 3600 - 1) and not D.is_fresh(True, 0, 30 * 24 * 3600)
    assert D.is_fresh(False, 0, 3 * 24 * 3600 - 1) and not D.is_fresh(False, 0, 3 * 24 * 3600)


# ----------------------------------------------------------------- the routes

class Answer:
    def __init__(self, payload=None, status_code=200):
        self.payload = payload or {}
        self.status_code = status_code
        self.text = "fake"

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPStatusError("refused", request=None, response=self)  # type: ignore[arg-type]

    def json(self):
        return self.payload


class MusicBrainz:
    """MusicBrainz's lookups by endpoint; every request kept."""

    def __init__(self):
        self.answers = {f"artist/{PORTISHEAD}": MB_PORTISHEAD, f"release-group/{DUMMY}": MB_DUMMY}
        self.calls: list[tuple[str, dict]] = []
        self.down = False

    async def get(self, endpoint, params=None):
        self.calls.append((endpoint, dict(params or {})))
        if self.down:
            return Answer(status_code=403)
        found = self.answers.get(endpoint)
        return Answer(found) if found else Answer({"error": "Not Found"}, status_code=404)


class Wikimedia:
    """Wikidata's wbgetentities and Wikipedia's REST summary, as recorded; every request kept."""

    def __init__(self):
        self.items = {"Q191352": WD_PORTISHEAD, "Q911143": WD_DUMMY, "Q5": WD_NO_ENGLISH}
        self.pages = {"Portishead_(band)": WP_PORTISHEAD, "Dummy_(album)": WP_DUMMY}
        self.requests: list[httpx.Request] = []
        self.down = False
        #? Wikipedia's REST answering every page with this status instead (a 503 while it is overloaded)
        self.pages_status: int | None = None

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        if self.down:
            raise httpx.ConnectError("no route to host")
        if request.url.host == "www.wikidata.org":
            item = parse_qs(urlparse(str(request.url)).query)["ids"][0]
            return httpx.Response(200, json=self.items.get(item, {**WD_NO_SUCH, "error": {**WD_NO_SUCH["error"], "id": item}}))
        if self.pages_status:
            return httpx.Response(self.pages_status, text="Service Unavailable")
        title = request.url.path.rsplit("/", 1)[-1]
        found = self.pages.get(title)
        return httpx.Response(200, json=found) if found else httpx.Response(404, json=WP_MISSING)

    def asked(self) -> list[str]:
        return [f"{request.url.host}{request.url.path}" for request in self.requests]


@pytest.fixture
def env(monkeypatch, tmp_path):
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16))
    monkeypatch.setattr(MusicBrainzClient, "rate_limit", RateLimit())
    monkeypatch.setattr(Config, "MUSICBRAINZ_EMAIL", "james@example.com")
    monkeypatch.setattr(Config, "NAVIDROME_URL", "http://navidrome:4533")
    monkeypatch.setattr(Config, "NAVIDROME_USER", "james")
    monkeypatch.setattr(Config, "NAVIDROME_PASSWORD", "hunter2-very-secret")
    mb_fake = MusicBrainz()
    client = MusicBrainzClient()

    async def get_client():
        return mb_fake

    client.get_client = get_client  # type: ignore[method-assign]

    wiki = Wikimedia()
    wikipedia._client = httpx.AsyncClient(transport=httpx.MockTransport(wiki.handle), follow_redirects=True)

    seen: list[httpx.Request] = []
    nd = {"handler": lambda request: httpx.Response(200, json=failed(70, "Artist not found"))}

    def handle(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return nd["handler"](request)

    navidrome.client = httpx.AsyncClient(transport=httpx.MockTransport(handle), base_url="http://navidrome:4533/rest")

    store = JobStore(str(tmp_path / "deadwax.db"))
    store.init()
    app = start()  # no `with`: no lifespan, nothing connects
    app.state.musicbrainz_client = client
    app.state.store = store

    class Env:
        pass

    e = Env()
    e.app, e.client, e.mb, e.wiki, e.nd, e.seen, e.store = app, TestClient(app), mb_fake, wiki, nd, seen, store
    yield e
    asyncio.run(navidrome.close_client())
    asyncio.run(wikipedia.close_client())
    wikipedia._client = None


def navidrome_calls(env) -> list[tuple[str, dict]]:
    return [(request.url.path.rsplit("/", 1)[-1], {key: values[0] for key, values in parse_qs(request.url.query.decode()).items()
                                                  if key not in ("u", "t", "s", "v", "c", "f")}) for request in env.seen]


ND_WORDS = "Portishead are an English band formed in 1991 in Bristol & named after the nearby town."


def found(text, source, url, subtitle=None, unavailable=False) -> dict:
    return {"text": text, "source": source, "url": url, "subtitle": subtitle, "unavailable": unavailable}


def test_an_artist_s_description_is_navidrome_s_first_with_wikidata_s_subtitle(env):
    env.nd["handler"] = lambda request: httpx.Response(200, json=ok(**ND_ARTIST_INFO))

    answer = env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD, "navidrome_id": "ar-1"})

    assert answer.status_code == 200
    #? James: Last.fm (Navidrome's) first - Wikipedia's words had too, but not said; the subtitle Wikidata's
    assert answer.json() == found(ND_WORDS, "lastfm", "https://www.last.fm/music/Portishead", "English band")
    assert navidrome_calls(env) == [("getArtistInfo2", {"id": "ar-1", "count": "0"})]
    #? MusicBrainz asked what the facts ask (one cache entry between them); Wikidata for the English page and the
    #? English description alone, in one request
    assert env.mb.calls == [(f"artist/{PORTISHEAD}", {"inc": MusicBrainzClient.ARTIST_INC, "fmt": "json"})]
    assert env.wiki.asked() == ["www.wikidata.org/w/api.php", "en.wikipedia.org/api/rest_v1/page/summary/Portishead_(band)"]
    query = parse_qs(urlparse(str(env.wiki.requests[0].url)).query)
    assert {key: value[0] for key, value in query.items()} == {
        "action": "wbgetentities", "ids": "Q191352", "props": "sitelinks|descriptions", "languages": "en",
        "sitefilter": "enwiki", "format": "json"}
    #? deadwax's user agent on every request to Wikimedia - the one MusicBrainz is told
    assert {request.headers["user-agent"] for request in env.wiki.requests} == {Config.musicbrainz_user_agent()}
    assert "james@example.com" in Config.musicbrainz_user_agent()
    #? the whole Wikipedia side kept, Wikipedia's words with it - there for when Navidrome can't say
    kept = asyncio.run(env.store.description_get(f"artist:{PORTISHEAD}"))
    assert (kept["text"], kept["subtitle"]) == (PORTISHEAD_WORDS, "English band")


def test_wikipedia_s_words_when_navidrome_has_none(env):
    answer = env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD, "navidrome_id": "ar-1"})

    assert answer.json() == found(PORTISHEAD_WORDS, "wikipedia", "https://en.wikipedia.org/wiki/Portishead_(band)",
                                  "English band")
    assert navidrome_calls(env) == [("getArtistInfo2", {"id": "ar-1", "count": "0"})]


def test_navidrome_and_the_wikipedia_side_are_asked_at_once(env, monkeypatch):
    """Neither waits for the other: Navidrome's first answer can be slow (it asks its agents), and so can the
    Wikipedia side - both are out before either has answered."""
    out: list[str] = []
    both = asyncio.Event()

    async def navidrome_side(request, kind, navidrome_id):
        out.append("navidrome")
        if len(out) == 2:
            both.set()
        await asyncio.wait_for(both.wait(), 2)
        return {"text": "N.", "source": "lastfm", "url": None}, False

    async def wikipedia_side(request, kind, mbid):
        out.append("wikipedia")
        if len(out) == 2:
            both.set()
        await asyncio.wait_for(both.wait(), 2)
        return {"text": "W.", "url": None, "subtitle": "S"}, False

    monkeypatch.setattr(describe_route, "navidrome_side", navidrome_side)
    monkeypatch.setattr(describe_route, "wikipedia_side", wikipedia_side)
    answer = env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD, "navidrome_id": "ar-1"})
    assert answer.json() == found("N.", "lastfm", None, "S")


def test_an_album_s_is_its_release_group_s_with_url_rels_alone(env):
    answer = env.client.get("/deadwax/describe/album", params={"mbid": DUMMY})

    assert answer.json() == found(DUMMY_WORDS, "wikipedia", "https://en.wikipedia.org/wiki/Dummy_(album)",
                                  "1994 studio album by Portishead")
    assert env.mb.calls == [(f"release-group/{DUMMY}", {"inc": "url-rels", "fmt": "json"})]
    assert env.wiki.asked()[-1] == "en.wikipedia.org/api/rest_v1/page/summary/Dummy_(album)"


def test_an_english_wikipedia_link_is_used_where_there_is_no_wikidata_one(env):
    env.mb.answers[f"artist/{NOBODY}"] = {"id": NOBODY, "name": "X", "relations": [
        relation("wikipedia", "https://en.wikipedia.org/wiki/Portishead_(band)")]}

    said = env.client.get("/deadwax/describe/artist", params={"mbid": NOBODY}).json()
    assert (said["text"], said["subtitle"]) == (PORTISHEAD_WORDS, None), "no Wikidata item: no subtitle"
    assert env.wiki.asked() == ["en.wikipedia.org/api/rest_v1/page/summary/Portishead_(band)"]


def test_an_id_musicbrainz_has_nothing_at_is_asked_once_and_kept_as_none(env):
    """A release group the files' tags name that MusicBrainz doesn't have (a bad tag, one merged away): its 404 is
    MusicBrainz answering - one attempt, not ten through the rate limit, and "none" kept, so no visit asks again."""
    for _ in range(2):
        said = env.client.get("/deadwax/describe/album", params={"mbid": NOBODY})
        assert said.status_code == 200 and said.json() == D.NONE
    assert env.mb.calls == [(f"release-group/{NOBODY}", {"inc": "url-rels", "fmt": "json"})]
    kept = asyncio.run(env.store.description_get(f"album:{NOBODY}"))
    assert kept is not None and kept["text"] is None and kept["subtitle"] is None


def test_an_item_wikidata_does_not_have_is_none_kept(env):
    """MusicBrainz links an item Wikidata no longer has (`no-such-entity`): a definite no, kept - not a failure."""
    env.mb.answers[f"artist/{NOBODY}"] = {"id": NOBODY, "name": "Gone", "relations": [
        relation("wikidata", "https://www.wikidata.org/wiki/Q999999999999")]}

    said = env.client.get("/deadwax/describe/artist", params={"mbid": NOBODY}).json()
    assert said == D.NONE and said["unavailable"] is False
    kept = asyncio.run(env.store.description_get(f"artist:{NOBODY}"))
    assert kept is not None and kept["text"] is None


def test_a_found_description_is_kept_and_asked_nothing_again_after_a_restart_too(env, monkeypatch):
    first = env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD}).json()
    asked = len(env.wiki.requests)
    #? a restart: MusicBrainz's memory gone - the database still holds it
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16))

    assert env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD}).json() == first
    assert len(env.wiki.requests) == asked and len(env.mb.calls) == 1


def test_a_month_on_it_is_asked_again_and_kept_if_asking_fails(env, monkeypatch):
    now = [1_000_000.0]
    monkeypatch.setattr(describe_route.time, "time", lambda: now[0])
    first = env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD}).json()
    now[0] += D.FOUND_FRESH_SECONDS - 60
    env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD})
    assert len(env.wiki.requests) == 2, "still fresh: nothing asked"

    now[0] += 120
    env.wiki.down = True
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16))
    assert env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD}).json() == {**first, "unavailable": True}
    assert len(env.wiki.requests) == 3, "too old: asked again - and Wikipedia away, the old one answered"

    #? Wikipedia back, with new words: they replace the kept ones, kept from now
    env.wiki.down = False
    env.wiki.pages["Portishead_(band)"] = summary("Portishead (band)", "Portishead are a band from Bristol.")
    env.wiki.items["Q191352"] = {"entities": {"Q191352": {**WD_PORTISHEAD["entities"]["Q191352"], "descriptions": {
        "en": {"language": "en", "value": "English trip hop band"}}}}, "success": 1}
    said = env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD}).json()
    assert (said["text"], said["subtitle"], said["unavailable"]) == ("Portishead are a band from Bristol.", "English trip hop band", False)
    kept = asyncio.run(env.store.description_get(f"artist:{PORTISHEAD}"))
    assert (kept["text"], kept["subtitle"], kept["fetched_at"]) == ("Portishead are a band from Bristol.", "English trip hop band", now[0])
    asked = len(env.wiki.requests)
    env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD})
    assert len(env.wiki.requests) == asked, "the new one fresh: nothing asked"


def test_none_is_kept_three_days_and_navidrome_asked_meanwhile(env, monkeypatch):
    now = [1_000_000.0]
    monkeypatch.setattr(describe_route.time, "time", lambda: now[0])
    env.mb.answers[f"artist/{NOBODY}"] = {"id": NOBODY, "name": "Nobody", "relations": [
        relation("wikidata", "https://www.wikidata.org/wiki/Q5")]}

    for _ in range(2):
        assert env.client.get("/deadwax/describe/artist", params={"mbid": NOBODY}).json() == D.NONE
    assert env.wiki.asked() == ["www.wikidata.org/w/api.php"], "an item with no English page: none, kept"
    assert len(env.mb.calls) == 1

    now[0] += D.NONE_FRESH_SECONDS
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16))
    env.client.get("/deadwax/describe/artist", params={"mbid": NOBODY})
    assert len(env.wiki.requests) == 2 and len(env.mb.calls) == 2, "three days on, asked again"


def test_a_subtitle_alone_is_found_and_kept_a_month(env, monkeypatch):
    """An item with an English description but no English page: no words of Wikipedia's, a subtitle all the same -
    found, so kept a month, not three days."""
    now = [1_000_000.0]
    monkeypatch.setattr(describe_route.time, "time", lambda: now[0])
    env.mb.answers[f"artist/{NOBODY}"] = {"id": NOBODY, "name": "Somebody", "relations": [
        relation("wikidata", "https://www.wikidata.org/wiki/Q7")]}
    env.wiki.items["Q7"] = {"entities": {"Q7": {"id": "Q7", "descriptions": {"en": {"value": "Icelandic band"}},
                                                "sitelinks": {}}}, "success": 1}

    assert env.client.get("/deadwax/describe/artist", params={"mbid": NOBODY}).json() == found(None, None, None, "Icelandic band")
    now[0] += D.NONE_FRESH_SECONDS + 60
    monkeypatch.setattr(MusicBrainzClient, "cache", ResponseCache(ttl_seconds=60, max_entries=16))
    env.client.get("/deadwax/describe/artist", params={"mbid": NOBODY})
    assert env.wiki.asked() == ["www.wikidata.org/w/api.php"], "a found subtitle stands past three days"


@pytest.mark.parametrize("away", ["musicbrainz", "wikimedia", "wikidata error", "wikipedia 503"])
def test_a_failure_is_never_kept_nor_an_error(env, away):
    if away == "musicbrainz":
        env.mb.down = True
    elif away == "wikimedia":
        env.wiki.down = True
    elif away == "wikidata error":
        env.wiki.items["Q191352"] = {"error": {"code": "maxlag", "info": "Waiting for a database server"}}
    else:
        env.wiki.pages_status = 503

    answer = env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD})
    #? said as a failure - the app keeps it a moment, never as "none" for its session
    assert answer.status_code == 200 and answer.json() == {**D.NONE, "unavailable": True}
    assert asyncio.run(env.store.description_get(f"artist:{PORTISHEAD}")) is None, "nothing kept of a failure"


def test_navidrome_s_words_still_said_with_wikipedia_away_and_said_unavailable(env):
    env.nd["handler"] = lambda request: httpx.Response(200, json=ok(**ND_ARTIST_INFO))
    env.wiki.down = True

    said = env.client.get("/deadwax/describe/artist", params={"mbid": PORTISHEAD, "navidrome_id": "ar-1"}).json()
    assert said == found(ND_WORDS, "lastfm", "https://www.last.fm/music/Portishead", None, unavailable=True)


def test_wikipedia_without_the_page_is_none_kept(env):
    env.wiki.pages.pop("Dummy_(album)")

    #? no words - the subtitle Wikidata's all the same, and kept
    assert env.client.get("/deadwax/describe/album", params={"mbid": DUMMY}).json() == found(
        None, None, None, "1994 studio album by Portishead")
    kept = asyncio.run(env.store.description_get(f"album:{DUMMY}"))
    assert kept is not None and kept["text"] is None and kept["subtitle"] == "1994 studio album by Portishead"


def test_navidrome_s_biography_by_navidrome_s_id_alone(env):
    env.nd["handler"] = lambda request: httpx.Response(200, json=ok(**ND_ARTIST_INFO))

    answer = env.client.get("/deadwax/describe/artist", params={"navidrome_id": "ar-1"})

    assert answer.json() == found(ND_WORDS, "lastfm", "https://www.last.fm/music/Portishead")
    assert navidrome_calls(env) == [("getArtistInfo2", {"id": "ar-1", "count": "0"})]
    assert env.mb.calls == [] and env.wiki.requests == []


def test_an_album_with_no_musicbrainz_id_has_navidrome_s_notes(env):
    env.nd["handler"] = lambda request: httpx.Response(200, json=ok(**ND_ALBUM_INFO))

    answer = env.client.get("/deadwax/describe/album", params={"navidrome_id": "al-1"})

    assert answer.json()["text"] == "Dummy is the debut album by Portishead."
    assert navidrome_calls(env) == [("getAlbumInfo2", {"id": "al-1"})]
    assert env.mb.calls == [] and env.wiki.requests == []


@pytest.mark.parametrize("navidrome_says, unavailable", [
    ("not found", False), ("empty", False), ("not set up", True), ("unreachable", True)])
def test_navidrome_with_nothing_to_say_is_none(env, monkeypatch, navidrome_says, unavailable):
    if navidrome_says == "not set up":
        monkeypatch.setattr(Config, "NAVIDROME_URL", "")
    elif navidrome_says == "unreachable":
        env.nd["handler"] = lambda request: (_ for _ in ()).throw(httpx.ConnectError("refused"))
    elif navidrome_says == "empty":
        env.nd["handler"] = lambda request: httpx.Response(200, json=ok(artistInfo2={}))

    answer = env.client.get("/deadwax/describe/artist", params={"navidrome_id": "ar-1"})
    #? Navidrome saying it has no such artist, or nothing of them, is a definite none; one it couldn't be asked
    #? (or isn't set up) is said unavailable, so the app asks again soon
    assert answer.status_code == 200 and answer.json() == {**D.NONE, "unavailable": unavailable}


def test_no_id_is_a_422_and_bad_ones_ask_nothing(env):
    assert env.client.get("/deadwax/describe/artist").status_code == 422
    assert env.client.get("/deadwax/describe/album").json()["detail"] == describe_route.NEEDS_AN_ID
    for params in ({"mbid": "portishead"}, {"mbid": PORTISHEAD.upper()}, {"mbid": f"{PORTISHEAD}x"},
                   {"navidrome_id": "x" * (ID_MAX + 1)}, {"navidrome_id": ""}):
        for kind in ("artist", "album"):
            assert env.client.get(f"/deadwax/describe/{kind}", params=params).status_code == 422, (kind, params)
    assert env.mb.calls == [] and env.wiki.requests == [] and env.seen == []
