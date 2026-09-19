"""
What an artist page shows, and where artist images come from.

PURE - no I/O, so it is testable without a network, the same reason matching.py and
editions.py are. Fetching lives in src/api/artist_images_endpoint.py and writing in
src/artist_art.py.

**MusicBrainz hosts no artist images at all.** The Cover Art Archive is releases only, and
what musicbrainz.org itself draws at the top of an artist page is a Wikimedia Commons file
reached through that artist's Wikidata link. So there are three sources, and the one that
actually has the pieces an artist page is made of is the one that needs a key:

  - the artist's own `image` RELATION, where an editor has added one. It points at a Commons
    file PAGE rather than at an image, so it only becomes a picture through Special:FilePath.
    Present for some artists and not others - Tame Impala and Portishead have one, Radiohead
    does not.
  - Wikidata, found through the artist's `wikidata` relation: P18 is the image, P154 the logo.
    Free, no key, and every Commons file states its own licence.
  - TheAudioDB, keyed by the same MusicBrainz artist id, which is the only one of the three
    carrying banners, backgrounds, transparent logos and wide thumbs. It needs an API key, so
    everything here treats it as optional and the page still works without it.
"""

import unicodedata
from urllib.parse import quote, urlparse

#? The filename STEM each kind is written under. The square one is `artist`, and that is the
#? whole reason this lands anywhere useful: **Navidrome reads it with no configuration at all**,
#? its ArtistArtPriority defaulting to "artist.*, album/artist.*, external". Writing the square
#? as `folder.*` instead - which is what Jellyfin and Kodi call an artist thumb - would be
#? invisible to Navidrome, and worse, `folder.*` is in Navidrome's COVER ART priority, so in any
#? folder that turned out to hold audio it would be read as that album's cover.
#?
#?   artist     Navidrome's artist image; Kodi and Jellyfin read it too
#?   banner     Kodi and Jellyfin
#?   logo       Jellyfin's logo; Kodi maps logo -> clearlogo
#?   fanart     Kodi's fanart, and one of Jellyfin's accepted backdrop names (its own docs use
#?              `fanart.jpg` for the first backdrop), so one file serves both
#?   landscape  Kodi's landscape, Jellyfin's thumb
#?   clearart   Kodi only, and harmless elsewhere
#?
#? Navidrome displays NONE of the five below the first: it has one artist image and no concept
#? of a banner or a logo. They are here because jimbrainz's own artist page is made of them, and
#? because anything else pointed at the same library can use them.
#?
#? The EXTENSION is whatever was actually fetched, as save_cover_art does it - every one of
#? these readers matches on the stem, and a PNG named .jpg is a lie on disk.
ARTIST_ART_STEMS = {
    "thumb": "artist",
    "banner": "banner",
    "logo": "logo",
    "fanart": "fanart",
    "landscape": "landscape",
    "clearart": "clearart",
}

#? display order, and the order the picker offers them in: the two most people want first
ARTIST_ART_KINDS = ("thumb", "banner", "fanart", "logo", "landscape", "clearart")

KIND_LABELS = {
    "thumb": "Square image",
    "banner": "Banner",
    "fanart": "Background",
    "logo": "Logo",
    "landscape": "Wide image",
    "clearart": "Clear art",
}

#? Which source to believe when two offer the same kind. fanart.tv leads because its artwork is
#? voted on by the people using it, and this asks for the most-liked of each kind; TheAudioDB's art
#? - cropped square, banner-shaped, transparent where it should be - while a Commons file is a
#? photograph of a band on a stage, which is the right fallback and the wrong first choice.
#? Between the two Commons routes, an `image` relation was put on that artist by a MusicBrainz
#? editor; P18 is Wikidata's idea of the same thing and is occasionally a different person.
SOURCE_ORDER = ("fanarttv", "theaudiodb", "musicbrainz", "wikidata")

COMMONS_HOSTS = {"commons.wikimedia.org", "commons.m.wikimedia.org"}

#? What Special:FilePath is asked for when an image is going to be looked at rather than
#? written. Commons originals are frequently 20 MB scans.
PREVIEW_WIDTH = 600

#? And what to ask for when it is going to be kept. Big enough to sit behind an artist page,
#? small enough not to pull a gatefold scan.
SAVE_WIDTH = 1200

#? How far below the original a thumbnail has to be asked for. MediaWiki will not upscale, so a
#? width at or near the original's resolves to the ORIGINAL - and that is the one thing
#? upload.wikimedia.org refuses a robot. Measured on a 367px-wide file: 300 serves, 366 does not.
THUMB_HEADROOM = 0.9


def safe_thumb_width(original_width: int, want: int = PREVIEW_WIDTH, vector: bool = False) -> int:
    """
    A width Commons will actually answer with a thumbnail.

    Wikimedia serves thumbnails to anything that identifies itself politely, and refuses
    ORIGINALS with "Please honor our robot policy" - so every Commons image here has to be
    fetched as a thumbnail. The catch is that MediaWiki does not upscale: ask for 600 of a file
    that is 367 wide and it hands back the original, which is refused. So the width asked for
    stays under the original's, with room to spare for its rounding.

    A VECTOR has no such limit - an SVG is rasterised at whatever width is asked for, and comes
    back as a PNG - so a logo is not shrunk to the nominal size Commons reports for it.
    """
    if vector:
        return want

    if original_width <= 0:
        return want

    return max(64, min(want, int(original_width * THUMB_HEADROOM)))


def commons_file_url(title: str, width: int | None = None) -> str:
    """
    A direct URL for a Commons file, by its page title.

    Special:FilePath redirects to the file itself, which is what makes this usable without
    asking the Commons API where the bytes live. `width` asks for a thumbnail instead of the
    original - the page wants 600px, not a 20 MB scan of a gatefold.
    """
    name = title.split(":", 1)[-1].strip().replace(" ", "_")
    url = f"https://commons.wikimedia.org/wiki/Special:FilePath/{quote(name)}"
    return f"{url}?width={width}" if width else url


def commons_title(url: str) -> str | None:
    """
    The `File:...` title inside a Commons URL, or None if that is not what this URL is.

    An `image` relation is a link to a file PAGE, and only Commons pages can be turned into a
    picture this way. Anything else - a band's own website, a dead image host - is left alone
    rather than guessed at.
    """
    if not url:
        return None

    parsed = urlparse(url)
    if parsed.netloc not in COMMONS_HOSTS:
        return None

    path = parsed.path
    for prefix in ("/wiki/File:", "/wiki/Special:FilePath/"):
        if path.startswith(prefix):
            title = path[len(prefix):]
            return title or None

    return None


def _candidate(kind: str, url: str, source: str, label: str, preview: str | None = None) -> dict:
    return {
        "kind": kind,
        "url": url,
        #? what the browser is shown, which for Commons is a thumbnail rather than the original
        "preview": preview or url,
        "source": source,
        "label": label,
    }


def credit_name(credit: list[dict] | None) -> str:
    """
    An artist credit as MusicBrainz itself renders it.

    The join phrases ARE the punctuation: a split release is "A / B", a collaboration "A & B",
    a guest spot "A feat. B". Joining the names on ", " instead - which is what jimbrainz did
    everywhere until now - invents punctuation MusicBrainz did not use and flattens a duet into
    what reads as a list of two separate acts.
    """
    parts = []

    for entry in credit or []:
        name = entry.get("name") or (entry.get("artist") or {}).get("name") or ""
        if name:
            parts.append(f"{name}{entry.get('joinphrase') or ''}")

    return "".join(parts).strip()


def credit_ids(credit: list[dict] | None) -> list[str]:
    """
    Every MusicBrainz artist id in a credit, in the order credited.

    A list rather than one id because a credit genuinely can be several artists, and the first
    of them is not "the" artist - on a split release it is simply whoever is printed first.
    """
    ids: list[str] = []

    for entry in credit or []:
        mbid = (entry.get("artist") or {}).get("id")
        if mbid and mbid not in ids:
            ids.append(mbid)

    return ids


def wikidata_id(relations: list[dict] | None) -> str | None:
    """The artist's Wikidata id, from its `wikidata` relation."""
    for relation in relations or []:
        if relation.get("type") != "wikidata":
            continue
        url = (relation.get("url") or {}).get("resource", "")
        entity = url.rstrip("/").rsplit("/", 1)[-1]
        if entity.startswith("Q"):
            return entity

    return None


def from_relations(relations: list[dict] | None) -> list[dict]:
    """Image candidates from MusicBrainz's own `image` relations."""
    found = []

    for relation in relations or []:
        if relation.get("type") != "image":
            continue
        url = (relation.get("url") or {}).get("resource", "")
        title = commons_title(url)
        if title:
            found.append(_candidate(
                "thumb", commons_file_url(title), "musicbrainz", "MusicBrainz image",
                commons_file_url(title, PREVIEW_WIDTH),
            ))

    return found


def from_wikidata(entity: dict | None) -> list[dict]:
    """
    Image candidates from a Wikidata entity: P18 the image, P154 the logo.

    The entity is passed in as fetched, so this stays pure. Claims that are missing, empty or
    of the wrong shape are skipped rather than crashed on - Wikidata is edited by hand and a
    claim can be deprecated, novalue, or a string where a file name was expected.
    """
    claims = ((entity or {}).get("claims") or {})
    found = []

    for prop, kind, label in (("P18", "thumb", "Wikidata image"), ("P154", "logo", "Wikidata logo")):
        for claim in claims.get(prop) or []:
            value = ((claim.get("mainsnak") or {}).get("datavalue") or {}).get("value")
            if isinstance(value, str) and value.strip():
                found.append(_candidate(
                    kind, commons_file_url(value), "wikidata", label,
                    commons_file_url(value, PREVIEW_WIDTH),
                ))

    return found


#? TheAudioDB's field names, in the order the picker shows them. The numbered fanart fields are
#? alternates rather than extra kinds: one background is written, and which one is a choice.
THEAUDIODB_FIELDS = (
    ("strArtistThumb", "thumb", "Thumb"),
    ("strArtistBanner", "banner", "Banner"),
    ("strArtistFanart", "fanart", "Background"),
    ("strArtistFanart2", "fanart", "Background 2"),
    ("strArtistFanart3", "fanart", "Background 3"),
    ("strArtistFanart4", "fanart", "Background 4"),
    ("strArtistLogo", "logo", "Logo"),
    ("strArtistClearart", "clearart", "Clear art"),
    ("strArtistWideThumb", "landscape", "Wide thumb"),
    ("strArtistCutout", "thumb", "Cutout"),
)


def from_theaudiodb(row: dict | None) -> list[dict]:
    """Image candidates from one TheAudioDB artist row."""
    found = []

    for field, kind, label in THEAUDIODB_FIELDS:
        url = (row or {}).get(field)
        if isinstance(url, str) and url.strip():
            found.append(_candidate(kind, url.strip(), "theaudiodb", f"TheAudioDB {label}"))

    return found


#? fanart.tv's fields, and what each is to jimbrainz. The HD logo comes before the plain one so
#? that when both exist the better is offered first; 4K backgrounds are offered alongside the
#? ordinary ones rather than instead of them, being several megabytes each.
FANARTTV_FIELDS = (
    ("artistthumb", "thumb", "Thumb"),
    ("musicbanner", "banner", "Banner"),
    ("artistbackground", "fanart", "Background"),
    ("artist4kbackground", "fanart", "Background 4K"),
    ("hdmusiclogo", "logo", "HD logo"),
    ("musiclogo", "logo", "Logo"),
)

#? How many of any one kind to take. fanart.tv can hold a dozen backgrounds for a popular band,
#? and a picker listing all of them is a picker nobody reads to the end.
FANARTTV_PER_KIND = 4


def _likes(image: dict) -> int:
    """fanart.tv reports likes as a string, and sometimes not at all."""
    try:
        return int(image.get("likes") or 0)
    except (TypeError, ValueError):
        return 0


def from_fanarttv(payload: dict | None) -> list[dict]:
    """
    Image candidates from one fanart.tv music response.

    Sorted by what people voted for. fanart.tv is the one source here whose pictures were put
    there BY the people using them in media centres - so "most liked" is a real signal about
    which background belongs behind an artist, rather than whichever happened to be uploaded
    first, which is the best any of the others can offer.
    """
    found = []

    for field, kind, label in FANARTTV_FIELDS:
        images = (payload or {}).get(field)
        if not isinstance(images, list):
            continue

        for image in sorted(images, key=_likes, reverse=True)[:FANARTTV_PER_KIND]:
            url = (image or {}).get("url")
            if isinstance(url, str) and url.strip():
                likes = _likes(image)
                found.append(_candidate(
                    kind, url.strip(), "fanarttv",
                    f"fanart.tv {label}" + (f" ({likes})" if likes else ""),
                ))

    return found


def best_per_kind(candidates: list[dict]) -> dict:
    """
    One candidate per kind - what "get everything" would write.

    First by SOURCE_ORDER, then by the order the source offered them, which for TheAudioDB puts
    the plain thumb ahead of the cutout and the first background ahead of its alternates.
    """
    best: dict[str, dict] = {}

    for index, candidate in enumerate(candidates):
        kind = candidate["kind"]
        rank = (SOURCE_ORDER.index(candidate["source"])
                if candidate["source"] in SOURCE_ORDER else len(SOURCE_ORDER), index)
        if kind not in best or rank < best[kind]["_rank"]:
            best[kind] = {**candidate, "_rank": rank}

    return {kind: {k: v for k, v in c.items() if k != "_rank"} for kind, c in best.items()}


#? Relations worth putting on the page, and what to call each group. MusicBrainz carries far
#? more than this per artist (six streaming services, three lyric sites) and a page listing all
#? of them is a page nobody reads.
LINK_GROUPS = {
    "official homepage": "Official site",
    "social network": "Social",
    "bandcamp": "Bandcamp",
    "soundcloud": "SoundCloud",
    "youtube": "YouTube",
    "wikidata": "Wikidata",
    "discogs": "Discogs",
    "last.fm": "Last.fm",
    "allmusic": "AllMusic",
    "lyrics": "Lyrics",
    "purchase for mail-order": "Merch",
}


#? Hosts whose name isn't simply their domain's first word. Everything else is title-cased from
#? the domain, which gets Bandcamp, Soundcloud and the rest right without a list to maintain.
SOCIAL_NAMES = {
    "twitter.com": "Twitter",
    "x.com": "X",
    "bsky.app": "Bluesky",
    "last.fm": "Last.fm",
    "vk.com": "VK",
}


def _host_label(url: str) -> str:
    """What to call a link, from where it goes."""
    host = urlparse(url).netloc.lower()
    host = host[4:] if host.startswith("www.") else host
    return SOCIAL_NAMES.get(host) or (host.split(".")[0].capitalize() if host else "Link")


def artist_links(relations: list[dict] | None) -> list[dict]:
    """
    The artist's links, grouped and de-duplicated, in LINK_GROUPS order.

    "Social network" covers every one of them in MusicBrainz's vocabulary, so a band with a
    Twitter, a Facebook and an Instagram got three links all labelled "Social" and no way to
    tell which was which. Those are named after where they actually go.
    """
    seen: set[str] = set()
    links = []

    for wanted, label in LINK_GROUPS.items():
        for relation in relations or []:
            if relation.get("type") != wanted:
                continue
            url = (relation.get("url") or {}).get("resource", "")
            if url and url not in seen:
                seen.add(url)
                links.append({"label": _host_label(url) if wanted == "social network" else label,
                              "url": url})

    return links


def artist_members(relations: list[dict] | None) -> list[dict]:
    """
    Who is in the band, past and present.

    A "member of band" relation hangs off both sides, so direction is what says which way round
    this one reads: backward means the other artist is a member of THIS one, which is the case
    worth showing on a band's page.
    """
    members = []

    for relation in relations or []:
        if relation.get("type") != "member of band" or relation.get("direction") != "backward":
            continue

        artist = relation.get("artist") or {}
        if not artist.get("name"):
            continue

        members.append({
            "name": artist["name"],
            "mbid": artist.get("id"),
            "began": relation.get("begin"),
            "ended": relation.get("end"),
            "current": not relation.get("ended"),
            "roles": [a for a in (relation.get("attributes") or []) if isinstance(a, str)],
        })

    #? current line-up first, then by when they joined; an unknown start date sinks
    members.sort(key=lambda m: (not m["current"], m["began"] or "9999"))
    return members


#? ── Finding an artist by a name that is no longer theirs ────────────────────────────────────
#?
#? MusicBrainz keeps ONE current name per artist and records every other name as an alias, while
#? each release keeps the name it was CREDITED under at the time. Those two disagree for every
#? artist who has ever renamed, and the disagreement is not a corner case: Ye is credited
#? "Kanye West" on all but two of his own albums, JAY-Z's artist name is "JAY-Z" while his
#? credits say "Jay-Z", and the same goes for Yusuf/Cat Stevens, Diddy and Snoop.
#?
#? jimbrainz writes the CREDIT into the tags and the folder, which is right - the album really
#? was credited that way - so the name on disk is the one MusicBrainz no longer answers to. A
#? search for it found a tribute band and nothing else.


def _quoted(name: str) -> str:
    """A Lucene phrase that survives whatever was typed into it."""
    return '"' + (name or "").replace("\\", "\\\\").replace('"', '\\"') + '"'


def artist_query(name: str) -> str:
    """
    The MusicBrainz query for "which artist goes by this name", aliases included.

    `artist:` matches an artist's CURRENT name only, so on its own it cannot find anybody who
    has renamed - measured: `artist:"Kanye West"` returns "Kanye West Tribute Band" and
    "Kanye West & Hatsune Miku", and Ye is not in the answer at all. `alias:` is the half that
    matches the names they used to go by, and every release credited to one of them.

    Fielded rather than free text, for the reason the search view is: a bare phrase leans on
    whatever MusicBrainz's default field happens to cover today, and this says what it means.
    Both clauses are bracketed so a caller can AND something onto the result without the OR
    quietly binding to the last term - the same trap as the type filter.
    """
    phrase = _quoted(name)
    return f"(artist:{phrase} OR alias:{phrase})"


def artist_names(artist: dict | None) -> list[str]:
    """
    Every name an artist answers to: their own, their sort name, and all their aliases.

    In that order, and de-duplicated case-insensitively, so the first entry is always what
    MusicBrainz calls them now.
    """
    artist = artist or {}
    names = [artist.get("name") or "", artist.get("sort-name") or ""]
    names += [a.get("name") or "" for a in (artist.get("aliases") or [])]

    seen: dict[str, str] = {}
    for name in names:
        if name and name.casefold() not in seen:
            seen[name.casefold()] = name

    return list(seen.values())


#? The characters a name picks up on its way through a tagger, a keyboard and a filesystem.
#? MusicBrainz sets its names properly - JAY-Z is "JAŸ‐Z" with a U+2010 HYPHEN, and is credited
#? "Jay‐Z" with the same one - while the folder somebody typed has a plain hyphen-minus. Neither
#? spelling means anything different, and MusicBrainz's own index already folds them, which is
#? why the search finds the artist and only this comparison used to miss.
_TYPOGRAPHY = str.maketrans({
    "\u2010": "-", "\u2011": "-", "\u2012": "-", "\u2013": "-", "\u2014": "-", "\u2015": "-",
    "\u2212": "-", "\u2018": "'", "\u2019": "'", "\u02bc": "'", "\u00b4": "'", "\u0060": "'",
    "\u201c": '"', "\u201d": '"', "\u00a0": " ",
})


def _fold(name: str) -> str:
    """One spelling of a name, for comparing it against another spelling of the same name."""
    stripped = "".join(
        c for c in unicodedata.normalize("NFKD", name or "") if not unicodedata.combining(c)
    )
    return " ".join(stripped.translate(_TYPOGRAPHY).casefold().split())


def answers_to(artist: dict | None, name: str) -> str:
    """
    The name this artist goes by that `name` is a spelling of, or '' if none is.

    Whole names only, never fuzzy: the reason for checking at all is that MusicBrainz's own
    score is not enough to risk writing one artist's photograph into another's folder, and a
    loose comparison would hand that guarantee straight back. What is folded away is only how a
    name was TYPED - case, accents, which dash, which apostrophe - none of which anybody means
    as a distinction. Two artists who fold together both match, and a tie is refused by the
    caller exactly as two artists sharing a name always were.

    What it returns is the name that MATCHED, in its own spelling, because that is worth
    showing: an answer of "Ye" explains nothing to somebody who searched for Kanye West.
    """
    wanted = _fold(name)
    if not wanted:
        return ""

    return next((n for n in artist_names(artist) if _fold(n) == wanted), "")



def former_names(artist: dict | None) -> list[str]:
    """
    The names an artist PERFORMED under and has stopped using, from MusicBrainz's aliases.

    MusicBrainz says so precisely: an alias of type "Artist name" that has ENDED. Ye's record
    carries "Kanye West" as exactly that (ended 2024) - while "Kanye" and "Yeezy" are live
    nicknames, "Kanye Omari West" is a legal name, and the zh and ja entries are how other
    languages spell him. None of those is how anybody names a folder, and every name here costs
    a Soulseek search, so this is deliberately narrow: a former name is the one MusicBrainz
    itself marks as former.

    Where editors never marked a name as ended there is nothing to find, and the search simply
    goes on with the names the release itself carries - an improvement that degrades to how
    things were, never to worse.
    """
    artist = artist or {}
    current = _fold(artist.get("name") or "")

    names: dict[str, str] = {}
    for alias in artist.get("aliases") or []:
        name = alias.get("name") or ""
        if alias.get("type") != "Artist name" or not alias.get("ended") or not name:
            continue
        if _fold(name) != current and _fold(name) not in names:
            names[_fold(name)] = name

    return list(names.values())


def _also_known_as(artist: dict | None) -> list[str]:
    """Every other name on the artist, best first, without their current one."""
    artist = artist or {}
    current = (artist.get("name") or "").casefold()
    aliases = artist.get("aliases") or []

    #? stable sort, so within a rank MusicBrainz's own order is kept
    ranked = sorted(
        (a for a in aliases if a.get("name")),
        key=lambda a: (a.get("type") != "Artist name", not a.get("primary")),
    )

    seen: dict[str, str] = {}
    for alias in ranked:
        name = alias["name"]
        if name.casefold() != current and name.casefold() not in seen:
            seen[name.casefold()] = name

    return list(seen.values())


def artist_facts(artist: dict | None) -> dict:
    """
    The artist, as a page wants it: no MusicBrainz shapes left for a component to unpick.

    Everything is optional. A brand-new artist in MusicBrainz can be a name and nothing else,
    and a page that renders "None" for the rest is worse than one that leaves those rows out.
    """
    artist = artist or {}
    life = artist.get("life-span") or {}

    return {
        "mbid": artist.get("id"),
        "name": artist.get("name") or "",
        "sort_name": artist.get("sort-name") or "",
        "type": artist.get("type") or "",
        "disambiguation": artist.get("disambiguation") or "",
        "country": artist.get("country") or "",
        "area": (artist.get("area") or {}).get("name") or "",
        "begin_area": (artist.get("begin-area") or {}).get("name") or "",
        "began": life.get("begin") or "",
        "ended_on": life.get("end") or "",
        "ended": bool(life.get("ended")),
        #? by how many people tagged it, not alphabetically: the first three are the answer to
        #? "what is this band", and the tail is noise like "emocore" and "seen live"
        "genres": [g.get("name") for g in sorted(
            artist.get("genres") or [], key=lambda g: -(g.get("count") or 0),
        ) if g.get("name")][:8],
        #? Names they ALSO go by - so their current name is not among them, and nor is the same
        #? name twice in different locales. MusicBrainz returns aliases in no order at all, so
        #? the ones it marks as an artist name lead and its search hints (deliberate misspellings,
        #? there to be found by) bring up the rear, where they do not crowd out the real ones.
        "aliases": _also_known_as(artist)[:6],
        "links": artist_links(artist.get("relations")),
        "members": artist_members(artist.get("relations")),
    }
