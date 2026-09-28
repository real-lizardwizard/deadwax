import os
import re
from urllib.parse import urlsplit
from dotenv import dotenv_values, load_dotenv
from src import __version__
from src.logger import logger

#? Which names the environment already held before .env was read.
#?
#? python-dotenv does not override existing variables, so anything in here won the tie - which
#? is precisely what makes configuring deadwax from a compose `environment:` block work at
#? all. Captured rather than inferred afterwards, because once load_dotenv() has run the two
#? sources are indistinguishable in os.environ, and "check your .env" is unhelpful advice to
#? somebody who configured everything in their compose file.
_ENV_BEFORE_DOTENV = frozenset(os.environ)

#? What the .env file holds, whether or not it won. Only used to explain where a setting came
#? from - and to catch an empty environment variable quietly hiding a real value in here.
_DOTENV_VALUES = dotenv_values()


def _env(name: str, default: str | None = None) -> str | None:
    """
    Read a setting, treating whitespace-only as unset.

    Docker and .env files hand over stray whitespace surprisingly often, and a value like
    "  " is truthy in python - so without the strip it sails past every `if not value` guard
    and only fails much later somewhere far less informative.
    """
    value = os.getenv(name, default)
    return value.strip() if isinstance(value, str) else value


def setting_source(name: str) -> str | None:
    """
    Where a setting actually came from, or None if nothing supplied it.

    Worth reporting rather than inferring. A setting can arrive from a compose
    `environment:` block, from `env_file`/.env, or from the host shell, and when the value is
    wrong the first question is always which of those you need to go and edit.
    """
    if name in _ENV_BEFORE_DOTENV and (os.getenv(name) or "").strip():
        return "the container environment"

    if ((_DOTENV_VALUES.get(name) or "") or "").strip():
        return ".env"

    return None


def shadowed_by_empty_env(name: str) -> bool:
    """
    True when an EMPTY environment variable is hiding a real value in .env.

    The sharp edge of supporting both sources, and one this project has already been cut by:
    an `environment:` entry with nothing after the `=` still counts as set, still wins over
    .env, and leaves you with a blank setting plus a perfectly good .env line that appears to
    be ignored for no reason. Compose produces exactly this from `SLSKD_URL=${SLSKD_URL}` when
    the outer variable isn't defined - which is why the example file uses literal values.
    """
    return (
        name in _ENV_BEFORE_DOTENV
        and not (os.getenv(name) or "").strip()
        and bool(((_DOTENV_VALUES.get(name) or "") or "").strip())
    )


def _describe_address(url: str | None, *, example: str, alone: str, login: str) -> str | None:
    """
    Why this can't be the address of a service deadwax sends a secret to, or None if it can. Shared
    by SLSKD_URL (the API key rides on every request) and NAVIDROME_URL (a token made from the
    password does). Each caller supplies the words that name its own service:

      - `example` is a working address, for the missing-scheme message;
      - `alone` says what to give instead of a `?` or `#`;
      - `login` says where a login belongs instead of in the address.

    Refused, beyond "no scheme, no host" (1.0.3 audit for Navidrome, 1.0.5 for slskd):

      - a user name or password in it (`http://me:pw@host`) would ride along as basic auth -
        requests and httpx both lift it out of the URL - and be quoted back wherever the address is;
      - a `?` or `#` never belongs in a service's address. httpx lets whatever follows swallow the
        path deadwax appends, so a call meant for Navidrome's /rest/getCoverArt fetched any page on
        that host; slskd_api's urljoin quietly drops it instead, so it only reads as something it
        isn't. Refused either way.

    A PATH is allowed: Navidrome's ND_BASEPATH and slskd's URL base both put the API under one, as
    does a reverse proxy's subpath.

    Nothing here quotes the value back (1.0.3 review): this is logged at start-up, shown on the
    settings row, and in the player's and the candidates panel's errors, and a value typed with a
    password in it - `me:pw@host`, with no scheme - would otherwise be repeated wherever it goes.
    The old slskd message, "use http://<the value>", did exactly that.
    """
    if not url:
        return "not set"

    if "://" not in url:
        return f"missing the scheme - it starts with http:// or https://, as in {example}"

    scheme, _, rest = url.partition("://")
    if scheme not in ("http", "https"):
        return "has a scheme other than http:// or https://"

    if not rest.strip("/"):
        return "has a scheme but no host"

    if "?" in url or "#" in url:
        return f"has a ? or # in it - {alone}"

    if any(c.isspace() for c in url):
        return "has a space in it"

    parts = urlsplit(url)
    if "@" in parts.netloc:
        return f"has a user name or password in it - {login}"

    if not parts.hostname:
        return "has a scheme but no host"

    try:
        parts.port
    except ValueError:
        return "has a port that isn't a number"

    return None


def describe_slskd_url(url: str | None) -> str | None:
    """
    Why this can't be SLSKD_URL, or None if it can. Every request to it carries SLSKD_APIKEY, which
    is full control of slskd - so since 1.0.5 it is held to what NAVIDROME_URL is. See
    _describe_address.
    """
    return _describe_address(
        url,
        example="http://slskd:5030",
        alone="give slskd's address alone, with its URL base if it has one",
        login="deadwax signs in to slskd with SLSKD_APIKEY alone",
    )


def describe_navidrome_url(url: str | None) -> str | None:
    """Why this can't be NAVIDROME_URL, or None if it can. See _describe_address."""
    return _describe_address(
        url,
        example="http://navidrome:4533",
        alone="give Navidrome's address alone, with its base path if it has one",
        login="those go in NAVIDROME_USER and NAVIDROME_PASSWORD",
    )


def without_login(url: str | None, mark: str = "") -> str:
    """
    The address as it may be shown: any user name or password in it replaced by `mark` (removed, by
    default). The clients refuse such an address, so this is the second line - an error quoting it
    lands in the log, the page's event log and the player's screen, and the settings payload
    renders on a page people screenshot into bug reports.

    Read by hand rather than by urlsplit, which raises on some malformed values and finds no host
    at all in one typed without a scheme - `me:pw@navidrome:4533` would come back whole. The login
    is whatever comes before the last `@` of the authority: the part after `://` (or the whole
    value, with none) up to the first `/`, `?` or `#`, which is where requests and httpx look.
    """
    url = url or ""
    scheme, sep, rest = url.partition("://")
    if not sep:
        scheme, rest = "", url

    end = min((i for i in (rest.find(c) for c in "/?#") if i != -1), default=len(rest))
    authority = rest[:end]
    if "@" not in authority:
        return url

    return f"{scheme}{sep}{mark}{authority.rpartition('@')[2]}{rest[end:]}"


#? The name MusicBrainz and the Cover Art Archive are given, with the version appended from
#? src/__init__.py rather than typed by anybody. That is the point of building it here: a user
#? agent written by hand in a compose file goes on claiming whichever version it was written
#? against long after the image has moved on, and the contact is the only part of it that was
#? ever the user's to supply.
APP_NAME = "deadwax"

#? The database's default home, and where it lived while the project was called jimbrainz
#? (renamed to deadwax in v0.6.21). An install that never set DB_PATH has every job, ignore,
#? override and saved scan in the OLD file, and a new default pointing somewhere empty would
#? greet it with a blank slate and no word of why. So the old file keeps being used - read in
#? place, never moved, since moving it is a write into somebody's config volume that nothing
#? here needs. Only when the new file doesn't exist yet: once it does, it is the database.
DEFAULT_DB_PATH = "/config/deadwax.db"
LEGACY_DB_PATH = "/config/jimbrainz.db"


def default_db_path(new: str = DEFAULT_DB_PATH, legacy: str = LEGACY_DB_PATH) -> str:
    """The database to use when DB_PATH is not set: the old one, if that is where the data is."""
    if not os.path.exists(new) and os.path.exists(legacy):
        return legacy
    return new


#? What the Cover Art Archive will serve for a release's front cover. The numbers are its fixed
#? thumbnail sizes; `full` is whatever was originally uploaded, which has no fixed size at all.
COVER_ART_SIZES = ("250", "500", "1200", "full")


#? How far LYRICS_LEAD_MS may move lyrics either way. Five seconds is far past any tapping lag;
#? a larger number is almost certainly seconds typed where milliseconds were meant.
LYRICS_LEAD_LIMIT_MS = 5000


#? PLAYER_CACHE_MB's default and bounds. 64 MB still holds a CD-quality song while it is made
#? (two copies of it, briefly); a terabyte is past any disk this cache would sensibly be given.
DEFAULT_PLAYER_CACHE_MB = 1024
PLAYER_CACHE_MB_RANGE = (64, 1 << 20)


def parse_player_cache_mb(value: str | None) -> int | None:
    """PLAYER_CACHE_MB as a whole number of MB within range, or None when it isn't one."""
    text = (value or "").strip().removesuffix("MB").removesuffix("mb").strip()
    #? ASCII digits only: int() also takes '٣' and '1_024', which nobody means as a size
    if not re.fullmatch(r"[0-9]+", text):
        return None
    low, high = PLAYER_CACHE_MB_RANGE
    megabytes = int(text)
    return megabytes if low <= megabytes <= high else None


def parse_lyrics_lead(value: str | None) -> int | None:
    """A lyrics lead in milliseconds, or None if `value` isn't one - a whole number within the limit."""
    text = (value or "").strip().removesuffix("ms").strip()
    try:
        lead = int(text or "0")
    except ValueError:
        return None
    return lead if abs(lead) <= LYRICS_LEAD_LIMIT_MS else None


def build_user_agent(contact: str) -> str:
    """`deadwax/<version> ( contact )` - MusicBrainz's documented shape, spaces and all."""
    return f"{APP_NAME}/{__version__} ( {contact} )"


def contact_from_useragent(value: str | None) -> str | None:
    """
    The contact inside a user agent written by hand, the way MUSICBRAINZ_USERAGENT used to be.

    MusicBrainz documents the form `App/1.0 ( contact )`, and the bracketed contact is the only
    part of it that was ever the user's own - the name and version describe deadwax. So an
    install configured the old way keeps working after an upgrade: the contact is lifted out,
    and the rest is rebuilt around it with the version actually running.

    None when there is no contact to find. The caller then sends the old value exactly as it
    was, since that is what this install has been sending, and guessing at it could only make
    it worse.
    """
    text = (value or "").strip()
    if not text:
        return None

    #? the documented place: the last bracketed part
    bracketed = [part.strip() for part in re.findall(r"\(([^()]*)\)", text)]
    if bracketed and bracketed[-1]:
        return bracketed[-1]

    #? no brackets - a bare address or URL, possibly after an `App/1.0` token
    for token in reversed(text.split()):
        token = token.strip("<>,;")
        if "@" in token or "://" in token:
            return token

    return None


def describe_contact(value: str | None) -> str | None:
    """
    Why this can't be sent as the MusicBrainz contact, or None if it can.

    Checks what would make it unusable, not whether the address is real: an address that parses
    is all a user agent needs, and MusicBrainz is the one who would ever write to it. Phrased to
    follow the setting's name - "MUSICBRAINZ_EMAIL has spaces in it".
    """
    text = (value or "").strip()

    if not text:
        return "is not set"

    if not text.isascii():
        #? request headers are ASCII, and httpx refuses to build a client with anything else -
        #? which would surface as every MusicBrainz request failing "unexpectedly"
        return "has characters a web request header can't carry - use plain ASCII"

    if "(" in text or ")" in text:
        return "wants just the address, without brackets - deadwax writes the rest itself"

    if any(c.isspace() or not c.isprintable() for c in text):
        return "has spaces in it - it should be one address, like you@example.com"

    if "@" not in text and "." not in text:
        return "doesn't look like an email address or a web address"

    return None


load_dotenv()
class Config:
    #? The contact MusicBrainz asks every app for: an email address, or a web address. It is the
    #? only part of the user agent that is yours - deadwax writes its own name and version
    #? around it, so the version sent is always the one running. See musicbrainz_user_agent().
    MUSICBRAINZ_EMAIL = _env("MUSICBRAINZ_EMAIL")

    #? The old way: a whole user agent, written by hand. Still read, so an install configured
    #? before MUSICBRAINZ_EMAIL existed keeps working - its contact is lifted out and used when
    #? no email is set. Superseded rather than required.
    MUSICBRAINZ_USERAGENT = _env("MUSICBRAINZ_USERAGENT")

    #? slskd is the download backend now, not optional anymore
    SLSKD_URL = _env("SLSKD_URL")
    SLSKD_APIKEY = _env("SLSKD_APIKEY")

    #? filesystem paths for organizing finished downloads
    SLSKD_DOWNLOAD_PATH = _env("SLSKD_DOWNLOAD_PATH")

    #? Optional, and cleanup is off without it. slskd's INCOMPLETE folder as seen from this
    #? container, which is a different mount from the completed downloads above. Setting it
    #? lets a cancelled download take its half-finished file with it; leaving it unset keeps
    #? slskd's own behaviour, where a partial file is retained so a retry can resume from it.
    SLSKD_INCOMPLETE_PATH = _env("SLSKD_INCOMPLETE_PATH")
    LIBRARY_PATH = _env("LIBRARY_PATH")
    DB_PATH = _env("DB_PATH") or default_db_path()

    #? off | dry_run | copy | move. Defaults to dry_run deliberately: organizing is the only
    #? thing here that writes to your filesystem, so a fresh install reports what it would
    #? have done rather than acting on a possibly mis-mapped volume.
    ORGANIZE_MODE = _env("ORGANIZE_MODE", "dry_run")

    #? How big a cover to fetch from the Cover Art Archive: 250 | 500 | 1200 | full. 500 is the
    #? size deadwax always fetched, and it stays the default - `full` pulls the original
    #? upload, which is often several megabytes, so it is something to choose rather than
    #? something to be given. Read at the point of use, like everything else here.
    COVER_ART_SIZE = _env("COVER_ART_SIZE", "500")

    #? on | off. Whether an album filed from a download gets its lyrics looked up on LRCLIB and
    #? written as a .lrc beside each track. On by default because it only ever ADDS files, and
    #? only once organizing actually writes - a dry run fetches nothing. Off is for anyone who
    #? would rather this container didn't ask a third party about every track they download.
    FETCH_LYRICS = _env("FETCH_LYRICS", "on")

    #? on | off. Whether a release's COUNTRY may name its folder when nothing else tells the
    #? pressing apart - `Dummy (1994) [GB]`. Off by default since v0.8.3, when James asked for
    #? it gone: most CDs are some country's, so most albums grew a suffix that said nothing
    #? anyone needed. Two different releases still never share a folder - see editions.py.
    COUNTRY_IN_FOLDER = _env("COUNTRY_IN_FOLDER", "off")

    #? on | off. When a download fails, move it to the next peer from the list it was picked
    #? from, by itself (v0.9.12). Off by default: the next peer down is ranked against the same
    #? release but may be a different pressing or a worse rip, and that is a choice somebody
    #? should see being made. "Try next peer" on a failed download works either way.
    AUTO_RETRY_PEER = _env("AUTO_RETRY_PEER", "off")

    #? Seconds slskd listens for answers to a Soulseek search (v0.9.16). Peers answer over
    #? several seconds, slow and firewalled ones last, so a longer search hears from more of
    #? them and a shorter one gets you a list sooner. 8 is what it always was; 3 to 60.
    SLSKD_SEARCH_TIMEOUT = _env("SLSKD_SEARCH_TIMEOUT", "8")

    #? How an ALBUM folder is named (v0.9.17) - the artist folder above it is always the artist.
    #? Tokens in src/naming.py; empty means the long-standing `{album} ({year}) [{edition}]`.
    #? Changing it moves nothing already filed: those albums show as "folder off-convention"
    #? until a release is applied to them.
    ALBUM_FOLDER_TEMPLATE = _env("ALBUM_FOLDER_TEMPLATE", "")

    #? Seconds to wait between writing an album's new tags and renaming its folder, when applying
    #? a release changes both (v1.0.1). Navidrome keeps plays, ratings and favourites across a
    #? retag OR a rename, but not both in one scan - which is what a one-step apply was. Waiting
    #? lets its watcher (5s after a change) see the new tags at the old path first. With Navidrome
    #? set up below, deadwax asks it when it has scanned instead of counting (v1.0.3), and this
    #? only has to be more than 0. 0 renames straight away either way, as before; 0 to 300.
    RETAG_RENAME_WAIT = _env("RETAG_RENAME_WAIT", "20")

    #? Milliseconds to move synced lyrics EARLIER as they are written - negative moves them
    #? later. LRCLIB's timings are tapped along by people and land a moment after the line is
    #? sung, which on a fast song shows the line just sung. 0 writes LRCLIB's timings as they
    #? are. See lyrics.py for why it goes into the timestamps and not an [offset:] tag.
    LYRICS_LEAD_MS = _env("LYRICS_LEAD_MS", "0")

    #? Optional, and artist banners are off without it. MusicBrainz has no artist images at all
    #? and Wikimedia Commons has a photograph at best, so TheAudioDB is the only source here
    #? with banners, logos and backgrounds - keyed by the same MusicBrainz artist id deadwax
    #? already holds. Everything else about an artist page works without it.
    THEAUDIODB_KEY = _env("THEAUDIODB_KEY")

    #? fanart.tv, the other source of artist artwork, and the one whose pictures are voted on by
    #? the people using them. It needs a PROJECT key, which its developers issue per application
    #? rather than per person - so it cannot be shipped in a public repo and has to be yours.
    #? The personal key is optional and only buys earlier sight of newly added images.
    FANARTTV_KEY = _env("FANARTTV_KEY")
    FANARTTV_PERSONAL_KEY = _env("FANARTTV_PERSONAL_KEY")

    #? Optional, and the player at /player/ is off without them. Navidrome is what plays the
    #? library; deadwax holds its login and passes on a short, fixed list of read-only requests,
    #? so the password never reaches a phone's browser. See src/api/navidrome_endpoint.py. With
    #? them, applying a release also asks Navidrome when it has scanned before renaming a folder.
    #? None of it needs an admin account, and a non-admin one of your own is the one to give it.
    NAVIDROME_URL = _env("NAVIDROME_URL")
    NAVIDROME_USER = _env("NAVIDROME_USER")
    NAVIDROME_PASSWORD = _env("NAVIDROME_PASSWORD")

    #? Where the player keeps the MP4s it makes of FLAC songs for Safari, whose seeks land only in
    #? an MP4 (1.1.0, src/player_cache.py). Empty is the container's temporary space. deadwax makes
    #? a folder of its own inside it, deadwax-player, private to it, and touches nothing else there
    #? - so this can be a folder other things use too. Asked for so the cache can go on an SSD. Only
    #? ever a cache: anything in it is made again from Navidrome when it is next played.
    PLAYER_CACHE_PATH = _env("PLAYER_CACHE_PATH")

    #? How much that cache may hold, in MB (MiB): the songs played longest ago go first past it.
    #? 1024 is the gigabyte it always had, several albums of CD-quality FLAC. 64 to 1048576.
    PLAYER_CACHE_MB = _env("PLAYER_CACHE_MB", str(DEFAULT_PLAYER_CACHE_MB))

    #? ===== which settings the settings tab may write ==========================
    #?
    #? Editability is a property of the setting, not a policy choice, and the split is real:
    #?
    #?   DB_PATH is where the overrides themselves are stored. Overriding it from the table
    #?   it lives in is a chicken-and-egg problem with no sensible answer - point it
    #?   somewhere new and the row telling you to do so is in the old file.
    #?
    #?   PUID/PGID are consumed by docker-entrypoint.sh, which has already dropped privileges
    #?   before Python starts. Nothing this process writes can change who it is running as.
    #?
    #? Everything else is genuinely changeable at runtime, because Config is read as a class
    #? attribute at the point of use rather than captured at import. The cached clients (slskd,
    #? MusicBrainz, Navidrome) and the library's scan cache are the exception, and the value here
    #? names the one to rebuild - see the settings route.
    EDITABLE = {
        "SLSKD_URL": "slskd",
        "SLSKD_APIKEY": "slskd",
        "MUSICBRAINZ_EMAIL": "musicbrainz",
        #? Still editable, so an override stored under it can be seen and reverted. The tab
        #? only shows its row while it is set - see the settings route.
        "MUSICBRAINZ_USERAGENT": "musicbrainz",
        "ORGANIZE_MODE": None,
        "SLSKD_DOWNLOAD_PATH": None,
        "SLSKD_INCOMPLETE_PATH": None,
        "LIBRARY_PATH": "library",
        #? the cover art client reads it per fetch, so there is nothing to rebuild
        "COVER_ART_SIZE": None,
        #? read by the poller as each album is filed, so nothing to rebuild
        "FETCH_LYRICS": None,
        #? read each time a folder name is made, so nothing to rebuild
        "COUNTRY_IN_FOLDER": None,
        #? read by the poller as each download fails, so nothing to rebuild
        "AUTO_RETRY_PEER": None,
        #? read per search, so nothing to rebuild
        "SLSKD_SEARCH_TIMEOUT": None,
        #? read by each apply as it runs
        "RETAG_RENAME_WAIT": None,
        #? read each time a folder name is made or read, so nothing to rebuild
        "ALBUM_FOLDER_TEMPLATE": None,
        #? read as each .lrc is written, so nothing to rebuild
        "LYRICS_LEAD_MS": None,
        #? read per lookup by the artist image client, so nothing to rebuild here either
        "THEAUDIODB_KEY": None,
        "FANARTTV_KEY": None,
        "FANARTTV_PERSONAL_KEY": None,
        #? the Navidrome client caches its base URL, so a change drops it for a rebuild
        "NAVIDROME_URL": "navidrome",
        #? signed into each request's token, so nothing to rebuild
        "NAVIDROME_USER": None,
        "NAVIDROME_PASSWORD": None,
        #? read by the player's cache at every request it answers, so nothing to rebuild
        "PLAYER_CACHE_PATH": None,
        "PLAYER_CACHE_MB": None,
    }

    #? Why each of these cannot be edited here, in words the settings tab renders verbatim.
    NOT_EDITABLE = {
        "DB_PATH": (
            "This is the database the overrides are stored in, so changing it here would "
            "move the file out from under the setting that changed it. Set it in your "
            "compose file."
        ),
    }

    #? Keys whose stored value came from the settings tab rather than the environment.
    #? Populated by apply_overrides(); read by the settings route so the tab can say which
    #? values are overriding the environment and offer to revert them.
    OVERRIDDEN: set[str] = set()

    #? What the environment said, before any override was laid over it. Kept so "revert to
    #? the environment value" can show what it would revert TO.
    ENV_VALUES: dict[str, str | None] = {}

    @classmethod
    def apply_overrides(cls, stored: dict[str, str]) -> None:
        """
        Lay the stored overrides over the environment's values.

        Called once at startup, after the store opens and before anything serves a request.
        Unknown and non-editable keys are ignored rather than trusted: this reads rows out of
        a database that a user can edit by hand, and setting arbitrary Config attributes from
        it would be a much larger surface than intended.
        """
        #? Captured ONCE, and only once. This method mutates the class attributes, so a
        #? second capture would read back the values a previous call had already overridden -
        #? and the real environment value would be gone for good. That bug is not theoretical:
        #? it made "revert to the environment" delete the row and then leave the overridden
        #? value in place, because there was nothing left to restore.
        if not cls.ENV_VALUES:
            cls.ENV_VALUES = {name: getattr(cls, name, None) for name in cls.EDITABLE}

        #? Reset to the environment before laying anything over it, so a key whose override
        #? has just been deleted actually goes back to what the environment said. Applying
        #? only the stored keys would leave the previous value stuck.
        for name, env_value in cls.ENV_VALUES.items():
            setattr(cls, name, env_value)

        cls.OVERRIDDEN = set()

        for key, value in stored.items():
            if key not in cls.EDITABLE:
                logger.warning(f"ignoring stored setting {key!r}, which is not editable")
                continue

            setattr(cls, key, value)
            cls.OVERRIDDEN.add(key)

        if cls.OVERRIDDEN:
            logger.info(
                f"applied {len(cls.OVERRIDDEN)} setting(s) from the settings tab: "
                f"{', '.join(sorted(cls.OVERRIDDEN))}"
            )

    @classmethod
    def lyrics_lead_ms(cls) -> int:
        """LYRICS_LEAD_MS as a number. Anything unreadable is 0 - LRCLIB's own timings."""
        return parse_lyrics_lead(cls.LYRICS_LEAD_MS) or 0

    @classmethod
    def musicbrainz_contact(cls) -> tuple[str | None, str | None]:
        """
        The contact to send, and the setting it came from.

        MUSICBRAINZ_EMAIL wins. Without it, the contact inside an old MUSICBRAINZ_USERAGENT is
        used, so an install configured before the email setting existed carries on working -
        and starts reporting the version it is actually running.

        An email that could not be sent at all is passed over rather than sent broken: httpx
        refuses a header it can't encode, which would take down every MusicBrainz request
        rather than just this one field. describe_contact() is what says why, in the settings
        tab and in the log.
        """
        email = (cls.MUSICBRAINZ_EMAIL or "").strip()
        if email and email.isascii() and email.isprintable():
            return email, "MUSICBRAINZ_EMAIL"

        legacy = contact_from_useragent(cls.MUSICBRAINZ_USERAGENT)
        if legacy:
            return legacy, "MUSICBRAINZ_USERAGENT"

        return None, None

    @classmethod
    def musicbrainz_user_agent(cls) -> str | None:
        """
        What MusicBrainz and the Cover Art Archive are told we are, or None if there's no contact.

        Built on every call rather than stored, so it follows a contact changed in the settings
        tab - and the version, which only changes with the code, cannot go stale.
        """
        contact, _ = cls.musicbrainz_contact()
        if contact:
            return build_user_agent(contact)

        #? An old hand-written value with no contact in it at all. Sent as it was, because it is
        #? what this install has been sending - MusicBrainz may well rate limit it, and the
        #? settings tab says so, but quietly replacing it with nothing would be worse.
        return (cls.MUSICBRAINZ_USERAGENT or "").strip() or None

    @classmethod
    def report_musicbrainz(cls) -> None:
        """
        Say what MusicBrainz will be told, and whether anything about it needs fixing.

        Called once the settings tab's overrides have been laid over the environment, NOT from
        check(), which runs before they are: an email set in the tab would otherwise be
        reported missing on every restart, next to a tab showing it perfectly well set.
        """
        email_problem = describe_contact(cls.MUSICBRAINZ_EMAIL) if cls.MUSICBRAINZ_EMAIL else None
        if email_problem:
            logger.error(f"MUSICBRAINZ_EMAIL {email_problem}", extra={"frontend": True})

        _, source = cls.musicbrainz_contact()
        user_agent = cls.musicbrainz_user_agent()

        if source == "MUSICBRAINZ_EMAIL":
            logger.info(f"MusicBrainz user agent: {user_agent}")

        elif source == "MUSICBRAINZ_USERAGENT":
            #? not an error - it works - but worth a line, since the fix is a one-line edit
            logger.info(
                f"using the contact from MUSICBRAINZ_USERAGENT, sent as {user_agent}. Set "
                f"MUSICBRAINZ_EMAIL instead and the old user agent can go."
            )

        elif user_agent:
            logger.error(
                "MUSICBRAINZ_USERAGENT has no contact in it that deadwax can find, so it is "
                "sent exactly as written - and MusicBrainz rate limits requests without one. "
                "Set MUSICBRAINZ_EMAIL to your email address.",
                extra={"frontend": True},
            )

        else:
            logger.error(
                "MUSICBRAINZ_EMAIL is not set. MusicBrainz asks every app for a contact address "
                "and rate limits requests without one - set it in the settings tab, or in your "
                "compose file.",
                extra={"frontend": True},
            )

    #? the three the player needs, all or none
    NAVIDROME_SETTINGS = ("NAVIDROME_URL", "NAVIDROME_USER", "NAVIDROME_PASSWORD")

    @classmethod
    def report_navidrome(cls) -> None:
        """
        Say whether the player at /player/ can ask Navidrome anything, and if not, what's missing.

        Called once the settings tab's overrides are in, beside report_musicbrainz() and for the
        same reason: from check(), a Navidrome set up in the tab was logged as "not configured" on
        every restart while the player worked (1.0.3 audit). Never logs the password, or anything
        made from it - only which settings are set, and where the address came from.
        """
        given = [name for name in cls.NAVIDROME_SETTINGS if getattr(cls, name, None)]

        if not given:
            logger.info(
                "Navidrome isn't set up (NAVIDROME_URL, NAVIDROME_USER, NAVIDROME_PASSWORD), so the "
                "player at /player/ is off, and applying a release waits a fixed RETAG_RENAME_WAIT "
                "before renaming"
            )
            return

        missing = [name for name in cls.NAVIDROME_SETTINGS if name not in given]
        if missing:
            logger.error(
                f"{' and '.join(missing)} {'is' if len(missing) == 1 else 'are'} not set, so the player "
                f"at /player/ is off - it needs all three NAVIDROME_ settings, and only "
                f"{' and '.join(given)} {'is' if len(given) == 1 else 'are'} there. Set the rest in the "
                f"settings tab (Connections), or in your compose file.",
                extra={"frontend": True},
            )
            return

        problem = describe_navidrome_url(cls.NAVIDROME_URL)
        if problem:
            #? true to the letter: the client refuses the address (get_client), so nothing is sent
            #? to it, and the apply waits the fixed time rather than asking (navidrome_usable)
            logger.error(
                f"NAVIDROME_URL is unusable ({problem}), so the player at /player/ can't reach "
                f"Navidrome, and applying a release waits a fixed RETAG_RENAME_WAIT before renaming. "
                f"It is Navidrome's address as seen from inside this container - "
                f"http://navidrome:4533 on a shared docker network.",
                extra={"frontend": True},
            )
            return

        source = (
            "the settings tab" if "NAVIDROME_URL" in cls.OVERRIDDEN
            else setting_source("NAVIDROME_URL") or "the environment"
        )
        logger.info(
            f"the player at /player/ plays from Navidrome at {cls.NAVIDROME_URL} (from {source}), "
            f"as {cls.NAVIDROME_USER}"
        )

    @classmethod
    def exists(cls, env_var: str):
        value = os.getenv(env_var)

        if not value:
            logger.error(f"{env_var} not set either in .env config file or environment")

        return value

    @classmethod
    def check(cls):
        #? MusicBrainz and Navidrome are reported separately, by report_musicbrainz() and
        #? report_navidrome(), once the settings tab's overrides are in - see their docstrings
        #? for why it can't happen here.

        if cls.DB_PATH == LEGACY_DB_PATH and not _env("DB_PATH"):
            logger.info(
                f"using the database from before the rename, {LEGACY_DB_PATH} - nothing needs "
                f"doing, it will go on being used where it is"
            )

        #? Named before anything else, because an empty environment variable beating a good
        #? .env line is invisible from the value alone - the setting simply reads as unset
        #? while the .env line sits there looking correct.
        for name in ("SLSKD_URL", "SLSKD_APIKEY", "MUSICBRAINZ_EMAIL", "ORGANIZE_MODE",
                     "COVER_ART_SIZE"):
            if shadowed_by_empty_env(name):
                logger.error(
                    f"{name} is set to an EMPTY value in the container environment, which "
                    f"overrides the value in your .env. Either give it a value in your compose "
                    f"file's `environment:` block or remove the line entirely - an "
                    f"`{name}=${{{name}}}` entry does this whenever the outer variable is unset.",
                    extra={"frontend": True},
                )

        url_problem = describe_slskd_url(cls.SLSKD_URL)
        if url_problem:
            logger.error(
                f"SLSKD_URL is unusable ({url_problem}) - searching and downloading will fail. "
                f"Set it in your compose file's `environment:` block, or in the .env named by "
                f"`env_file:`; a value in `environment:` wins if you use both.",
                extra={"frontend": True},
            )

        else: logger.info(f"SLSKD_URL found! (from {setting_source('SLSKD_URL')})")

        if not cls.SLSKD_APIKEY:
            logger.error("SLSKD_APIKEY not found in environment, downloads will not work", extra={"frontend": True})

        else: logger.info(f"SLSKD_APIKEY found! (from {setting_source('SLSKD_APIKEY')})")

        if not cls.SLSKD_DOWNLOAD_PATH:
            logger.warning("SLSKD_DOWNLOAD_PATH not found in environment, organizing downloaded files will be disabled")

        else: logger.info("SLSKD_DOWNLOAD_PATH found!")

        if cls.SLSKD_INCOMPLETE_PATH:
            logger.info(
                "SLSKD_INCOMPLETE_PATH found! cancelled downloads will take their partial files "
                "with them, and empty folders left in it are cleared"
            )

        else:
            logger.info(
                "SLSKD_INCOMPLETE_PATH not set, so cancelling a download leaves its partial "
                "file in slskd's incomplete folder (which is what lets slskd resume it)"
            )

        if not cls.LIBRARY_PATH:
            logger.warning("LIBRARY_PATH not found in environment, organizing downloaded files will be disabled")

        else: logger.info("LIBRARY_PATH found!")

        if cls.ORGANIZE_MODE not in ("off", "dry_run", "copy", "move"):
            logger.error(
                f"ORGANIZE_MODE is '{cls.ORGANIZE_MODE}', expected one of off/dry_run/copy/move. "
                f"Falling back to dry_run.",
                extra={"frontend": True},
            )
            cls.ORGANIZE_MODE = "dry_run"

        if cls.COVER_ART_SIZE not in COVER_ART_SIZES:
            logger.error(
                f"COVER_ART_SIZE is '{cls.COVER_ART_SIZE}', expected one of "
                f"{', '.join(COVER_ART_SIZES)}. Falling back to 500.",
                extra={"frontend": True},
            )
            cls.COVER_ART_SIZE = "500"

        if cls.organizing_enabled():
            logger.info(f"organizing enabled in '{cls.ORGANIZE_MODE}' mode")

        else: logger.info("organizing disabled (needs SLSKD_DOWNLOAD_PATH + LIBRARY_PATH, and ORGANIZE_MODE not 'off')")

    @classmethod
    def navidrome_configured(cls) -> bool:
        """All three NAVIDROME_ settings are there - whether the address is usable or not."""
        return bool(cls.NAVIDROME_URL and cls.NAVIDROME_USER and cls.NAVIDROME_PASSWORD)

    @classmethod
    def navidrome_usable(cls) -> bool:
        """
        Navidrome can be asked: all three set AND an address describe_navidrome_url() accepts. The
        client refuses any other (1.0.3 review), so an apply that relied on asking it would only
        ever fall back - better to say from the start that it waits a fixed time.
        """
        return cls.navidrome_configured() and describe_navidrome_url(cls.NAVIDROME_URL) is None

    @classmethod
    def organizing_enabled(cls) -> bool:
        return bool(cls.SLSKD_DOWNLOAD_PATH and cls.LIBRARY_PATH and cls.ORGANIZE_MODE != "off")


SEARCH_TIMEOUT_RANGE = (3, 60)


def parse_search_timeout(value) -> int | None:
    """SLSKD_SEARCH_TIMEOUT as whole seconds within range, or None when it isn't one."""
    try:
        seconds = int(str(value).strip())
    except (TypeError, ValueError):
        return None
    low, high = SEARCH_TIMEOUT_RANGE
    return seconds if low <= seconds <= high else None


RENAME_WAIT_RANGE = (0, 300)


def parse_rename_wait(value) -> int | None:
    """RETAG_RENAME_WAIT as whole seconds within range, or None when it isn't one."""
    try:
        seconds = int(str(value).strip())
    except (TypeError, ValueError):
        return None
    low, high = RENAME_WAIT_RANGE
    return seconds if low <= seconds <= high else None


def rename_wait_seconds() -> int:
    """How long an apply waits before renaming - the setting when valid, else the default 20."""
    seconds = parse_rename_wait(Config.RETAG_RENAME_WAIT)
    return 20 if seconds is None else seconds


def search_timeout_seconds() -> int:
    """What a search waits for - the setting when it is valid, else the long-standing 8."""
    return parse_search_timeout(Config.SLSKD_SEARCH_TIMEOUT) or 8


def player_cache_bytes() -> int:
    """The player cache's cap in bytes - the setting when it is valid, else the gigabyte it always was."""
    return (parse_player_cache_mb(Config.PLAYER_CACHE_MB) or DEFAULT_PLAYER_CACHE_MB) << 20
