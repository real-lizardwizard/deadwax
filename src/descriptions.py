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

WITH A LASTFM_API_KEY (2.1.42, S3 - notes/lastfm.md; James's order of 2026-10-24, "Last.fm FIRST, Wikipedia (via
MusicBrainz) as the fallback", now met by deadwax's own ask): LAST.FM's own words first - an artist's artist.getInfo
bio, an album's album.getInfo wiki (from_lastfm) - then Wikipedia's, then Navidrome's (answer_lastfm_first). Without a
key the order above stands, and nothing of it changes.

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

from src.lastfm import lastfm_url, whole

#? What a description answer is: the paragraph, whose words they are, and the page they came from (the link
#? that credits them - Wikipedia's CC BY-SA asks for it), and Wikidata's one-line subtitle. `source` is
#? "lastfm" (Navidrome's own, its link Last.fm's page - or, since 2.1.42, Last.fm's own) or "wikipedia"; every field
#? None when there is none.
#? `unavailable` is True when a source couldn't be asked just now (MusicBrainz, Wikimedia or Navidrome away - and
#? since 2.1.42 Last.fm, away or refusing the key):
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

#? (2.1.42) The sentence Last.fm ends every bio and album wiki with, after its "Read more on Last.fm" link - as the
#? recordings have it (tests/fixtures/lastfm/recorded/, 2026-11-25: all three artists' content and Dummy's), any case,
#? any spaces. Never drawn: the link under the words credits Last.fm already
LICENCE = re.compile(r"\s*User-contributed\s+text\s+is\s+available\s+under\s+the\s+Creative\s+Commons\s+By-SA\s+"
                     r"License;\s+additional\s+terms\s+may\s+apply\.?", re.IGNORECASE)
#? (2.1.42) A Last.fm page for several artists of one name. WRITTEN FROM THE DESIGN (deadwax-plans/lastfm.md 2.8) AND
#? THE REVIEW: no recording holds one. Its first words say so - artists, bands or acts (plural, or "more than one")
#? that share a NAME: "There are several different artists with this name:", "There is more than one artist named
#? ...", "There were two acts by this name". Never artists doing anything else: "There were two band members in the
#? first line-up", "There are 18 artists on this compilation", "There are many acts of kindness" are a bio's
_WHO = r"(?:artist|band|act|group|musician|singer|rapper|project)"
DISAMBIGUATION = re.compile(
    rf"there\s+(?:are|is|were|have\s+been)\s+(?:more\s+than\s+one\s+{_WHO}|[^.:;\n]{{0,60}}?\b{_WHO}s)\s+"
    r"(?:(?:with|by|of|under|sharing|using|going\s+by)\s+(?:this|that|the\s+same|one|a)\s+name\b|named\b|called\b)",
    re.IGNORECASE)
#? ... or a page numbered from its start - "1) ..." first (after a heading line at most, "Several artists:"), then
#? "2) ..." - read with its lines, before they are made one
NUMBERED = re.compile(r"\s*(?:[^\n]{0,120}:[ \t]*\n\s*)?1([.)])\s.*?\s2\1\s", re.DOTALL)
#? an end a sentence can have: its stop, then any closing quote or bracket
_SENTENCE_END = re.compile(r"[.!?][\"')\]]*$")
#? a tag the keeping's cut went through, at the very end
_HALF_A_TAG = re.compile(r"<[^>]*$")
#? the blank line between two of Last.fm's paragraphs
_PARAGRAPHS = re.compile(r"\n\s*\n")
#? (2.1.42) a list, as _prose() knows one: a paragraph of LIST_LINES lines or more, two in three of them short (at most
#? LIST_LINE_LETTERS) and ending no sentence - Dance Gavin Dance's discography is 26 such lines, 62 letters at most
LIST_LINES = 3
LIST_LINE_LETTERS = 80
#? the prose a list must come after to end the words: after less ("Mogwai.") the words go on past it
PROSE_BEFORE_A_LIST = 200

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
    text = (trimmed(_SPACES.sub(" ", _CONTROL.sub("", whole(value))).strip(), SUBTITLE_LETTERS)
            if isinstance(value, str) else "")
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
    return clean_text(_unmarked(fragment))


def _unmarked(fragment: str | None) -> str:
    """An HTML fragment's text, not yet cleaned or cut: Last.fm's "Read more on Last.fm" taken off, every tag
    dropped, its entities read."""
    if not isinstance(fragment, str) or not fragment.strip():
        return ""
    reader = _Text()
    try:
        reader.feed(READ_MORE.sub("", fragment))
        reader.close()
    except Exception:
        #? a fragment the parser chokes on is still not drawn as HTML: its tags stripped the blunt way
        return html.unescape(re.sub(r"<[^>]*>", " ", fragment))
    return "".join(reader.parts)


def clean_text(text) -> str:
    """One line of words: control characters out, a lone surrogate U+FFFD (lastfm.whole: no UTF-8 carries one -
    2.1.43's review), every run of spaces one, cut at MAX_LETTERS."""
    if not isinstance(text, str):
        return ""
    return trimmed(_SPACES.sub(" ", _CONTROL.sub("", whole(text))).strip())


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
    #? (2.1.41) the one rule for a Last.fm address, src/lastfm.py's: https, on last.fm or a host under it
    return {"text": text, "source": "lastfm", "url": lastfm_url(body.get("lastFmUrl"))}


def from_lastfm(body: dict | None, kind: str) -> dict | None:
    """
    A description from Last.fm's own answer (2.1.42, S3), as deadwax keeps it - artist.getInfo's
    (src/lastfm.py artist_info: `{"url", "listeners", "bio": {"summary", "content"}}`, `kind` "artist") or
    album.getInfo's (album_info: `{"url", "wiki": {...}}`, "album"):

      - the words: the bio's or the wiki's `content`, else its `summary` - HTML, as Last.fm wrote it;
      - cut at Last.fm's own "Read more on Last.fm" link (the last one): what follows it is Last.fm's footer -
        in every recording (tests/fixtures/lastfm/recorded/, 2026-11-25) the content ends `...Read more on
        Last.fm</a>. User-contributed text is available under the Creative Commons By-SA License; additional
        terms may apply.`, and the summary at the link (an album's with a full stop after it);
      - that licence sentence dropped wherever it is anyway (LICENCE), then read as text (plain_text's way);
      - its prose only: the paragraphs before the first list that follows a real amount of prose (_prose - a
        discography, a line-up);
      - words the keeping cut short - no link in them: S2 keeps a content's first BIO_MAX letters - end at their
        last whole sentence (an_end());
      - then clean_text(), cut at MAX_LETTERS.

    None for no words (Last.fm's empty page is its link alone: "Tame Impla" in the recordings) or a
    disambiguation page (DISAMBIGUATION by its first words, NUMBERED by its lines). `url` is the answer's own Last.fm
    page, https on last.fm only
    (lastfm_url) - its link reads "More on Last.fm", as Navidrome's does.
    """
    if not isinstance(body, dict):
        return None
    words = body.get("bio" if kind == "artist" else "wiki")
    words = words if isinstance(words, dict) else {}
    field, text = None, ""
    for field in (words.get("content"), words.get("summary")):
        text = _lastfm_words(field)
        if text:
            break
    if not text or DISAMBIGUATION.match(text) or NUMBERED.match(_unmarked(field)):
        return None
    return {"text": text, "source": "lastfm", "url": lastfm_url(body.get("url"))}


def _lastfm_words(fragment) -> str:
    """One of Last.fm's fields (a content or a summary) as from_lastfm() says it - "" for none."""
    if not isinstance(fragment, str):
        return ""
    ends = list(READ_MORE.finditer(fragment))
    if ends:
        fragment = fragment[:ends[-1].start()]
    else:
        #? cut short: a tag the cut went through is no tag - dropped here, whatever the parser makes of it (3.12.13's
        #? and 3.14.7's html.parser drop it themselves; this doesn't rest on that)
        fragment = _HALF_A_TAG.sub("", fragment)
    text, stopped = _prose(LICENCE.sub(" ", _unmarked(fragment)))
    text = _SPACES.sub(" ", _CONTROL.sub("", text)).strip()
    return clean_text(text if ends or stopped else an_end(text))


def _prose(text: str) -> tuple[str, bool]:
    """
    A Last.fm text's prose: its paragraphs (Last.fm parts them with a blank line) up to the first list (_a_list) that
    follows at least PROSE_BEFORE_A_LIST letters of them - as Dance Gavin Dance's bio has "Discography:", "Band
    members:" and the rest after its two paragraphs of prose (recorded 2026-11-25), which as one paragraph would read
    "... Discography: November 14, 2006 - Whatever I Say Is Royal Ocean May 15, 2007 - ...". And whether it stopped at
    one: the words then end where a paragraph does, whatever the keeping cut after them. A line break inside prose
    is no list, and a list after a line or two ("Mogwai.") doesn't end the words there; a text whose first paragraph
    is a list is as it was.
    """
    paragraphs = _PARAGRAPHS.split(text)
    for at, paragraph in enumerate(paragraphs):
        if at and _a_list(paragraph):
            before = " ".join(paragraphs[:at])
            if len(_SPACES.sub(" ", before).strip()) >= PROSE_BEFORE_A_LIST:
                return before, True
    return text, False


def _a_list(paragraph: str) -> bool:
    """A paragraph that is a list: LIST_LINES lines or more, two in three of them short and ending no sentence -
    "Discography:", "November 14, 2006 - Whatever I Say Is Royal Ocean", "Jon Mess - vocals (2005-2012)"."""
    lines = [line.strip() for line in paragraph.split("\n") if line.strip()]
    listed = sum(len(line) <= LIST_LINE_LETTERS and not _SENTENCE_END.search(line) for line in lines)
    return len(lines) >= LIST_LINES and 3 * listed >= 2 * len(lines)


def an_end(text: str) -> str:
    """Words cut short, ended where a sentence does: at the last whole sentence (in the second half), else at the
    last word with an ellipsis - trimmed()'s rule. Words that already end a sentence are as they were."""
    if len(text) < 2 or _SENTENCE_END.search(text):
        return text
    return trimmed(text, len(text) - 1)


def answer_lastfm_first(heard: dict | None, row: dict | None, said: dict | None, unavailable: bool = False) -> dict:
    """
    The route's answer with a LASTFM_API_KEY (2.1.42): Last.fm's own words (`heard`, from_lastfm) first, else the
    kept row's Wikipedia words, else Navidrome's (`said`) - and the row's subtitle, whichever the paragraph is.
    Without a key the route answers answer_of(), as it always did.
    """
    if heard:
        return answer_of(row, heard, unavailable)
    if row and row.get("text"):
        return answer_of(row, None, unavailable)
    return answer_of(row, said, unavailable)


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
