"""
The short compose file, the image's defaults and every environment variable in one list (2.0.3).

James (2026-10-23): "can we prune the docker compose a bit so that most things default to a sensible value and
can be edited within the app? and then just a big list of available environment variables and what they do".
So the compose example holds what Docker needs - the image, the mounts, the port and `env_file: .env` - and no
setting Server settings can edit; the image carries the container's own side of the two mounts
(SLSKD_DOWNLOAD_PATH=/downloads, LIBRARY_PATH=/music) while the code keeps no default for them outside it; and
docs/configuration.md's "Environment variables" lists every variable deadwax reads, so a new one can't arrive
undocumented. See "A short compose file, and every environment variable in one list" in notes/backend-gotchas.md.
"""

import re
from pathlib import Path

from src import config
from src.config import DEFAULT_DB_PATH, DEFAULT_MUSICBRAINZ_CACHE_MB, DEFAULT_PLAYER_CACHE_MB, LOGIN_SETTINGS, Config
from src.naming import DEFAULT_ALBUM_FOLDER

REPO = Path(__file__).resolve().parent.parent

#? what reads an environment variable by name: config.py's _env, os.getenv (same_origin's TRUSTED_ORIGINS), and
#? os.environ in either form - in src/, and the image's start-up script's ${NAME:-default}
READS = (
    re.compile(r'''\b_env\(\s*["']([A-Z][A-Z0-9_]*)["']'''),
    re.compile(r'''\bos\.getenv\(\s*["']([A-Z][A-Z0-9_]*)["']'''),
    re.compile(r'''\bos\.environ(?:\.get\(\s*|\[\s*)["']([A-Z][A-Z0-9_]*)["']'''),
)
ENTRYPOINT_READS = re.compile(r"\$\{([A-Z][A-Z0-9_]*):-")
#? a row of the list: its first cell, one variable or two joined with " / " (PUID / PGID)
ROW = re.compile(r"^\| `([A-Z][A-Z0-9_]*)`(?: / `([A-Z][A-Z0-9_]*)`)? \|")


def _read_by_deadwax() -> set[str]:
    names: set[str] = set()
    for path in (REPO / "src").rglob("*.py"):
        text = path.read_text(encoding="utf-8")
        for pattern in READS:
            names.update(pattern.findall(text))
    names.update(ENTRYPOINT_READS.findall((REPO / "docker-entrypoint.sh").read_text(encoding="utf-8")))
    return names


def _section(title: str, level: str = "##") -> str:
    text = (REPO / "docs/configuration.md").read_text(encoding="utf-8")
    body = text.split(f"\n{level} {title}\n", 1)[1]
    #? up to the next heading of the same level or above
    stops = [m.start() for m in re.finditer(r"^#{1,%d} " % len(level), body, re.MULTILINE)]
    return body[:stops[0]] if stops else body


def _rows(section: str) -> list[str]:
    names = []
    for line in section.splitlines():
        match = ROW.match(line)
        if match:
            names.extend(name for name in match.groups() if name)
    return names


def _listed() -> set[str]:
    return set(_rows(_section("Environment variables")))


def _compose() -> str:
    return (REPO / "docker-compose.example.yml").read_text(encoding="utf-8")


# ----------------------------------------------------------------- the list

def test_the_scan_finds_what_deadwax_is_known_to_read():
    """The scan is only as good as its patterns: every setting Config knows, TRUSTED_ORIGINS (os.getenv), the removed
    DEADWAX_ADMINS (still read, to say it's ignored) and the start-up script's PUID/PGID are all found by it."""
    found = _read_by_deadwax()
    known = set(Config.EDITABLE) | set(Config.NOT_EDITABLE) | {"TRUSTED_ORIGINS", "DEADWAX_ADMINS", "PUID", "PGID"}
    assert known <= found, sorted(known - found)


def test_every_variable_deadwax_reads_is_in_the_docs_list():
    """A variable added to src/ (or to the start-up script) without a row in configuration.md's list fails here."""
    missing = _read_by_deadwax() - _listed()
    assert not missing, f"read by deadwax but not in docs/configuration.md#environment-variables: {sorted(missing)}"


def test_the_docs_list_names_nothing_deadwax_does_not_read():
    """The other way round: a row for a variable nothing reads (a typo, or one taken out of the code) fails too."""
    extra = _listed() - _read_by_deadwax()
    assert not extra, f"in the docs list but read nowhere: {sorted(extra)}"


def test_the_list_s_tables_split_as_the_settings_do():
    """'Set in the app' is exactly what Server settings may write (Config.EDITABLE); 'Environment only' holds every
    setting it may not (Config.NOT_EDITABLE: DB_PATH and the logins) and TRUSTED_ORIGINS, which it doesn't show."""
    in_app = _rows(_section("Set in the app (or here)", "###"))
    assert set(in_app) == set(Config.EDITABLE) and len(in_app) == len(set(in_app))
    env_only = set(_rows(_section("Environment only", "###")))
    assert set(Config.NOT_EDITABLE) | {"TRUSTED_ORIGINS"} <= env_only
    assert not env_only & set(Config.EDITABLE)
    for line in _section("Environment only", "###").splitlines():
        match = ROW.match(line)
        if match and match.group(1) in Config.NOT_EDITABLE:
            assert "shown, locked" in line, line


def test_the_list_gives_the_defaults_the_code_has():
    """Each default the list states for a setting with one in the code is the code's (read from Config's source,
    since a test run's environment may set them)."""
    source = (REPO / "src/config.py").read_text(encoding="utf-8")
    section = _section("Environment variables")
    checked = 0
    for name, default in re.findall(r'^\s+([A-Z][A-Z0-9_]*) = _env\("\1", "([^"]+)"\)$', source, re.MULTILINE):
        row = next(line for line in section.splitlines() if line.startswith(f"| `{name}` |"))
        assert row.startswith(f"| `{name}` | `{default}` |"), row
        checked += 1
    assert checked >= 9


def test_the_list_gives_the_defaults_the_code_computes():
    """(after review) The defaults the test above can't read as a literal: a number's constant, the folder template's
    (the code's "" means naming's own), and DB_PATH's (default_db_path())."""
    section = _section("Environment variables")
    for name, default in (("PLAYER_CACHE_MB", DEFAULT_PLAYER_CACHE_MB), ("MUSICBRAINZ_CACHE_MB", DEFAULT_MUSICBRAINZ_CACHE_MB),
                          ("ALBUM_FOLDER_TEMPLATE", DEFAULT_ALBUM_FOLDER), ("DB_PATH", DEFAULT_DB_PATH)):
        row = next(line for line in section.splitlines() if line.startswith(f"| `{name}` |"))
        assert row.startswith(f"| `{name}` | `{default}` "), row


# ----------------------------------------------------------------- the compose example

def test_no_setting_the_app_can_edit_is_in_the_compose_example():
    """Everything Server settings edits starts at its default and is set there: the compose example sets none of them,
    not even commented out - nor any other variable, since it has no environment: block (a line there would beat .env,
    even an empty one). It passes .env in, for the secrets and the environment-only settings."""
    compose = _compose()
    assert "environment:" not in compose
    for name in sorted(_read_by_deadwax()):
        assert not re.search(rf"\b{name}=", compose), name
    env_file = compose.index("env_file:")
    #? (after review) optional: compose refuses a missing required env_file before deadwax can say a word, and a
    #? Komodo stack with an empty Environment may write no .env at all
    following = [line.strip() for line in compose[env_file:].split("\n")[1:3]]
    assert following[0].startswith("- path: .env  #") and following[1].startswith("required: false  #"), following
    assert "docs/configuration.md#environment-variables" in compose


def test_the_compose_example_mounts_where_the_image_looks():
    """The container's side of each mount is the image's own default: /downloads and /music (the dockerfile's ENV),
    /config (the database's default folder)."""
    compose = _compose()
    dockerfile = (REPO / "dockerfile").read_text(encoding="utf-8")
    env_block = dockerfile[dockerfile.index("\nENV "):]
    env_block = env_block[:env_block.index("\n\n")]
    for name, inside in (("SLSKD_DOWNLOAD_PATH", "/downloads"), ("LIBRARY_PATH", "/music")):
        assert re.search(rf"\b{name}={inside}\b", env_block), name
        assert re.search(rf"^      - /path/to/[^:]+:{inside}  # ", compose, re.MULTILINE), inside
    config = str(Path(DEFAULT_DB_PATH).parent)
    assert re.search(rf"^      - /path/to/[^:]+:{config}  # ", compose, re.MULTILINE)


def test_the_code_keeps_no_default_for_the_two_paths_outside_the_image():
    """Only the image fills them in: outside it (the dev setup, a plain python -m src.main) both stay unset until the
    environment sets them, and organizing stays off - never a /music the code made up."""
    source = (REPO / "src/config.py").read_text(encoding="utf-8")
    for name in ("SLSKD_DOWNLOAD_PATH", "LIBRARY_PATH"):
        assert re.search(rf'^    {name} = _env\("{name}"\)$', source, re.MULTILINE), name


# ----------------------------------------------------------------- .env.example

def test_the_example_env_carries_only_what_the_app_cant_or_shouldnt_hold():
    """Its lines are the secrets (and the address each goes with: a secret from the environment is only ever sent to
    the environment's address), PUID/PGID and the environment-only settings - every one commented out, since an
    uncommented empty line is a value (LIBRARY_PATH= would take the image's /music away)."""
    lines = (REPO / ".env.example").read_text(encoding="utf-8").splitlines()
    assert all(not line or line.startswith("#") for line in lines)
    named = [m.group(1) for line in lines if (m := re.match(r"^#([A-Z][A-Z0-9_]*)=", line))]
    assert set(named) == {
        "PUID", "PGID", "SLSKD_URL", "SLSKD_APIKEY", "NAVIDROME_URL", "NAVIDROME_USER", "NAVIDROME_PASSWORD",
        *LOGIN_SETTINGS, "TRUSTED_ORIGINS",
    }
    assert "docs/configuration.md#environment-variables" in "\n".join(lines)


# ----------------------------------------------------------------- what the docs tell people to do (after review)

SENTENCES = re.compile(r"(?<=[.!?])\s+")
RESTART_DEADWAX = re.compile(r"\brestart(?:ing)? deadwax\b(?! wouldn't)|reads it at a restart", re.IGNORECASE)


def _doc_texts():
    for path in [*sorted((REPO / "docs").glob("*.md")), REPO / "README.md", REPO / ".env.example"]:
        yield path.name, re.sub(r"\s+", " ", path.read_text(encoding="utf-8"))


def test_an_environment_change_is_never_said_to_need_only_a_restart(monkeypatch):
    """A restart keeps the environment the container was created with, so a changed .env or compose line takes a
    recreate. No sentence in the docs says "restart deadwax" without saying so, and neither does the app: the locked
    logins rows, the missing key, and organizing off with logins on."""
    for name, text in _doc_texts():
        for sentence in SENTENCES.split(text):
            if RESTART_DEADWAX.search(sentence):
                assert "recreat" in sentence, f"{name}: {sentence}"
    from src import auth
    monkeypatch.setattr(Config, "AUTH_MODE", "on")
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", "short")
    said = [config.LOGINS_LOCKED, auth.unusable()]
    monkeypatch.setattr(Config, "DEADWAX_SECRET_KEY", "x" * 64)
    monkeypatch.setattr(Config, "OVERRIDDEN", set())
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "dry_run")
    said.append(Config.describe_logins_organizing())
    monkeypatch.setattr(Config, "ORGANIZE_MODE", "copy")
    monkeypatch.setattr(Config, "LIBRARY_PATH", None)
    said.append(Config.describe_logins_organizing())
    for words in said:
        assert words and "recreate the container" in words and "restart deadwax" not in words, words


def test_the_compose_example_s_env_file_is_said_to_be_optional_everywhere():
    """No page still says compose refuses a missing .env: the example's env_file is required: false."""
    for name, text in _doc_texts():
        assert not re.search(r"refuses (?:a missing one|an `env_file`)|a missing one isn't", text), name


def test_trimming_an_old_compose_file_is_said_in_an_order_that_works():
    """Server settings saves only a value that differs from the one it shows (editedEnvDraft drops a draft equal to
    the committed value), so "save it there first, then take the line out" saves nothing and loses the setting. The
    line comes out first; and with logins on, ORGANIZE_MODE and Navidrome stay, or nothing can be reached."""
    text = re.sub(r"\s+", " ", (REPO / "docs/getting-started.md").read_text(encoding="utf-8"))
    trim = text[text.index("**Already have a longer compose file?**"):text.index("## The first run")]
    assert "first (its row" not in trim
    assert trim.index("take a setting's line out") < trim.index("set the setting again in Server settings")
    assert "With logins on, leave `ORGANIZE_MODE`" in trim and "`NAVIDROME_`" in trim
    view = (REPO / "ui/src/components/SettingsView.tsx").read_text(encoding="utf-8")
    assert "(committed.value ?? '') === value) delete next[key]" in view


def test_the_example_env_says_to_set_organizing_before_logins():
    """Logins on with organizing still dry run makes every route 503, Server settings included - so .env.example's
    AUTH_MODE line says to set Organizing first, not merely that it's needed."""
    text = (REPO / ".env.example").read_text(encoding="utf-8")
    block = text[text.index("# Logins"):text.index("#AUTH_MODE=on")]
    assert "BEFORE you turn it" in block and "Organizing" in block and "Server settings included" in block


def test_the_readme_names_the_locked_settings_as_server_settings_shows_them():
    """Server settings shows DB_PATH and the logins locked (Config.NOT_EDITABLE); PUID/PGID and TRUSTED_ORIGINS
    aren't rows at all, and the README doesn't say they are."""
    text = re.sub(r"\s+", " ", (REPO / "README.md").read_text(encoding="utf-8"))
    para = text[text.index("Most of the container's configuration is"):]
    para = para[:para.index("</p>")] if "</p>" in para else para[:2000]
    for name in Config.NOT_EDITABLE:
        assert f"<code>{name}</code>" in para, name
    assert "aren't shown at all" in para and "can't be changed here and say why" not in para
