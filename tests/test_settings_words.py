"""
The settings are described for the person using them (2.0.1).

James, 2026-10-23: "I need the descriptions to be more user oriented and not testing oriented. Like where
gapless says 'an experiment' is unacceptable." The words of every setting - You's notes and choices, and
every row, group note, dropdown label and locked reason of Server settings - had been written while each
feature was on trial, so some described how it was built or what had been checked on a phone. What this
holds is the floor under the rewrite: none of those words say "experiment", "trial", "test", "verified" or
a build's version ("2.0.0-player.N").

Two ways in, so a branch nobody's set-up reaches is read too:

  - the server's words as the settings route answers them, under a plain install, a filled-in one and a
    broken one (every "unrecognised" branch), logins off and on - and the tables they come from;
  - the user-facing literals of the app's settings files: their source with the comments taken out, which
    is everything the page can show (code identifiers can't hold these words: UNVERIFIED, `unverified` are
    one word each, so `\\bverified\\b` passes them).

ui/test/you.sim.cjs and ui/test/settings.sim.cjs pin the words themselves.
"""

import asyncio
import io
import re
import sys
import tokenize
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from src import config  # noqa: E402
from src.config import Config  # noqa: E402
from src.routes import settings as settings_route  # noqa: E402

REPO = Path(__file__).resolve().parent.parent

#? the words a setting's description must never use - what a test note says, not what a setting does
TESTING_WORDS = re.compile(r"experiment|\btrial|\bverified\b|\btest(s|ed|ing)?\b|2\.0\.0-player|\bplayer\.\d", re.I)

#? every file whose literals You or Server settings show
APP_FILES = [
    "ui/src/app/You.tsx",
    "ui/src/app/GaplessChoice.tsx",
    "ui/src/app/QualityChoice.tsx",
    "ui/src/app/NormalizationChoice.tsx",
    "ui/src/app/LookChoice.tsx",
    "ui/src/app/WindDownChoice.tsx",
    "ui/src/app/GettingChoices.tsx",
    "ui/src/app/ConfirmCancelChoice.tsx",
    "ui/src/lib/getSettings.ts",
    "ui/src/app/ServerSettings.tsx",
    "ui/src/components/SettingsView.tsx",
    "ui/src/lib/serverSettings.ts",
    "ui/src/components/RetimeLyrics.tsx",
    "ui/src/components/MusicBrainzAnswers.tsx",
]


def strings_in(value) -> list[str]:
    """Every string anywhere in an answer."""
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [text for key, item in value.items() for text in strings_in(key) + strings_in(item)]
    if isinstance(value, (list, tuple, set)):
        return [text for item in value for text in strings_in(item)]
    return []


def offending(texts) -> list[str]:
    return [text for text in texts if TESTING_WORDS.search(text)]


def without_comments(source: str) -> str:
    """A TypeScript file's source with its comments gone: block and JSX comments, then line comments (never a
    URL's `//`, which follows a colon)."""
    source = re.sub(r"/\*[\s\S]*?\*/", "", source)
    return re.sub(r"(^|[^:])//.*$", r"\1", source, flags=re.M)


def answer_under(monkeypatch, **values) -> dict:
    for name, value in values.items():
        monkeypatch.setattr(Config, name, value)
    return asyncio.run(settings_route.settings())


PLAIN = {}
FILLED = {
    "SLSKD_URL": "http://slskd:5030", "SLSKD_APIKEY": "key", "NAVIDROME_URL": "http://navidrome:4533",
    "NAVIDROME_USER": "deadwax", "NAVIDROME_PASSWORD": "pw", "MUSICBRAINZ_EMAIL": "me@example.com",
    "MUSICBRAINZ_USERAGENT": "old/1.0 ( me@example.com )", "ORGANIZE_MODE": "move", "COUNTRY_IN_FOLDER": "on",
    "AUTO_RETRY_PEER": "on", "FETCH_LYRICS": "off", "LYRICS_LEAD_MS": "300", "COVER_ART_SIZE": "full",
    "RETAG_RENAME_WAIT": "0", "AUTH_MODE": "on", "DEADWAX_SECRET_KEY": "x" * 64, "DEADWAX_ADMIN_PASSWORD": "short",
}
BROKEN = {
    "SLSKD_URL": "slskd", "NAVIDROME_URL": "navidrome", "NAVIDROME_USER": None, "MUSICBRAINZ_EMAIL": "nobody",
    "MUSICBRAINZ_USERAGENT": "no contact here", "ORGANIZE_MODE": "sideways", "COUNTRY_IN_FOLDER": "maybe",
    "AUTO_RETRY_PEER": "often", "FETCH_LYRICS": "sometimes", "LYRICS_LEAD_MS": "soon", "COVER_ART_SIZE": "huge",
    "RETAG_RENAME_WAIT": "later", "SLSKD_SEARCH_TIMEOUT": "forever", "PLAYER_CACHE_MB": "lots",
    "MUSICBRAINZ_CACHE_MB": "lots", "ALBUM_FOLDER_TEMPLATE": "{nope}", "AUTH_MODE": "maybe",
    "DEADWAX_SECRET_KEY": "short", "SLSKD_DOWNLOAD_PATH": "/nowhere/at/all", "LIBRARY_PATH": "/nowhere/either",
}


@pytest.mark.parametrize("values", [PLAIN, FILLED, BROKEN], ids=["plain", "filled", "broken"])
def test_no_server_setting_reads_as_a_test_note(monkeypatch, values):
    answer = answer_under(monkeypatch, **values)
    #? and as someone given Settings and the log sees it: the admins-only rows locked, in their words
    seen = settings_route._as_seen_by(answer, "someone")
    assert offending(strings_in(answer) + strings_in(seen)) == []


def test_no_table_a_setting_is_described_from_reads_as_a_test_note():
    tables = [
        settings_route.ORGANIZE_MODES, settings_route.ORGANIZE_MODE_CHOICES, settings_route.COUNTRY_CHOICES,
        settings_route.AUTO_RETRY_CHOICES, settings_route.LYRICS_CHOICES, settings_route.COVER_ART_SIZE_CHOICES,
        settings_route.COVER_ART_SIZE_NOTES, settings_route.ADMINS_ONLY, settings_route.PLAYER_CACHE_IS,
        settings_route.MUSICBRAINZ_CACHE_IS, Config.NOT_EDITABLE, config.LOGINS_LOCKED,
    ]
    assert offending(strings_in(tables)) == []


def test_no_string_the_settings_route_can_say_reads_as_a_test_note():
    """Every string literal in the route - f-strings' words included - but the docstrings, which are no row's."""
    source = (REPO / "src/routes/settings.py").read_text(encoding="utf-8")
    tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    said = []
    for at, token in enumerate(tokens):
        if token.type not in (tokenize.STRING, getattr(tokenize, "FSTRING_MIDDLE", -1)):
            continue
        before = next((t for t in reversed(tokens[:at]) if t.type not in (tokenize.NL, tokenize.COMMENT)), None)
        #? a docstring: a string that is a statement of its own
        if token.type == tokenize.STRING and (before is None or before.type in (tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT)):
            continue
        said.append(token.string)
    assert said and offending(said) == []


def test_the_organize_modes_dropdown_names_them_in_words_with_the_values_compose_takes():
    assert list(settings_route.ORGANIZE_MODE_CHOICES) == list(settings_route.ORGANIZE_MODES)
    assert all(label[0].isupper() and "_" not in label for label in settings_route.ORGANIZE_MODE_CHOICES.values())


@pytest.mark.parametrize("path", APP_FILES)
def test_no_setting_words_in_the_app_read_as_a_test_note(path):
    source = without_comments((REPO / path).read_text(encoding="utf-8"))
    assert [line.strip() for line in source.splitlines() if TESTING_WORDS.search(line)] == []


def test_the_scan_finds_what_it_is_for():
    """The scan itself, against what You said until 2.0.1 - and a comment, which it leaves alone."""
    assert offending(["An experiment: it shortens the pause between songs"]) != []
    assert offending(["Verified on an iPhone", "since 2.0.0-player.62", "on trial"]) != [] and len(offending(["a test"])) == 1
    assert without_comments("x // An experiment\n/* trial */ <p>{/* verified */}Plays</p> 'https://x'") == "x \n <p>{}Plays</p> 'https://x'"
    assert offending(["UNVERIFIED", "access.unverified", "latest", "contest"]) == []


#? (2.0.1, after review) what the reviewers found the rewrite said wrongly, each held to its fix


def cache_size_words(monkeypatch, value) -> str:
    answer = answer_under(monkeypatch, PLAYER_CACHE_MB=value)
    return next(text for text in strings_in(answer) if "cache holds at most" in text)


def test_the_player_cache_says_a_few_gb_suits_it_better_only_where_that_holds(monkeypatch):
    assert "a few GB suits it better" in cache_size_words(monkeypatch, None)
    assert "a few GB suits it better" in cache_size_words(monkeypatch, "512")
    #? never to an admin who has already given it more
    assert "suits it better" not in cache_size_words(monkeypatch, "8000")
    assert "suits it better" not in cache_size_words(monkeypatch, "20480")


def test_deadwax_s_own_account_is_not_said_to_carry_everything(monkeypatch):
    """With logins on each person plays as their own account - the NAVIDROME_USER row says so - so its lock
    can't say everything deadwax does for everyone goes through deadwax's."""
    lock = settings_route._SHARED_ACCOUNT_LOCK
    assert "everything" not in lock and "deadwax's own Navidrome account" in lock
    answer = answer_under(monkeypatch, **FILLED)
    assert any("each person plays as their own account" in text for text in strings_in(answer))


def test_organizing_names_its_modes_in_the_dropdown_s_words(monkeypatch, tmp_path):
    for mode, label in (("dry_run", "Dry run"), ("off", "Off")):
        answer = answer_under(monkeypatch, SLSKD_DOWNLOAD_PATH=str(tmp_path), LIBRARY_PATH=str(tmp_path), ORGANIZE_MODE=mode)
        blockers = answer["organizing"]["blockers"]
        assert blockers == [b for b in blockers if "'" not in b and "dry_run" not in b]
        assert any(f"set to {label}" in blocker for blocker in blockers)
    group = next(g for g in answer_under(monkeypatch)["groups"] if g["id"] == "organizing")
    assert "Dry run" in group["note"] and "dry_run" not in group["note"]
    #? the caches write files too: organizing is the one that files or moves your music
    assert "only thing here that writes" not in group["note"]


def test_the_guide_s_normalization_off_keeps_maximum_quality_s_exception():
    """The app's Off note says "unless Maximum quality converts it"; configuration.md's Playback table and the guide's
    "Off is bit-perfect" paragraph must too, or a 24/192 FLAC resampled under the default reads as bit for bit."""
    app = (REPO / "ui/src/app/NormalizationChoice.tsx").read_text(encoding="utf-8")
    assert "unless Maximum quality converts it" in app
    row = next(line for line in (REPO / "docs/configuration.md").read_text(encoding="utf-8").splitlines()
               if line.startswith("| Normalization |"))
    assert "bit for bit, unless Maximum quality converts it" in row
    paragraph = next(block for block in (REPO / "docs/player.md").read_text(encoding="utf-8").split("\n\n")
                     if block.startswith("**Off is bit-perfect.**"))
    assert "unless Maximum quality converts it" in paragraph


def test_the_retry_setting_names_the_button_as_requests_has_it():
    """AUTO_RETRY_PEER's words name the button an admin goes looking for: it is Next peer, on a failed download in
    Requests - there is no "Try next peer" and no downloads panel since the main page retired. (2.0.3, the compose
    prune) .env.example no longer carries the setting - it is set in Server settings - so configuration.md's row is
    what says it."""
    env = (REPO / ".env.example").read_text(encoding="utf-8")
    assert "AUTO_RETRY_PEER" not in env
    row = next(line for line in (REPO / "docs/configuration.md").read_text(encoding="utf-8").splitlines()
               if line.startswith("| `AUTO_RETRY_PEER` | `off` | `on` moves"))
    assert "Try next peer" not in row and "downloads panel" not in row
    assert "**Next peer** on a failed download, in Requests, works either way" in row
