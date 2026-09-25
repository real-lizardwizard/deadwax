import os
import re
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


def describe_slskd_url(url: str | None) -> str | None:
    """Return a human explanation of why this URL is unusable, or None if it's fine."""
    if not url:
        return "not set"

    if "://" not in url:
        return f"missing the scheme - use http://{url} rather than {url}"

    scheme, _, rest = url.partition("://")

    if scheme not in ("http", "https"):
        return f"unsupported scheme '{scheme}', expected http or https"

    if not rest.strip("/"):
        return "has a scheme but no host"

    return None


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
    #? attribute at the point of use rather than captured at import. The two cached clients
    #? are the exception, and `invalidates` names the one to rebuild - see the settings route.
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
        #? read per lookup by the artist image client, so nothing to rebuild here either
        "THEAUDIODB_KEY": None,
        "FANARTTV_KEY": None,
        "FANARTTV_PERSONAL_KEY": None,
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

    @classmethod
    def exists(cls, env_var: str):
        value = os.getenv(env_var)

        if not value:
            logger.error(f"{env_var} not set either in .env config file or environment")

        return value

    @classmethod
    def check(cls):
        #? MusicBrainz is reported separately, by report_musicbrainz(), once the settings tab's
        #? overrides are in - see its docstring for why it can't happen here.

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

        else: logger.info(f"SLSKD_DOWNLOAD_PATH found!")

        if cls.SLSKD_INCOMPLETE_PATH:
            logger.info("SLSKD_INCOMPLETE_PATH found! cancelled downloads will take their partial files with them")

        else:
            logger.info(
                "SLSKD_INCOMPLETE_PATH not set, so cancelling a download leaves its partial "
                "file in slskd's incomplete folder (which is what lets slskd resume it)"
            )

        if not cls.LIBRARY_PATH:
            logger.warning("LIBRARY_PATH not found in environment, organizing downloaded files will be disabled")

        else: logger.info(f"LIBRARY_PATH found!")

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
    def organizing_enabled(cls) -> bool:
        return bool(cls.SLSKD_DOWNLOAD_PATH and cls.LIBRARY_PATH and cls.ORGANIZE_MODE != "off")
