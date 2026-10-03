"""
The settings tab's backend.

MOST SETTINGS ARE EDITABLE HERE. The ones that aren't, aren't for a stated reason.

Server settings arrive as environment variables from a compose `environment:` block or from
`.env`, read once at process start. Editing that file from inside the container would not
affect the running process, so the writable path does NOT touch it. Overrides are stored in
the sqlite database instead (see the `settings` table in store.py) and laid over the
environment's values at startup by Config.apply_overrides().

The precedence question is the one that matters, and there is only one honest answer:

  A STORED OVERRIDE WINS over the environment.

The alternative - environment wins - would mean an edit made in this tab silently reverted on
the next restart for anybody configuring through compose, which is most people. So the
override wins, and the tab says plainly when a value is overriding what the environment
supplied, and offers to revert it. Reverting DELETES the row rather than writing the
environment's value back, so a setting that has been reverted follows the compose file again
instead of pinning whatever it happened to say that day.

Two settings genuinely cannot be edited here, and the tab renders the reason rather than
hiding them: DB_PATH (it is the database the overrides live in) and PUID/PGID (consumed by
docker-entrypoint.sh, which has already dropped privileges before Python starts).

Editing applies LIVE, without a restart, because Config is read as a class attribute at the
point of use rather than captured at import. The cached clients (slskd, MusicBrainz, Navidrome)
are the exception, so a change to their settings drops the cached client and the next call
rebuilds it.

Diagnosis is still half the job. For every setting the tab answers:

  1. what value did the container actually receive?
  2. which file do I go and edit to change it - or is it overridden here?
  3. is it usable, and if not, precisely what is wrong with it?

Question 2 is genuinely hard to answer from outside: once load_dotenv() has run, a value from
compose and a value from .env are indistinguishable in os.environ. config.py captures the
difference at import time; this endpoint is what surfaces it.

Client-side preferences (format preference, auto-grab, candidate defaults) are a separate
thing entirely - they live in localStorage, they ARE editable, and the backend never sees
them. See ui/src/state/persisted.ts.
"""

import os
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from src import __version__, player_cache
from src.config import (COVER_ART_SIZES, DEFAULT_PLAYER_CACHE_MB, LYRICS_LEAD_LIMIT_MS, PLAYER_CACHE_MB_RANGE,
                        RENAME_WAIT_RANGE, SEARCH_TIMEOUT_RANGE, Config,
                        build_user_agent, parse_player_cache_mb, parse_rename_wait, parse_search_timeout,
                        describe_contact, describe_navidrome_url, describe_slskd_url, parse_lyrics_lead,
                        setting_source, shadowed_by_empty_env, without_login)
from src.scan_wait import SCAN_WAIT_CAP_SECONDS
from src.logger import logger

router = APIRouter()


#? Modes the organizer understands, with what each one actually does to your filesystem.
#? Ordered least to most destructive, which is the order the tab renders them in.
ORGANIZE_MODES = {
    "off": "Never organize - downloads stay where slskd put them",
    "dry_run": "Log what would happen, write nothing",
    "copy": "Copy into the library, leave slskd's copy alone",
    "move": "Move into the library",
}

#? What COUNTRY_IN_FOLDER can be set to, as the dropdown names them.
COUNTRY_CHOICES = {
    "off": "Leave the country out of folder names",
    "on": "Name a regional pressing by its country",
}

#? What AUTO_RETRY_PEER can be set to, as the dropdown names them.
AUTO_RETRY_CHOICES = {
    "off": "Leave a failed download for me to retry",
    "on": "Move a failed download to the next peer by itself",
}

#? What FETCH_LYRICS can be set to, as the dropdown names them.
LYRICS_CHOICES = {
    "on": "Fetch lyrics as albums are filed",
    "off": "Don't fetch lyrics automatically",
}

#? What COVER_ART_SIZE can be set to, as the dropdown names them. The keys are the Cover Art
#? Archive's own sizes - see COVER_ART_SIZES in config.py, which a test keeps these in step with.
COVER_ART_SIZE_CHOICES = {
    "250": "250 × 250",
    "500": "500 × 500",
    "1200": "1200 × 1200",
    "full": "Full size",
}

#? What each one costs, for the line under the dropdown.
COVER_ART_SIZE_NOTES = {
    "250": "A thumbnail: a few tens of KB, and soft anywhere bigger than the library's list",
    "500": "The default. Sharp in the library, and small enough not to notice on disk",
    "1200": "Sharp on any screen, and usually a few hundred KB",
    "full": (
        "The original upload, at whatever size it was scanned - usually thousands of pixels "
        "and several MB, sometimes much more. If the original isn't an image (the Archive "
        "takes PDFs), the 1200 × 1200 copy is saved instead"
    ),
}


def _describe_path(value: str | None, *, needs_write: bool,
                   unwritable: str = "organizing will fail when it tries to file something") -> tuple[str, str | None]:
    """
    Whether a configured path is actually usable from inside this container.

    Returns (status, detail). This is the single most valuable check in the file: the most
    common first-run failure by a wide margin is a path that is set, looks correct, and
    points somewhere this container cannot see - because the value describes the HOST's
    filesystem rather than the container's. That failure is invisible from the value alone,
    which is exactly why it is worth resolving here rather than trusting the string.
    """
    if not value:
        return "unset", None

    path = Path(value)

    try:
        if not path.exists():
            return "error", (
                f"nothing exists at {value} as seen from inside this container. This is "
                f"usually a volume mapping - the path has to be the CONTAINER's path, not "
                f"the host's."
            )

        if not path.is_dir():
            return "error", f"{value} exists but is a file, not a directory"

        if not os.access(path, os.R_OK):
            return "error", f"{value} exists but this container cannot read it (check PUID/PGID)"

        if needs_write and not os.access(path, os.W_OK):
            return "error", (
                f"{value} is readable but NOT writable, so {unwritable}. Check PUID/PGID against "
                f"the folder's owner."
            )

    except OSError as e:
        #? A path can raise on stat alone - a broken mount, a permission wall partway up.
        #? Report it rather than letting it 500 the whole settings tab.
        return "error", f"could not check {value}: {e}"

    return "ok", None


#? What stands in for a login typed into an address (1.0.5). Saving refuses one and the clients
#? won't use one, so it only reaches the payload from compose or .env - and it is still a
#? password. Marked rather than dropped: the row says the address has a login in it, and a field
#? showing none would leave you looking for it.
LOGIN_MARK = "•••@"


def _setting(
    key: str,
    value: str | None,
    *,
    effect: str,
    required: bool = False,
    secret: bool = False,
    status: str | None = None,
    detail: str | None = None,
    choices: dict[str, str] | None = None,
    address: bool = False,
) -> dict:
    """
    One row in the settings tab.

    `choices` is value -> label for a setting that only takes certain values, which the tab
    draws as a dropdown rather than a text box that would accept anything and fail on save.

    `address` marks a URL that a secret is sent to (SLSKD_URL, NAVIDROME_URL): any login typed
    into it is shown as LOGIN_MARK, here and in env_value.
    """
    #? Secrets (API keys, the Navidrome password) never leave the process. The tab shows
    #? whether one arrived and nothing else - enough to diagnose "downloads don't work",
    #? without putting a credential in a screenshot somebody pastes into an issue.
    def shown(v: str | None) -> str | None:
        return without_login(v, LOGIN_MARK) if address and v else v

    reported = ("set" if value else None) if secret else (shown(value) or None)

    if status is None:
        status = "ok" if value else ("error" if required else "unset")

    #? An empty compose variable beating a good .env line reads as simply unset, which sends
    #? people to edit the file that was already correct. Always worth calling out by name.
    if shadowed_by_empty_env(key):
        status = "error"
        detail = (
            f"{key} is set to an EMPTY value in the container environment, which overrides "
            f"the value in your .env. Remove the line from your compose file's "
            f"`environment:` block, or give it a literal value - an `{key}=${{{key}}}` entry "
            f"does this whenever the outer variable isn't defined."
        )

    return {
        "key": key,
        "value": reported,
        "source": setting_source(key),
        "status": status,
        "detail": detail,
        "effect": effect,
        "required": required,
        "secret": secret,
        #? Whether the tab may render an input for this, and why not when it may not.
        "editable": key in Config.EDITABLE,
        "locked_reason": Config.NOT_EDITABLE.get(key),
        #? True when this value came from the settings tab rather than the environment. The
        #? tab uses it to say so and to offer "revert to the environment value", which is the
        #? thing that stops an override becoming invisible state nobody remembers setting.
        "overridden": key in Config.OVERRIDDEN,
        #? What reverting would restore. Never sent for secrets.
        "env_value": (
            None if secret else (shown(Config.ENV_VALUES.get(key)) if key in Config.OVERRIDDEN else None)
        ),
        "choices": choices,
    }


def _navidrome_rows() -> list[dict]:
    """
    Where the player at /player/ plays from. All three or none: the player needs a login to ask
    anything, so a URL alone is reported as incomplete rather than as fine.
    """
    url = Config.NAVIDROME_URL
    url_problem = describe_navidrome_url(url) if url else None
    partial = bool(url or Config.NAVIDROME_USER or Config.NAVIDROME_PASSWORD) and not (
        Config.navidrome_configured()
    )
    missing = "all three NAVIDROME_ settings are needed before the player can ask Navidrome anything"

    return [
        _setting(
            "NAVIDROME_URL",
            url,
            effect=(
                "The Navidrome the player at /player/ plays from. deadwax passes the player's "
                "requests on to it, so this is Navidrome's address as seen from inside THIS "
                "container, with its base path if it has one - and the phone only ever needs to "
                "reach deadwax. Changing it takes the password again, typed with it"
            ),
            status="error" if url_problem or (partial and not url) else None,
            detail=f"unusable: {url_problem}" if url_problem else (missing if partial and not url else None),
            address=True,
        ),
        _setting(
            "NAVIDROME_USER",
            Config.NAVIDROME_USER,
            effect=(
                "The Navidrome account the player plays as. Its play counts (and Last.fm or "
                "ListenBrainz scrobbles, if that account has them) are recorded there. It doesn't "
                "need to be an admin - a non-admin account of your own is the one to use"
            ),
            status="error" if partial and not Config.NAVIDROME_USER else None,
            detail=missing if partial and not Config.NAVIDROME_USER else None,
        ),
        _setting(
            "NAVIDROME_PASSWORD",
            Config.NAVIDROME_PASSWORD,
            secret=True,
            effect=(
                "That account's password. It stays in deadwax: the phone is never sent it, or "
                "anything made from it"
            ),
            status="error" if partial and not Config.NAVIDROME_PASSWORD else None,
            detail=missing if partial and not Config.NAVIDROME_PASSWORD else None,
        ),
    ]


#? What the player's cache is, for both of its rows.
PLAYER_CACHE_IS = (
    "Only a cache: safe to delete at any time, and a song that isn't in it is made again from "
    "Navidrome the next time Safari plays it, which only makes that first play start a moment later"
)


def _player_cache_rows() -> list[dict]:
    """
    Where the player keeps the MP4s it makes for Safari, and how much. The folder is checked the way
    the cache itself will check it - the configured path usable, and deadwax's own folder inside it
    a private folder of its own - without making anything.
    """
    configured = Config.PLAYER_CACHE_PATH
    status, detail = _describe_path(
        configured, needs_write=True,
        unwritable="the player can't keep its MP4s there and Safari is sent FLAC",
    )
    if status != "error":
        problem = player_cache.folder_problem(configured)
        if problem:
            status, detail = "error", (
                f"{problem}. Until then Safari is sent FLAC, and its seeks can land seconds off"
            )
    folder = player_cache.cache.directory
    where = f" ({folder})" if folder is not None else ""
    if configured:
        path_effect = (
            f"Where the player keeps FLAC songs repackaged as MP4s for Safari and iPhones, whose "
            f"seeks land only in an MP4 - in a folder of its own inside this one{where}, which "
            f"deadwax makes private and touches nothing else beside. Best on a fast disk (an SSD). "
            f"{PLAYER_CACHE_IS}"
        )
    else:
        path_effect = (
            f"Unset: the player keeps FLAC songs repackaged as MP4s for Safari and iPhones in the "
            f"container's temporary space{where}, which starts empty with every new container. Set "
            f"it to a folder mounted from a fast disk (an SSD) to keep them there; deadwax makes a "
            f"private folder of its own inside it. {PLAYER_CACHE_IS}"
        )

    megabytes = parse_player_cache_mb(Config.PLAYER_CACHE_MB)
    low, high = PLAYER_CACHE_MB_RANGE
    used = megabytes or DEFAULT_PLAYER_CACHE_MB
    size_effect = (
        f"The player's cache holds at most {used} MB of songs, the ones played longest ago cleared "
        f"first (a CD-quality song is 20-60 MB). A song being made has a second copy of itself on "
        f"disk until it is done. When the disk runs short, older songs are cleared to make room, and "
        f"if there still isn't enough Safari is sent the FLAC instead"
    )
    if megabytes is None:
        size_effect = f"unrecognised, so {DEFAULT_PLAYER_CACHE_MB} is used. {size_effect}"

    return [
        _setting(
            "PLAYER_CACHE_PATH",
            configured,
            effect=path_effect,
            status=status,
            detail=detail,
        ),
        _setting(
            "PLAYER_CACHE_MB",
            Config.PLAYER_CACHE_MB,
            effect=size_effect,
            status="ok" if megabytes is not None else "error",
            detail=None if megabytes is not None else f"expected a whole number of MB, {low} to {high}",
        ),
    ]


def _musicbrainz_rows() -> list[dict]:
    """
    The contact MusicBrainz asks for - and, while one is still set, the old hand-written user agent.

    The email row says what is actually sent. That is the only way to see that the version
    really is filled in for you, and it is the first thing somebody debugging a 403 needs.
    """
    email = Config.MUSICBRAINZ_EMAIL
    email_problem = describe_contact(email) if email else None
    contact, source = Config.musicbrainz_contact()
    user_agent = Config.musicbrainz_user_agent()

    sent = (
        f"Sent as: {user_agent}"
        if contact
        else f"Once it is set, requests go out as: {build_user_agent('you@example.com')}"
    )

    rows = [
        _setting(
            "MUSICBRAINZ_EMAIL",
            email,
            #? not required while an old user agent is supplying the contact - nothing is broken
            required=source != "MUSICBRAINZ_USERAGENT",
            effect=(
                "Your email address. MusicBrainz asks every app for a way to reach whoever is "
                "making its requests, and rate limits the ones without - deadwax writes the "
                f"rest of the user agent itself, so it always names the version running. {sent}"
            ),
            status="error" if email_problem else None,
            detail=f"MUSICBRAINZ_EMAIL {email_problem}" if email_problem else None,
        ),
    ]

    #? Only while it is set - or overridden to empty, which has to stay visible to be revertable.
    #? Nobody configuring a new install should be shown a setting they no longer need.
    legacy = Config.MUSICBRAINZ_USERAGENT
    if legacy or "MUSICBRAINZ_USERAGENT" in Config.OVERRIDDEN:
        old = "The old way of identifying deadwax: a whole user agent, written by hand."
        status, detail = "ok", None

        if source == "MUSICBRAINZ_EMAIL":
            effect = f"{old} Ignored now that MUSICBRAINZ_EMAIL is set, so you can remove it."
        elif source == "MUSICBRAINZ_USERAGENT":
            effect = (
                f"{old} Only its contact, {contact}, is still used - deadwax fills in its "
                f"own name and version now. Put that address in MUSICBRAINZ_EMAIL and this "
                f"one can go."
            )
        elif legacy:
            effect, status = old, "error"
            detail = (
                "There's no contact in it that deadwax can find, so it is sent exactly as "
                "written - and MusicBrainz rate limits a user agent without one. Set "
                "MUSICBRAINZ_EMAIL instead."
            )
        else:
            effect, status = f"{old} Cleared here, overriding the environment.", "unset"

        rows.append(
            _setting("MUSICBRAINZ_USERAGENT", legacy, effect=effect, status=status, detail=detail)
        )

    return rows


def _cover_art_row() -> dict:
    """COVER_ART_SIZE, offered as the sizes the Archive actually serves."""
    size = Config.COVER_ART_SIZE
    known = size in COVER_ART_SIZES

    return _setting(
        "COVER_ART_SIZE",
        size,
        effect=COVER_ART_SIZE_NOTES.get(size, "unrecognised - covers are fetched at 500 × 500"),
        status="ok" if known else "error",
        detail=None if known else f"expected one of {', '.join(COVER_ART_SIZES)}",
        choices=COVER_ART_SIZE_CHOICES,
    )


def _country_row() -> dict:
    """COUNTRY_IN_FOLDER, saying what a folder would look like either way."""
    value = (Config.COUNTRY_IN_FOLDER or "off").strip().lower()
    known = value in COUNTRY_CHOICES

    return _setting(
        "COUNTRY_IN_FOLDER",
        Config.COUNTRY_IN_FOLDER,
        effect=(
            "A pressing nothing else tells apart is named by its country: Dummy (1994) [GB]"
            if value == "on"
            else "No country in folder names: Dummy (1994). Two different pressings of one album "
                 "are still kept apart, by catalogue number"
        ),
        status="ok" if known else "error",
        detail=None if known else f"expected one of {', '.join(COUNTRY_CHOICES)}",
        choices=COUNTRY_CHOICES,
    )


def _auto_retry_row() -> dict:
    """AUTO_RETRY_PEER, as an on/off dropdown."""
    value = (Config.AUTO_RETRY_PEER or "off").strip().lower()
    known = value in AUTO_RETRY_CHOICES
    return _setting(
        "AUTO_RETRY_PEER",
        Config.AUTO_RETRY_PEER,
        effect=(
            "A download that fails moves to the next peer from the list you picked it from, "
            "up to three asks each time, skipping any peer already tried"
            if value == "on"
            else "A failed download waits for you - 'Try next peer' on its row moves it on. The "
                 "next peer down may be a different pressing or a worse rip, which is why this "
                 "is off unless you turn it on"
        ),
        status="ok" if known else "error",
        detail=None if known else f"expected one of {', '.join(AUTO_RETRY_CHOICES)}",
        choices=AUTO_RETRY_CHOICES,
    )


#? what the album folder template's preview names - one album with an edition, one without
TEMPLATE_EXAMPLES = (
    {"album": "Wish You Were Here", "original_year": "1975", "year": "2011", "album_artist": "Pink Floyd",
     "disambiguation": "2011 remaster", "media_format": "CD", "country": "GB", "catalog_number": "50999 028955 2 9"},
    {"album": "Dummy", "original_year": "1994", "year": "1994", "album_artist": "Portishead",
     "media_format": "CD", "country": "GB", "catalog_number": "828 553-2"},
)


def _album_folder_row() -> dict:
    """ALBUM_FOLDER_TEMPLATE, previewed on two albums - one with an edition, one without."""
    from src.naming import DEFAULT_ALBUM_FOLDER, TOKENS, validate_template
    from src.organizer import build_album_dirname, sanitize_filename

    value = (Config.ALBUM_FOLDER_TEMPLATE or "").strip()
    problem = validate_template(value) if value else None
    examples = " and ".join(
        f"{sanitize_filename(example['album_artist'])}/{build_album_dirname(example)}"
        for example in TEMPLATE_EXAMPLES
    )
    return _setting(
        "ALBUM_FOLDER_TEMPLATE",
        Config.ALBUM_FOLDER_TEMPLATE,
        effect=(
            f"Names album folders like {examples}. A token left empty takes its brackets with it. "
            f"Tokens: {', '.join('{' + t + '}' for t in TOKENS)}. Albums already filed keep their "
            f"folders until a release is applied to them"
            if not problem else
            f"unusable, so folders are named by the default, {DEFAULT_ALBUM_FOLDER}"
        ),
        status="error" if problem else "ok",
        detail=problem,
    )


def _rename_wait_row() -> dict:
    """RETAG_RENAME_WAIT, in seconds."""
    value = Config.RETAG_RENAME_WAIT
    seconds = parse_rename_wait(value)
    low, high = RENAME_WAIT_RANGE
    #? an unreadable value is read as the default 20, which is not 0 - so it pauses like any other
    pause = 20 if seconds is None else seconds
    if pause == 0:
        effect = ("Applying a release renames the folder straight away. Navidrome loses the album's "
                  "plays, ratings and favourites when its tags and folder change together")
    elif Config.navidrome_usable():
        #? v1.0.3: with the connection there, the number only has to say "don't rename at once".
        #? Usable, not merely filled in: an address the client refuses means the fixed wait below.
        effect = ("Applying a release that changes an album's tags AND its folder writes the tags, "
                  "asks Navidrome until it has scanned them (usually a few seconds), then renames - "
                  "so Navidrome keeps the album's plays, ratings and favourites. If no scan finishes "
                  f"within {SCAN_WAIT_CAP_SECONDS}s, or Navidrome can't be reached, the folder is left "
                  "in place and the editor says so. With Navidrome set up this only has to be more "
                  "than 0; 0 renames straight away")
    else:
        effect = (f"Applying a release that changes an album's tags AND its folder writes the tags, "
                  f"waits {pause}s for Navidrome to see them, then renames - so Navidrome keeps "
                  f"the album's plays, ratings and favourites. Set up Navidrome on the Connections "
                  f"tab and deadwax asks it instead of waiting a fixed time. 0 renames straight away")
    if seconds is None:
        effect = f"unrecognised, so read as 20. {effect}"
    return _setting(
        "RETAG_RENAME_WAIT",
        value,
        effect=effect,
        status="ok" if seconds is not None else "error",
        detail=None if seconds is not None else f"expected whole seconds, {low} to {high}",
    )


def _search_timeout_row() -> dict:
    """SLSKD_SEARCH_TIMEOUT, in seconds."""
    value = Config.SLSKD_SEARCH_TIMEOUT
    seconds = parse_search_timeout(value)
    low, high = SEARCH_TIMEOUT_RANGE
    return _setting(
        "SLSKD_SEARCH_TIMEOUT",
        value,
        effect=(
            f"Each Soulseek search listens for {seconds}s. Peers answer over several seconds, slow "
            "and firewalled ones last - longer finds more, shorter answers sooner"
            if seconds else "unrecognised - searches use 8s"
        ),
        status="ok" if seconds else "error",
        detail=None if seconds else f"expected whole seconds, {low} to {high}",
    )


def _lyrics_row() -> dict:
    """FETCH_LYRICS, as an on/off dropdown."""
    value = Config.FETCH_LYRICS
    known = value in LYRICS_CHOICES

    return _setting(
        "FETCH_LYRICS",
        value,
        effect=(
            "Each album filed from a download has its lyrics looked up on LRCLIB"
            if value == "on"
            else "Lyrics are only fetched when you ask, from the library"
            if value == "off"
            else "unrecognised - lyrics are fetched as albums are filed"
        ),
        status="ok" if known else "error",
        detail=None if known else f"expected one of {', '.join(LYRICS_CHOICES)}",
        choices=LYRICS_CHOICES,
    )


def _lyrics_lead_row() -> dict:
    """LYRICS_LEAD_MS, in words that say which way it moves them."""
    lead = parse_lyrics_lead(Config.LYRICS_LEAD_MS)

    if lead is None:
        effect = "unrecognised - LRCLIB's timings are written as they are"
    elif lead > 0:
        effect = f"Synced lyrics are written {lead} ms earlier than LRCLIB times them"
    elif lead < 0:
        effect = f"Synced lyrics are written {-lead} ms later than LRCLIB times them"
    else:
        effect = "Synced lyrics are written with LRCLIB's own timings"

    return _setting(
        "LYRICS_LEAD_MS",
        Config.LYRICS_LEAD_MS,
        effect=effect,
        status="ok" if lead is not None else "error",
        detail=None if lead is not None else (
            f"expected a whole number of milliseconds, at most {LYRICS_LEAD_LIMIT_MS} either way"
        ),
    )


@router.get("")
@router.get("/")
async def settings():
    """
    Everything the settings tab renders: the server configuration as this process actually
    received it, grouped the way someone troubleshooting would look for it.
    """
    download_status, download_detail = _describe_path(Config.SLSKD_DOWNLOAD_PATH, needs_write=False)
    library_status, library_detail = _describe_path(Config.LIBRARY_PATH, needs_write=True)
    incomplete_status, incomplete_detail = _describe_path(
        Config.SLSKD_INCOMPLETE_PATH, needs_write=True
    )

    url_problem = describe_slskd_url(Config.SLSKD_URL)
    organize_mode = Config.ORGANIZE_MODE
    organize_known = organize_mode in ORGANIZE_MODES

    #? Organizing needs BOTH paths and a mode that acts. Stated as one derived fact because
    #? "why did nothing get filed" has four possible causes and checking them one at a time
    #? is how people end up convinced the feature is broken.
    organizing_blockers = []
    if not Config.SLSKD_DOWNLOAD_PATH:
        organizing_blockers.append("SLSKD_DOWNLOAD_PATH is not set")
    elif download_status == "error":
        organizing_blockers.append("SLSKD_DOWNLOAD_PATH does not resolve inside this container")
    if not Config.LIBRARY_PATH:
        organizing_blockers.append("LIBRARY_PATH is not set")
    elif library_status == "error":
        organizing_blockers.append("LIBRARY_PATH is not usable")
    if organize_mode == "off":
        organizing_blockers.append("ORGANIZE_MODE is 'off'")
    elif organize_mode == "dry_run":
        organizing_blockers.append(
            "ORGANIZE_MODE is 'dry_run', so organizing reports what it would do and writes nothing"
        )

    return {
        #? Rendered in the tab's footer. "What version are you running" is the first question
        #? asked about any bug report, and until now the only way to answer it was to check
        #? which image tag you happened to pull.
        "version": __version__,
        #? Read-only, and the tab says so prominently. See this module's docstring.
        "editable": False,
        "groups": [
            {
                "id": "connections",
                "label": "Connections",
                "note": "Where deadwax fetches metadata and downloads from, and where the player plays from.",
                "settings": [
                    _setting(
                        "SLSKD_URL",
                        Config.SLSKD_URL,
                        required=True,
                        effect=(
                            "The slskd instance searches and downloads go through. Every request "
                            "to it carries the API key, so changing it takes the key again, "
                            "typed with it"
                        ),
                        status="error" if url_problem else "ok",
                        detail=(
                            f"unusable: {url_problem}. It has to be reachable from inside "
                            f"THIS container - if slskd is another container on the same "
                            f"docker network use its service name and internal port "
                            f"(http://slskd:5030), not your host's IP and published port."
                            if url_problem
                            else None
                        ),
                        address=True,
                    ),
                    _setting(
                        "SLSKD_APIKEY",
                        Config.SLSKD_APIKEY,
                        required=True,
                        secret=True,
                        effect="Authenticates against slskd; downloads fail without it",
                    ),
                    _setting(
                        "THEAUDIODB_KEY",
                        Config.THEAUDIODB_KEY,
                        secret=True,
                        effect=(
                            "One of the two sources of artist banners, logos and backgrounds. "
                            "Without either, an artist still gets a photo from Wikimedia "
                            "Commons where there is one"
                        ),
                    ),
                    _setting(
                        "FANARTTV_KEY",
                        Config.FANARTTV_KEY,
                        secret=True,
                        effect=(
                            "The other, and the one whose artwork is voted on by the people "
                            "using it. fanart.tv issues this key per application, so it has to "
                            "be registered by you at fanart.tv rather than shipped with deadwax"
                        ),
                    ),
                    _setting(
                        "FANARTTV_PERSONAL_KEY",
                        Config.FANARTTV_PERSONAL_KEY,
                        secret=True,
                        effect=(
                            "Optional, and only alongside the key above: your own fanart.tv "
                            "account key, which shows images added in the last week rather than "
                            "waiting for them"
                        ),
                    ),
                    *_musicbrainz_rows(),
                    *_navidrome_rows(),
                ],
            },
            {
                "id": "paths",
                "label": "Paths",
                "note": (
                    "All of these are paths as seen from INSIDE this container, which is not "
                    "always the path you'd type on the host."
                ),
                "settings": [
                    _setting(
                        "SLSKD_DOWNLOAD_PATH",
                        Config.SLSKD_DOWNLOAD_PATH,
                        effect="Where slskd writes finished downloads, so deadwax can find them",
                        status=download_status,
                        detail=download_detail,
                    ),
                    _setting(
                        "LIBRARY_PATH",
                        Config.LIBRARY_PATH,
                        effect="Where organized music is filed, and what the library tab reads",
                        status=library_status,
                        detail=library_detail,
                    ),
                    _setting(
                        "SLSKD_INCOMPLETE_PATH",
                        Config.SLSKD_INCOMPLETE_PATH,
                        effect=(
                            "The slskd partial-download folder. Optional: set it and cancelling "
                            "a download also deletes its half-finished file, and the empty "
                            "folders slskd leaves behind there are cleared every ten minutes. "
                            "Leave it unset and slskd keeps the partial so a retry can resume "
                            "from it"
                        ),
                        status=incomplete_status,
                        detail=incomplete_detail,
                    ),
                    _setting(
                        "DB_PATH",
                        Config.DB_PATH,
                        effect=(
                            "The sqlite file holding job state and the metadata queue. Needs "
                            "to be on a persistent volume or you lose it on every restart"
                        ),
                    ),
                    *_player_cache_rows(),
                ],
            },
            {
                "id": "organizing",
                "label": "Organizing",
                "note": (
                    "Organizing is the only thing here that writes to your filesystem, which "
                    "is why it starts in dry_run."
                ),
                "settings": [
                    _setting(
                        "ORGANIZE_MODE",
                        organize_mode,
                        effect=ORGANIZE_MODES.get(
                            organize_mode, "unrecognised - the organizer falls back to dry_run"
                        ),
                        status="ok" if organize_known else "error",
                        detail=(
                            None
                            if organize_known
                            else f"expected one of {', '.join(ORGANIZE_MODES)}"
                        ),
                        choices={mode: mode for mode in ORGANIZE_MODES},
                    ),
                    _country_row(),
                    _album_folder_row(),
                    _rename_wait_row(),
                ],
            },
            {
                "id": "soulseek",
                "label": "Soulseek searches",
                "note": "How long each search listens for answers. A search runs under every name "
                        "the artist has recorded as, side by side, so this is the wait for all of them.",
                "settings": [_search_timeout_row()],
            },
            {
                "id": "downloads",
                "label": "When a download fails",
                "note": (
                    "A download keeps the rest of the candidates list it was picked from, as "
                    "it was shown - your filters and sort - so a failed one can move to the "
                    "next peer instead of starting the search again."
                ),
                "settings": [_auto_retry_row()],
            },
            {
                "id": "cover-art",
                "label": "Cover art",
                "note": (
                    "What 'Get cover' and the metadata editor save into an album's folder, from "
                    "the Cover Art Archive. Covers already on disk are kept - replace one from "
                    "the metadata editor, where you can compare the two first."
                ),
                "settings": [_cover_art_row()],
            },
            {
                "id": "lyrics",
                "label": "Lyrics",
                "note": (
                    "From LRCLIB, saved as a .lrc file beside each track - synced where LRCLIB "
                    "has timings, which Navidrome, Jellyfin and Kodi all read. A .lrc already "
                    "there is never replaced. 'Get lyrics' in the library works whatever this "
                    "is set to. A new lead applies to lyrics fetched from then on; re-time the "
                    "ones already saved below."
                ),
                "settings": [_lyrics_row(), _lyrics_lead_row()],
            },
        ],
        "organize_modes": ORGANIZE_MODES,
        "organizing": {
            "enabled": not organizing_blockers,
            "blockers": organizing_blockers,
        },
    }


# ==============================================================================
# Writing
# ==============================================================================


class SettingUpdate(BaseModel):
    """One setting to change. `value` of null means 'revert to the environment'."""
    key: str
    value: str | None = None


def _validate(key: str, value: str) -> str | None:
    """
    Why this value cannot be stored, or None if it can.

    The line drawn here is between DEFINITIONALLY wrong and ENVIRONMENTALLY wrong, and it
    matters:

      Definitionally wrong is rejected. An ORGANIZE_MODE of "sideways" or a URL with no
      scheme can never work, whatever else changes, so storing it would only produce a
      confusing failure later somewhere less informative.

      Environmentally wrong is STORED and reported. A path that doesn't resolve today may be
      a volume the user is about to mount, and refusing it would mean the only way to fix a
      broken setup is to edit the compose file - which is exactly what this tab exists to
      avoid. The row renders its own validation state, so nothing is hidden by allowing it.
    """
    if key == "ORGANIZE_MODE" and value not in ORGANIZE_MODES:
        return f"expected one of {', '.join(ORGANIZE_MODES)}"

    #? Required, so an empty one is wrong too - and since 1.0.5 held to what NAVIDROME_URL is: no
    #? login, no ? or #. Every request to it carries the API key. See describe_slskd_url.
    if key == "SLSKD_URL":
        problem = describe_slskd_url(value)
        if problem:
            return problem

    #? An empty or malformed contact can never work: MusicBrainz rate limits a user agent it
    #? can't reach anybody through, and httpx refuses a header it can't encode. Revert is the way
    #? back to the environment's value - saving a blank would override it with nothing.
    if key == "MUSICBRAINZ_EMAIL":
        problem = describe_contact(value)
        if problem:
            return problem

    #? Optional, so only a URL that is there can be wrong - and more makes it wrong than a slskd
    #? one, since every request to it carries the login. See describe_navidrome_url.
    if key == "NAVIDROME_URL" and value:
        problem = describe_navidrome_url(value)
        if problem:
            return problem

    if key == "COVER_ART_SIZE" and value not in COVER_ART_SIZES:
        return f"expected one of {', '.join(COVER_ART_SIZES)}"

    if key == "COUNTRY_IN_FOLDER" and value not in COUNTRY_CHOICES:
        return f"expected one of {', '.join(COUNTRY_CHOICES)}"

    if key == "ALBUM_FOLDER_TEMPLATE" and value.strip():
        from src.naming import validate_template
        problem = validate_template(value)
        if problem:
            return problem

    if key == "SLSKD_SEARCH_TIMEOUT" and parse_search_timeout(value) is None:
        low, high = SEARCH_TIMEOUT_RANGE
        return f"expected whole seconds, {low} to {high} - 8 is the default"

    if key == "RETAG_RENAME_WAIT" and parse_rename_wait(value) is None:
        low, high = RENAME_WAIT_RANGE
        return f"expected whole seconds, {low} to {high} - 20 is the default, 0 renames straight away"

    if key == "AUTO_RETRY_PEER" and value not in AUTO_RETRY_CHOICES:
        return f"expected one of {', '.join(AUTO_RETRY_CHOICES)}"

    if key == "FETCH_LYRICS" and value not in LYRICS_CHOICES:
        return f"expected one of {', '.join(LYRICS_CHOICES)}"

    if key == "PLAYER_CACHE_MB" and parse_player_cache_mb(value) is None:
        low, high = PLAYER_CACHE_MB_RANGE
        return (f"expected a whole number of MB, {low} to {high} - {DEFAULT_PLAYER_CACHE_MB} is the "
                f"default")

    if key == "LYRICS_LEAD_MS" and parse_lyrics_lead(value) is None:
        return (f"expected a whole number of milliseconds, at most {LYRICS_LEAD_LIMIT_MS} "
                f"either way - 300, say, or -200 to move them later")

    return None


#? An address that is sent a secret with every request -> that secret, and what a save moving the
#? address without it is told. Navidrome since 1.0.3, slskd since 1.0.5.
SECRET_FOR_ADDRESS = {
    "NAVIDROME_URL": (
        "NAVIDROME_PASSWORD",
        "type the Navidrome password again with the new address - deadwax won't send the saved "
        "one to an address it wasn't entered for",
    ),
    "SLSKD_URL": (
        "SLSKD_APIKEY",
        "type the slskd API key again with the new address - deadwax won't send the saved one "
        "to an address it wasn't entered for",
    ),
}


def _moved_without_secret(updates: list[SettingUpdate]) -> dict[str, str]:
    """
    Each address this batch may not point somewhere new, with why. Empty when it may.

    Every request to NAVIDROME_URL carries a token made from the saved password, and Navidrome
    accepts the same token and salt again for as long as the password stands; every request to
    SLSKD_URL carries the API key itself, which is full control of slskd. deadwax has no login, so
    anyone who can reach it could re-point either address with curl and collect the secret on the
    next ping (the 1.0.3 audit did it to Navidrome). A new address therefore takes its secret
    again, in the same save.

    Not a change, and so allowed: saving the address it already is, clearing it (nothing is sent
    anywhere - an empty SLSKD_URL is refused anyway, as not set), and reverting it (that address
    is the environment's, which is the admin's). Nor when no secret is set yet, from here or the
    environment - there is nothing to send. Reverting or blanking the secret is not typing it.
    """
    wanted = {update.key: update.value for update in updates}
    refused = {}

    for address, (secret, reason) in SECRET_FOR_ADDRESS.items():
        url = (wanted.get(address) or "").strip()
        if not url or url == (getattr(Config, address) or "").strip() or not getattr(Config, secret):
            continue
        if (wanted.get(secret) or "").strip():
            continue
        refused[address] = reason

    return refused


@router.put("")
@router.put("/")
async def update_settings(updates: list[SettingUpdate], request: Request):
    """
    Save a batch of settings, apply them live, and report the result.

    A BATCH rather than one call per setting, because the tab has a single save button and a
    half-applied save is the worst outcome available: some settings changed, some not, and no
    way to tell which from looking. Everything is validated first and the whole batch is
    refused if anything in it is invalid.
    """
    store = request.app.state.store

    if not store.available:
        raise HTTPException(
            status_code=503,
            detail=(
                "the database isn't available, so settings can't be saved. Check DB_PATH "
                "points at a writable volume."
            ),
        )

    #? Validate the whole batch before writing any of it.
    problems = {}
    for update in updates:
        if update.key in Config.NOT_EDITABLE:
            problems[update.key] = Config.NOT_EDITABLE[update.key]
        elif update.key not in Config.EDITABLE:
            problems[update.key] = "not a setting that can be changed here"
        elif update.value is not None:
            problem = _validate(update.key, update.value)
            if problem:
                problems[update.key] = problem

    #? After validation, so an address that is unusable anyway is told that rather than this
    for key, reason in _moved_without_secret(updates).items():
        problems.setdefault(key, reason)

    if problems:
        raise HTTPException(
            status_code=400,
            detail="; ".join(f"{key}: {reason}" for key, reason in problems.items()),
        )

    #? Which cached clients this batch invalidates. Collected as a set so changing both the
    #? slskd URL and its API key rebuilds that client once rather than twice.
    invalidate = set()
    changed = []

    for update in updates:
        if update.value is None:
            await store.clear_setting(update.key)
        else:
            await store.set_setting(update.key, update.value)

        changed.append(update.key)
        target = Config.EDITABLE.get(update.key)
        if target:
            invalidate.add(target)

    #? Re-read everything from the store rather than mutating Config per key, so the in-memory
    #? state is exactly what the next restart would produce. A "saved" that leaves the process
    #? in a state the database wouldn't reproduce is a lie that only shows up on restart.
    Config.apply_overrides(store.stored_settings())

    #? Config is read at the point of use, so most settings are already live. The cached
    #? clients are the exception: they are built once, so drop them and let the next call
    #? rebuild against the new values.
    if "slskd" in invalidate:
        await request.app.state.slskd_client.close_client()
        logger.info("slskd client dropped, it will rebuild with the new settings")

    if "musicbrainz" in invalidate:
        await request.app.state.musicbrainz_client.close_client()
        #? said out loud, because the point of the email setting is that the rest of the user
        #? agent is filled in for you - and this is where you get to see that it was
        logger.info(
            f"MusicBrainz user agent is now: {Config.musicbrainz_user_agent() or 'not set'}",
            extra={"frontend": True},
        )

    if "navidrome" in invalidate:
        from src.api.navidrome_endpoint import navidrome
        from src.routes.store_album import forget_navidrome_ids

        await navidrome.close_client()
        #? another Navidrome (or another account on it) has other album ids (2.0.0-player.17)
        forget_navidrome_ids()
        logger.info("Navidrome client dropped, it will rebuild with the new address")

    if "library" in invalidate:
        #? The scan cache keys on folder mtime under the OLD root, so it is meaningless now.
        from src.library import clear_scan_cache

        clear_scan_cache()
        logger.info("library scan cache cleared, the new path will be read fresh")

    logger.info(
        f"settings updated from the interface: {', '.join(changed)}",
        extra={"frontend": True},
    )

    return await settings()
