# The main page's settings tab

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### The settings tab

- **More settings in v0.9.16**, all on the Downloads tab: where the candidates panel's Quality
  floors (bitrate, bit depth) and its sort START (`candidateMinBitrate`, `candidateMinBitDepth`,
  `candidateSort` - browser preferences, validated against exactly the values the dropdowns
  offer), and `SLSKD_SEARCH_TIMEOUT` (server, 3-60s, default 8 as it always was; a new
  "Soulseek searches" group, `max_wait` = timeout + 17).
- **Auto-grab had been wired to NOTHING - found while laying out the tabs.** "Auto-grab best
  match" was a checkbox, stored and read (`getSettings().autoGrab` in main.js), and no code ever
  acted on it; the reader then went with the vanilla candidates panel in v0.9.10. CLAUDE.md's
  own rule is that every preference is genuinely wired to behaviour. It is now (`autoGrabPick`
  in lib/candidates.ts): on a fresh FIND only, never a Re-search; the top of the list through the
  default filters and sort; only at `AUTO_GRAB_MIN_SCORE` (75, the "good" band) or better, since
  a weak best match is exactly when you want to choose; and the panel says it did it. The pick
  goes through the same download path, runners-up and all. **Verified in the real page**: with
  auto-grab on and a 24-bit default, a Find queued the 24/96 peer by itself - pending row in the
  downloads panel, "Queued ✓", the note - with the Quality badge at 1 and the sort on quality.
- **Tabs since v0.9.15** (asked for: "some tabs for settings organization instead of a long
  list"): Search, Downloads, Library, Connections, Interface, in a strip outside the scroller
  so it never scrolls away. Server groups are placed by `tabForGroup()` - `connections`,
  `downloads`, and everything else (paths, organizing, cover art, lyrics, and any group added
  later, so nothing is ever unreachable) under Library. `tabMarks()` puts an amber mark on a tab
  with a setting whose status is `error` (Library also when organizing is blocked) and an
  accent dot on one holding an unsaved edit - drafts span tabs and the save bar still saves all
  of them, so an edit must not hide behind a tab you've left. The last tab is remembered in
  `deadwax-settings-tab` (the literal id, validated on read). The server's AUTO_RETRY_PEER group
  is labelled "When a download fails", beside the client's own "Downloads" section on that tab.
  **Verified in the real page**: each tab showed its sections, an edit on Search marked Search
  while Library was open, the choice survived in storage, and at 375px the strip wrapped to two
  rows with no overflow.

- **The server half is EDITABLE as of v0.5.1**, via exactly the persistence story the
  previous version of this note said it would need: a `settings` table in the sqlite DB, with
  the environment as the fallback. It is NOT written to `.env` — editing that from inside the
  container would not affect the running process and would be discarded on the next
  `docker compose up`.
- **A stored override WINS over the environment, and that is the only honest precedence.**
  The alternative — environment wins — means an edit made in the tab silently reverts on the
  next restart for anyone configuring through compose, which is most people and everyone whose
  stacks are managed for them. So the override wins, the row says it is overriding, and it offers to revert.
- **Reverting DELETES the row rather than writing the environment's value back.** Copying the
  value back would pin whatever compose said that day, so a later compose change would
  silently stop taking effect. Absence is the only representation of "follow the environment"
  that stays true.
- **`Config.ENV_VALUES` is captured ONCE and must stay that way.** `apply_overrides()` mutates
  the class attributes, so re-capturing on a later call reads back values a previous call
  already overwrote — and the real environment value is gone for good. That bug shipped
  briefly and made "revert" delete the row and then change nothing, because there was nothing
  left to restore. Both directions are now tested.
- **What cannot be edited, and why, is rendered rather than hidden.** `DB_PATH` is the
  database the overrides live in; `PUID`/`PGID` are consumed by `docker-entrypoint.sh` before
  Python starts. A disabled control with no explanation reads as a bug.
- **Validation splits DEFINITIONALLY wrong from ENVIRONMENTALLY wrong.** An `ORGANIZE_MODE` of
  "sideways" is refused because it can never work. A path that doesn't resolve is STORED and
  reported, because it may be a volume you are about to mount — and refusing it would mean the
  only way to fix a broken setup is to edit compose, which is what this tab exists to avoid.
- **So the endpoint's job is DIAGNOSIS.** It answers the three questions someone actually
  has: what value did the container receive, which file do I edit to change it, and what is
  wrong with it. The middle one is the one that is genuinely hard from outside — once
  `load_dotenv()` has run, a compose value and a .env value are indistinguishable in
  `os.environ`. `config.py` captures that at import time and `setting_source()` reports it.
- **Paths are RESOLVED, not echoed.** `_describe_path()` stats every configured path and
  checks readability, and writability where it matters. A path that exists on the host but
  not inside the container is the most common first-run failure in this project and it is
  completely invisible from the string — which looks correct, because it is correct, just
  not from in here.
- **The API key never reaches the browser.** The row reports `set` or nothing. `THEAUDIODB_KEY`
  (v0.6.15) is declared `secret` for the same reason and is masked the same way. This payload
  renders on a page people screenshot into bug reports. A test asserts the key's value does
  not appear anywhere in the payload.
- **slskd's address takes the key again, and holds no login (1.0.5)** - the rule 1.0.3 made for
  Navidrome, asked for. Anyone who can reach deadwax can PUT a new `SLSKD_URL` (a write with no
  Origin passes SameOriginWrites by design), and the next ping or search would have carried the
  saved `SLSKD_APIKEY` - full control of slskd - to it.
  - `SECRET_FOR_ADDRESS` (settings.py) pairs each address with its secret and the sentence a
    refusal gives; `_moved_without_secret()` refuses a batch that changes either address from its
    current value (stripped) without a non-empty secret beside it. The exceptions are
    Navidrome's: the same value, reverting (the environment's address is the admin's), and no
    secret set yet. Clearing is too, though an empty `SLSKD_URL` is refused anyway, as required.
    Reverting or blanking the secret is not typing it. An address that fails validation is told
    that, not this.
  - **One URL check for both**, `_describe_address()` in config.py, each caller passing its own
    words: no login, no `?`/`#`, no space, a numeric port, a host; a PATH is allowed (slskd's URL
    base survives slskd_api's urljoin - measured). That urljoin quietly DROPS a `?` or `#`, so for
    slskd they are refused for reading as something they aren't, not for swallowing a path as
    they do in httpx. **Nothing quotes the value back** - slskd's old "use http://<value>" did.
    `get_client` already ran `describe_slskd_url()`, so an environment value is refused by the
    client with no change there (the pill reads `UNKNOWN_ERROR`, the Log says why).
  - **The cost:** a reverse proxy in front of slskd with a login in the URL no longer works
    (requests sent it as basic auth, beside the key). Point deadwax at slskd directly.
  - **The payload masks a login in an address** (`_setting(address=True)`: `LOGIN_MARK`, `•••@`,
    in `value` and `env_value`, for SLSKD_URL and NAVIDROME_URL). One can only come from compose
    or .env now, and it is still a password. Marked rather than dropped, so the row's "has a user
    name or password in it" has something to point at. `without_login()` moved to config.py and
    reads the authority by hand: urlsplit finds no host in a scheme-less `me:pw@host` and handed
    it back whole.
  - The tab's note beside the secret is `retypeSecretNote()` (SettingsView.tsx), from a table
    mirroring `SECRET_FOR_ADDRESS`; it replaced `navidromePasswordNote`.
  - **Verified in the real page** against two listeners logging `X-API-Key`: a new address with
    no key showed the red note on the key's row, Save gave the refusal in the save bar and the
    collector received nothing; with the key typed, one save stored both ("Set here") and the
    next ping reached the collector carrying only the typed key.
- **Only `error` is decorated.** An unset OPTIONAL setting renders plain. When every row
  carries a colour, the row that needs attention stops standing out, which is the list's
  whole job.
- **The organizing verdict is derived server-side and stated once**, with every blocker
  listed at the same time. "Why did nothing get filed" has four possible causes across two
  groups; discovering them one at a time is how people conclude the feature is broken rather
  than misconfigured.
- **Client preferences are a separate storage key (`deadwax-preferences`), not more fields
  on `deadwax-download-defaults`.** That older blob is read and rewritten wholesale by
  `main.js` too, so any field it did not know about would survive only until the next time it
  saved. New key, one writer.
- **Every preference is genuinely wired to behaviour**, and the vanilla half reads them at
  the point of use rather than caching at load — so a change in the settings tab applies to
  the next action without a reload. `PREFERENCE_FALLBACK` is duplicated in `main.js` because
  the two files are separate ES modules that cannot import each other; **keep the two copies
  in step** until the search view is ported and the duplicate goes away.
- **"Studio only" as a default still shows in the button label.** A filter that is silently
  on is a search that quietly returns less than you asked for, which is the exact failure the
  visible label exists to prevent — see the search-type-filter decision above.
