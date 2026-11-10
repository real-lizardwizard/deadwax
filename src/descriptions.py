"""
A short description of an artist or an album (2.0.13) - the words under the artist page's name and under an
album page's hero, as Apple Music's blurbs. James (2026-10-24): "I want to have the little descriptions for
the artists and albums displayed on their respective pages".

PURE - no I/O, the reason matching.py, editions.py and artists.py are: fetching is
src/api/wikipedia_endpoint.py's, the route src/routes/describe.py's. Two things are said:

THE PARAGRAPH. Where its words come from, in order - James, 2026-10-24, after seeing Dance Gavin Dance from
both: "Last.fm FIRST, Wikipedia (via MusicBrainz) as the fallback - for artists and albums":

  1. NAVIDROME's own (getArtistInfo2's `biography`, getAlbumInfo2's `notes`), which Navidrome fills from its
     metadata agents - Deezer then Last.fm for an artist's (its default agents "deezer,lastfm,listenbrainz"),
     Last.fm alone for an album's, Last.fm only once Navidrome has a Last.fm key (0.64.2 ships none) - asked as
     the signed-in person. It arrives as HTML (Navidrome adds target='_blank' to Last.fm's own link); it is
     read here as TEXT, and Last.fm's "Read more on Last.fm" tail (Navidrome 0.64 removes it; older ones
     don't) taken off. Its link is the answer's `lastFmUrl`.
  2. WIKIPEDIA's summary of the page (its REST `page/summary`: the lead's first paragraph, as plain text),
     reached the way deadwax already reaches artist pictures - the MusicBrainz entity's `wikidata` relation
     (an artist's, or an album's release group's), that item's English Wikipedia page (its `enwiki`
     sitelink). A `wikipedia` relation straight to an English page is used when there is no Wikidata one.
     English only: a French page (Portishead's own `wikipedia` relation is to fr.wikipedia.org) is not said.
  3. Neither: no paragraph.

THE SUBTITLE (James, 2026-10-24, later): Wikidata's one-line English description of the same item
(`descriptions.en` - "English band", "1994 studio album by Portishead"), asked in the same wbgetentities
request as the English page, whichever source the paragraph came from. None when the item has none.

Never HTML: what comes from outside is only ever text by the time it leaves deadwax, and the page draws it
as text.
"""

import html
import re
from html.parser import HTMLParser
from urllib.parse import quote, unquote, urlparse

#? What a description answer is: the paragraph, whose words they are, and the page they came from (the link
#? that credits them - Wikipedia's CC BY-SA asks for it), and Wikidata's one-line subtitle. `source` is
#? "lastfm" (Navidrome's own, its link Last.fm's page) or "wikipedia"; every field None when there is none.
#? `unavailable` is True when a source couldn't be asked just now (MusicBrainz, Wikimedia or Navidrome away):
#? what came is still answered, but the app keeps it only a moment (lib/describe.ts), never for the session.
SOURCES = ("wikipedia", "lastfm")
NONE = {"text": None, "source": None, "url": None, "subtitle": None, "unavailable": False}

#? How long a description kept in the database stands: a found one (words or a subtitle) a month (a Wikipedia
#? lead changes slowly), a "there is none" three days - so an English page written on Wikipedia for an item
#? MusicBrainz already links is seen within days, without asking Wikidata for every page of an unknown band each
#? visit. A Wikidata link added on MusicBrainz itself takes longer: deadwax keeps MusicBrainz's lookups on disk
#? for a month (musicbrainz_cache.py LOOKUP_FRESH_SECONDS), so it is seen once that saved answer is renewed -
#? or at once after Server settings' Clear of MusicBrainz's saved answers.
FOUND_FRESH_SECONDS = 30 * 24 * 3600
NONE_FRESH_SECONDS = 3 * 24 * 3600

#? The most of a description kept: Wikipedia's lead paragraph is a few hundred letters, but Deezer's
#? biography (Navidrome's first agent) is the WHOLE of it. Cut at the last sentence that fits - or, with none
#? past halfway, at the last word, ending in an ellipsis.
MAX_LETTERS = 1500

ENGLISH_WIKIPEDIA = "en.wikipedia.org"
SUMMARY_URL = "https://en.wikipedia.org/api/rest_v1/page/summary/{}"
#? the English page AND the English one-line description, in one request: a few hundred bytes, not the entity
WIKIDATA_ENTITY = ("https://www.wikidata.org/w/api.php?action=wbgetentities&ids={}&props=sitelinks%7Cdescriptions"
                   "&languages=en&sitefilter=enwiki&format=json")
#? the most of a subtitle kept - Wikidata's run to a line ("American musical group; post-hardcore band")
SUBTITLE_LETTERS = 200

#? Last.fm's link at the end of a summary, however Navidrome wrote the tag: `<a href="https://www.last.fm/
#? music/...">Read more on Last.fm</a>` (Last.fm's own) or with Navidrome's target='_blank' before the href
READ_MORE = re.compile(r"\s*<a\b[^>]*>\s*Read more on Last\.fm\s*</a>\.?", re.IGNORECASE)

#? the namespaces a `wikipedia` link could point into that are not an article
NAMESPACES = frozenset({"File", "Image", "Special", "Category", "Talk", "Template", "Help", "Portal", "User", "Wikipedia"})

_ENTITY = re.compile(r"^Q[1-9][0-9]*$")
_SPACES = re.compile(r"\s+")
#? control characters a text could carry - never drawn
_CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def wikidata_entity(relations: list[dict] | None) -> str | None:
    """The Wikidata item an artist or a release group is linked to (its `wikidata` url relation), or None."""
    for relation in relations or []:
        if not isinstance(relation, dict) or relation.get("type") != "wikidata":
            continue
        url = ((relation.get("url") or {}).get("resource") or "").strip()
        entity = url.rstrip("/").rsplit("/", 1)[-1]
        if _ENTITY.match(entity):
            return entity
    return None


def page_title(url: str) -> str | None:
    """An English Wikipedia page's title from its address (`https://en.wikipedia.org/wiki/Dummy_(album)` ->
    `Dummy (album)`), or None for any other address - another language, another site, not a page."""
    try:
        parsed = urlparse((url or "").strip())
    except ValueError:
        return None
    host = (parsed.hostname or "").lower()
    if host not in (ENGLISH_WIKIPEDIA, "en.m.wikipedia.org") or not parsed.path.startswith("/wiki/"):
        return None
    title = unquote(parsed.path[len("/wiki/"):]).replace("_", " ").strip()
    #? a namespace (File:, Special:) is not an article
    if not title or title.split(":", 1)[0] in NAMESPACES and ":" in title:
        return None
    return title


def wikipedia_relation(relations: list[dict] | None) -> str | None:
    """The English Wikipedia page a `wikipedia` url relation points at, when there is one."""
    for relation in relations or []:
        if not isinstance(relation, dict) or relation.get("type") != "wikipedia":
            continue
        title = page_title((relation.get("url") or {}).get("resource") or "")
        if title:
            return title
    return None


def _item(payload: dict | None, entity_id: str) -> dict | None:
    """The one item in wbgetentities' answer - None for a missing item (`"missing": ""`) or an error answer. A
    redirected item is answered under its new id, so the one entity there is read when the asked one isn't."""
    entities = (payload or {}).get("entities") if isinstance(payload, dict) else None
    if not isinstance(entities, dict) or not entities:
        return None
    entity = entities.get(entity_id)
    if not isinstance(entity, dict) and len(entities) == 1:
        entity = next(iter(entities.values()))
    if not isinstance(entity, dict) or "missing" in entity:
        return None
    return entity


def enwiki_title(payload: dict | None, entity_id: str) -> str | None:
    """
    The English Wikipedia page of a Wikidata item, from wbgetentities' answer (WIKIDATA_ENTITY):
    `{"entities": {"Q191352": {"sitelinks": {"enwiki": {"title": "Portishead (band)"}}}}}`. None for an item
    with no English page, a missing item or an error answer.
    """
    entity = _item(payload, entity_id)
    if entity is None:
        return None
    link = (entity.get("sitelinks") or {}).get("enwiki")
    title = link.get("title") if isinstance(link, dict) else None
    return title.strip() if isinstance(title, str) and title.strip() else None


def english_description(payload: dict | None, entity_id: str) -> str | None:
    """
    Wikidata's one-line English description of an item - the page's subtitle - from wbgetentities' answer:
    `{"entities": {"Q911143": {"descriptions": {"en": {"language": "en", "value": "1994 studio album by
    Portishead"}}}}}`. Text only, one line, at most SUBTITLE_LETTERS; None when the item has none.
    """
    entity = _item(payload, entity_id)
    found = ((entity or {}).get("descriptions") or {}).get("en") if entity else None
    value = found.get("value") if isinstance(found, dict) else None
    text = trimmed(_SPACES.sub(" ", _CONTROL.sub("", value)).strip(), SUBTITLE_LETTERS) if isinstance(value, str) else ""
    return text or None


def summary_url(title: str) -> str:
    """Wikipedia's REST summary for a page title, the title as the page's own address writes it."""
    return SUMMARY_URL.format(quote(title.replace(" ", "_"), safe="()!,'*-._~"))


def page_url(title: str) -> str:
    return f"https://{ENGLISH_WIKIPEDIA}/wiki/{quote(title.replace(' ', '_'), safe='()!,*-._~')}"


def from_summary(payload: dict | None, title: str) -> dict | None:
    """
    A description from Wikipedia's REST summary: its `extract` (plain text - never `extract_html`) and the
    page's own address (`content_urls.desktop.page`, else made from the title). None for a page that isn't
    an article (`type` "disambiguation", "no-extract", "mainpage") or has no words.
    """
    if not isinstance(payload, dict) or payload.get("type") != "standard":
        return None
    text = clean_text(payload.get("extract"))
    if not text:
        return None
    url = (((payload.get("content_urls") or {}).get("desktop") or {}).get("page") or "").strip()
    if not url.startswith(f"https://{ENGLISH_WIKIPEDIA}/"):
        url = page_url(payload.get("title") or title)
    return {"text": text, "source": "wikipedia", "url": url}


class _Text(HTMLParser):
    """Only the text of an HTML fragment - every tag dropped, its words kept, a <br> or a <p> a space."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.skipping = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.skipping += 1
        elif tag in ("br", "p", "div", "li"):
            self.parts.append(" ")

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self.skipping:
            self.skipping -= 1
        elif tag in ("p", "div", "li"):
            self.parts.append(" ")

    def handle_data(self, data):
        if not self.skipping:
            self.parts.append(data)


def plain_text(fragment: str | None) -> str:
    """An HTML fragment (Navidrome's biography or notes) as plain text: Last.fm's "Read more on Last.fm"
    taken off, every tag dropped, its entities read, the spaces one."""
    if not isinstance(fragment, str) or not fragment.strip():
        return ""
    reader = _Text()
    try:
        reader.feed(READ_MORE.sub("", fragment))
        reader.close()
    except Exception:
        #? a fragment the parser chokes on is still not drawn as HTML: its tags stripped the blunt way
        return clean_text(html.unescape(re.sub(r"<[^>]*>", " ", fragment)))
    return clean_text("".join(reader.parts))


def clean_text(text) -> str:
    """One line of words: control characters out, every run of spaces one, cut at MAX_LETTERS."""
    if not isinstance(text, str):
        return ""
    return trimmed(_SPACES.sub(" ", _CONTROL.sub("", text)).strip())


def trimmed(text: str, limit: int = MAX_LETTERS) -> str:
    """At most `limit` letters: cut at the last sentence that fits, else at the last word with an ellipsis."""
    if len(text) <= limit:
        return text
    head = text[:limit]
    stop = max(head.rfind(". "), head.rfind("! "), head.rfind("? "))
    if stop >= limit // 2:
        return head[:stop + 1]
    space = head.rfind(" ")
    return (head[:space] if space > 0 else head).rstrip(" ,;:-") + "…"


def from_navidrome(info: dict | None, field: str) -> dict | None:
    """
    A description from Navidrome's getArtistInfo2 (`field` "biography") or getAlbumInfo2 ("notes") answer,
    the body inside subsonic-response: `{"artistInfo2": {"biography": ..., "lastFmUrl": ...}}`. Its link is
    `lastFmUrl` when it is a Last.fm address, else none.
    """
    key = "artistInfo2" if field == "biography" else "albumInfo"
    body = (info or {}).get(key) if isinstance(info, dict) else None
    if not isinstance(body, dict):
        return None
    text = plain_text(body.get(field))
    if not text:
        return None
    link = (body.get("lastFmUrl") or "").strip()
    host = (urlparse(link).hostname or "").lower() if link else ""
    url = link if link.startswith("https://") and (host == "last.fm" or host.endswith(".last.fm")) else None
    return {"text": text, "source": "lastfm", "url": url}


def is_fresh(found: bool, fetched_at: float, now: float) -> bool:
    """Whether a kept description (or a kept "none") still stands."""
    return now - fetched_at < (FOUND_FRESH_SECONDS if found else NONE_FRESH_SECONDS)


def found_in(row: dict | None) -> bool:
    """Whether a kept row holds anything - Wikipedia's words, or Wikidata's subtitle."""
    return bool(row and (row.get("text") or row.get("subtitle")))


def answer_of(row: dict | None, paragraph: dict | None = None, unavailable: bool = False) -> dict:
    """
    The route's answer: the paragraph - Navidrome's (`paragraph`) when it said one, else the kept row's
    Wikipedia words - and the row's subtitle, whichever the paragraph is.
    """
    answer = dict(NONE)
    if paragraph:
        answer.update(text=paragraph["text"], source=paragraph["source"], url=paragraph.get("url"))
    elif row and row.get("text"):
        answer.update(text=row["text"], source="wikipedia", url=row.get("url"))
    answer["subtitle"] = (row or {}).get("subtitle") or None
    answer["unavailable"] = bool(unavailable)
    return answer
