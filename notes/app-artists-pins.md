# The app: artists, the id bridge, pins and Home

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### Artists, and the two libraries joined (2.0.0-player.17)

Slice 6 of the one app (`uplan/slices.md` S6, numbered .17: the turntable took .11, .14 and its fix
.16). The boards are `Artist.dc.html`, `Library.dc.html` (the chips and the sort),
`Album.dc.html` ("Also: <edition> ›") and `NowPlayingInfo.dc.html` (About filled in). James's
decisions it carries: Info is about the music, its artist LINKING TO THEIR PAGE; one search box,
whose artist rows and artist top result become links now; the album you have and the album you
don't both show the artist as a link; pins of albums and artists come next ("pin from an album or
artist page"), so the artist hero keeps room for one (built in 2.0.0-player.18 - "Pins, and a
finished Home").

- **Three more calls on the fixed list** (routes/navidrome.py; `test_there_is_no_general_proxy`
  and the turntable test's copy edited on purpose; `test_navidrome_artists.py` (19) through
  `start()`): `GET /navidrome/artists` (getArtists - takes NOTHING from the page, not even its one
  parameter, a music folder; Navidrome's index by initial flattened into one list, in its order),
  `/artists/{artist_id}` (getArtist) and `/songs/{song_id}` (getSong), each by an id of at most
  `ID_MAX` (256) characters passed as Navidrome's `id` parameter, never a path, answers passed back
  as sent. Safe for the reason the rest are: each READS the library the account can see, as every
  Subsonic app does, and none needs admin. Each asks through `client_for(request)`
  (`test_every_navidrome_route_asks_through_client_for` counts eleven routes now).
- **The id bridge: `GET /deadwax/store/album?release_mbid=|navidrome_id=`** (src/routes/
  store_album.py, prefix `/deadwax/store`): one album across its three ids - Navidrome's album id
  (what plays), `store_album.id` (what pins and step 5 key on) and the release MBID (what both
  share). It answers `present` (index_present's live rows, only folders still there - one gone is
  marked `missing`, as Find's checks mark one; tombstones never listed, a merged disc folder's
  `merged` row not listed but its release's own row is), `other_pressings` (index_pressings by the
  group the present rows carry), and `navidrome_id` for the release and for each of the first
  `OTHER_PRESSINGS_LOOKED_UP` (5) other pressings. **Navidrome's id is looked up INTERNALLY, never by
  relaying anything the page sent**: `client_for(request).call("search3")` by the release MBID (a
  Navidrome that matches ids in a search finds it at once), then by the album's title from the store
  row - and an album is believed only when its own `musicBrainzId` IS the release, so a title's
  other pressings are never taken. Found ids are memoised (`NAVIDROME_ID_SECONDS` 600,
  `NAVIDROME_IDS_KEPT` 256; misses are not, since an album just filed is still being scanned), and
  forgotten when the settings tab changes Navidrome (`forget_navidrome_ids`). **Since 2.0.0-player.21
  a kept id is CHECKED with getAlbum before each use** and looked up afresh when Navidrome no longer
  has it as that release (it stands while Navidrome can't be reached). Found in the real page by the
  desktop editor's staged-rip check: an apply writes the tags, Navidrome scans, the page's follow
  finds the album - and the rename a moment later gave it a new id on the stub (which ids albums by
  folder), while the memo handed out the old one for ten minutes and the page never moved. A
  Navidrome on its default PIDs keeps the id across a rename (the release id is in it), so James's
  wouldn't have shown it; the check costs one getAlbum instead of the searches it saves. Given `navidrome_id`,
  the release is getAlbum's `musicBrainzId` (as the turntable's disc art reads it). Navidrome unset,
  down or not having it is `navidrome_id: null` with the store's half answered. Exactly one of the
  two ids (each bounded, the MBID anchored), or a 422 with nothing asked. `tests/test_store_lookup.py`
  (26): tombstones, merged, a folder gone since, other pressings, no release id, Navidrome down and
  unset, the title fallback, a title match of the wrong pressing refused, found kept and misses
  asked again, client_for, nothing the page sent reaching Navidrome, the 422s - and (review) the
  limits stated here: a found id asked again past `NAVIDROME_ID_SECONDS` (the bridge's own clock
  moved), the `NAVIDROME_IDS_KEPT` bound letting go of the least recently used, only five other
  pressings looked up, and a store read that fails answering nothing of the store but Navidrome's id.
- **`OWNED_FIELDS` gains `albumartist_mbids`** (test_owned.py: one artist's id, a collaboration's
  several, none): what finds an artist's MusicBrainz id when Navidrome doesn't send it, and the
  Navidrome artist for one opened from MusicBrainz.
- **`GET /search_musicbrainz/artist?mbid=`**: the LIGHT facts - `get_artist` (the main page's
  artist page's own call, so one cache entry serves both) shaped by `artist_facts`, less its links
  and members (`ARTIST_FACT_FIELDS`). Successes cached like every MusicBrainz answer; a failure (an
  error dict from request_with_retries, or MusicBrainzUnavailable) is a 503, never facts made of an
  error. Three tests in `test_musicbrainz_routes.py` (and five MBID cases).
- **The artist page** (`app/ArtistPage.tsx` at `#/<tab>/artist/<id>`, `PageKind` 'artist'): the id
  is Navidrome's artist, or `mb:<mbid>` for one known only by MusicBrainz (the album you don't have
  links so). `lib/artistPage.ts` (pure, `artist.sim.cjs`) finds each side from the other: Navidrome's
  artist -> MBID by its own `musicBrainzId`, else every /library/owned folder of the albums
  Navidrome has of theirs that says agreeing on ONE single-artist id (a collaboration's ids never
  count); MBID -> Navidrome's artist by `musicBrainzId`, else the name the library files their
  albums under, else MusicBrainz's name for an artist Navidrome has no id for - each only when one
  artist answers (two Nirvanas, neither). A Navidrome artist's page is drawn inside the gate, an
  `mb:` one outside it (its you-have half asked only while Navidrome answers). Hero: Navidrome's
  picture through `/cover` (the `artist.jpg` the main page's artist images save) in a 240px band of
  `--dw-artist-hero`, a scrim only over a picture, the back link at the top with the right kept for
  S7's pin (there since 2.0.0-player.18), the name at the foot, MusicBrainz's facts under it (`factsLine`: "Group · Bristol ·
  since 1991", "1965 to 2014"). **The rows** (`artistRows`): the discography browse
  (`/discography?types=album`, complete - not a search) with what the library holds of each by the
  store's word (owned folders by GROUP id), opened as the Navidrome album holding one of those
  releases - `heldInOrder` (lib/idBridge.ts, shared with Search's held row): the plain edition
  first (none, or the "Standard" the scan names the plain one beside another), then the oldest -
  "N editions" past one, counting RELEASES (a set kept one folder per disc, or one release twice, is
  one); a Navidrome album no folder ties to a group (no release id, or an .m4a deadwax filed, whose
  folder has no group id) claimed only by the ONE group of its exact title, oldest first; every
  Navidrome album still unclaimed is a row of its own - ONE per group the library's folders say it
  is, keyed `group:<id>` as MusicBrainz's row will be - so nothing you have is left off; oldest
  first, the undated last whichever kind, then by folded title, then the key. **Studio only** (on, as the board) browses again with
  `studio_only` - the browse's pages are cached, so it costs MusicBrainz nothing more - and never
  hides an album you have (held albums are rows whatever they are). A renamed artist is one page:
  the browse is by MBID, so Donda (credited Kanye West) and BULLY sit together. A row held only by
  the store's word (Navidrome hasn't found it) asks the bridge (`navidromeAlbumFor`) and opens that
  album, else the album you don't have; a row you don't have opens that page and has the Search
  row's Get chip (`usualGet`, now in `app/pressingLists.ts` and shared with Search). MusicBrainz
  down: the albums you have are the list, one row each, with Try again; no MBID at all: said, and
  only those.
- **Play and Shuffle, by the gesture rule**: `playOrder` - one copy of each row's album, in the
  page's order (never both editions of Dummy) - each prefetched KEPT as it is known (the album
  page's own prefetch, so a press on a row turning into a scroll can't call it off),
  `PREFETCH_AT_ONCE` (4) at a time in the page's order (`inTurns`), and only once /library/owned
  has answered (until then both of Dummy's would be asked for); the buttons disabled until every one
  has ANSWERED and one has songs (`settled`, `playable`); the tap is `rememberQueue(albums)` - every
  album played kept for Info and the turntable, not just the last eight - then
  `actions.playTracks(tracks, shuffle ? null : 0, shuffle)`, nothing awaited. An album Navidrome won't send is left out and said ("Plays 2 of the 3 albums you
  have - Navidrome didn't send the rest"), with Try again - which works because `prefetchAlbum` now
  LETS GO of a failed ask (it used to hand the same failure back for 30 s; search.sim pins it).
  `app/ArtistPage.tsx: playTracks` is on app-rules' allowlist, on purpose.
- **The Library tab** (`player/Library.tsx`, `app/LibraryViews.tsx`, `app/usePaged.ts` - the
  album paging moved there verbatim, `rearm` and all): Albums / Artists / Songs as the board's 32px
  chips (`aria-pressed`) and a sort as its "Recently added ▾" - a line in the accent holding the
  platform's own `<select>`, unseen over it, 17px - with the count beside it once the whole list is
  in. Albums keeps its four orders; Artists (getArtists, asked as the view is chosen) by Name
  (Navidrome's) or Most albums (`sortArtists`), each opening the artist; Songs - search3 with an
  EMPTY query, a page of `SONGS_PAGE` (100) at a time - each OPENING its album (tiles navigate: a
  row that fetched and then played would start the music outside the tap). The Songs chip is left
  out when Navidrome's empty search lists none, asked once, for one song, as the tab is drawn; the
  saved view then falls back to Albums. The view is kept per device (`deadwax-player-library-view`);
  each view is drawn once chosen and kept, hidden, with its scroll. App's per-tab scroll is
  untouched.
- **The album you have**: the artist line is a link (Navidrome's album artist, `artistId`) reaching
  44px; under the meta line a row drawn FROM THE FIRST FRAME - "✓ In your library" and an "Also:
  <edition> ›" chip for each other pressing Navidrome has (`alsoChips`: never the album showing,
  never one with no Navidrome id, at most `ALSO_SHOWN` 3; the label the edition, else "the 1994
  pressing") - on ONE line, so a chip landing moves nothing below and a long edition ellipsizes.
  Asked as the page opens, `/store/album?navidrome_id=`, through its own latestOnly. **The album you
  don't have**: the artist a link when credited to ONE artist with an MBID (`soleCredit`).
- **Search**: the top result and the other artists found (rows, round 48px) open the artist's
  page; a MusicBrainz row found held after it was drawn opens the album you have through the bridge
  (`heldReleases` -> `navidromeAlbumFor`, its own latestOnly, called off with a chip's lookup by
  `standDown`), the album you don't have when Navidrome hasn't found it.
- **Requests' Done rows**: a row whose album is in the library (`filed`, `partly_filed`,
  `already_there`, with a `release_mbid`) carries `release` and OPENS it (the row a button); one
  this download filed (`plays`) has the board's round ▶ (named "Play <album>"). The ▶ plays only with
  the album's songs in hand: the first `DONE_PREFETCHED` (5) such rows are looked up and prefetched
  KEPT while the tab's root is what shows (`requestsActive`: App's watching, no Sources sheet over
  it - never as the app starts), and otherwise the ▶ opens the album. A tap that finds the album
  asks for its songs too. A row it can't open says why: "Navidrome hasn't found it yet - it may
  still be scanning", no folder tagged with its release (`NOT_IN_STORE`: an untagged copy an
  already-there download matched - no scan helps), Navidrome not set up or not answering (App's
  `navidromeProblem`), or deadwax not answering; the note goes once a later look finds the album.
  `app/Requests.tsx: playTracks` is on the allowlist; requests.sim fakes its context and the bridge.
- **Info > About filled in** (`app/useInfoDetails.ts`, App's, asked only while Info is open, one
  latestOnly per song): getSong ("played 12 times" on the first line - Navidrome's count NOW, the
  tap-time album's until it answers - and "Written by", `displayComposer` else the composers among
  `contributors`), the bridge by Navidrome album id ("This pressing: <edition> · <year> · FLAC" and
  the folder, monospace, a folder per line), the album's labels from OpenSubsonic `recordLabels` in
  its line, and the artist the card goes to - with getArtist's album count and MusicBrainz's facts.
  Every one by the rule: not sent, not drawn (each a key only when there is something to say, so the
  shape without details is what it was). The artist card is a link (`toArtist`, every sheet
  closing, as Go to album).
- **Style** (tokens only): theme.css section 10 gains `--dw-artist-hero`, `--dw-artist-scrim`,
  `--dw-play-face`; app.css `--app-artist-*`, `--app-hero-link-reach`, `--app-album-chips-gap`,
  `--app-held-badge-*`, `--app-library-*`, `--app-sort-*`, `--app-done-play-*`,
  `--app-z-hero-words`, `--app-artist-plays-line`, `--app-hero-artist-line`. `test_app_css.py` (54,
  nine new) holds the hero, the scrim only over a picture, the rows and back link as tap targets, the
  link's reach, the one-line chip row, the library chips' reach and wrap, the sort's unseen 17px
  picker, the Done row's 44px play target and the folder's lines - and the review's fixes below.
- **After review** (33 findings confirmed, every one fixed; the duplicates merged):
  - **Nothing moves under a finger as an answer lands.** The artist page's albums wait for
    Navidrome's albums, MusicBrainz's and /library/owned - or `ROWS_WAIT_MS` (1.5 s, as Search
    waits) - and are then drawn; held albums MusicBrainz hasn't claimed are keyed as its rows will
    be, so its answer moves no key (rows used to change key, split Dummy in two, and the third row
    turn from the vinyl into Third under a finger); once drawn they stay drawn, Navidrome asked again
    or not. A Studio only re-browse keeps the last answer on screen, busy, until the new one lands. Play and Shuffle, and the line under them, are drawn from
    the first frame wherever albums could be had - an `mb:` artist too, while Navidrome answers
    ("Looking for their albums in your library…", "Navidrome has none of their albums to play") -
    and the "Albums" heading is as tall as the Studio only chip that comes later. Info holds the
    song's and the store's answers back for each other, or `INFO_SETTLE_MS` (0.5 s, about its slide
    up), and draws the folder LAST, in a row of its own ("In your library" › Folder) outside every
    link, where it can be selected and isn't read out with the album card. Search's held row opens
    the album page with its credited artist, and `.pl-hero-artist` holds its line from the first
    frame (`--app-hero-artist-line`).
  - **Play plays one copy of each album, and Info knows each.** Play waits for /library/owned (it
    says which of Navidrome's albums are copies of one; before it, Dummy queued twice) and the
    albums are asked for a few at a time; `lib/playedAlbums.ts` keeps every album of an artist's
    queue (`rememberQueue`, up to `QUEUE_ALBUMS_KEPT` 64, the first to play kept longest) until the
    next queue starts - with eight kept, the albums that play FIRST were let go, and Info and the
    turntable's disc art lost the song playing.
  - **No verdict without the library's word.** Until /library/owned answers, a row only Navidrome
    claims is "in your library" and every other row says neither and has no Get chip (`held` null);
    "MusicBrainz doesn't know who this is" waits for it too. "N editions" counts releases.
  - **A late answer opens nothing elsewhere.** A row's bridge lookup on the artist page and a Done
    row's are called off when the page or the tab stops showing (and a ref checked as the answer
    lands, since Preact runs effects after paint), and another row's tap calls one still out off.
  - **The artist opened from MusicBrainz**: looked for in a fresh list of artists when the kept one
    is older than `ARTIST_INDEX_STALE_MS` (15 s - an artist new to the library isn't in a list from
    before; `artistIndexAge`), and a failed look has Try again. The session keeps each page's
    answers (`ARTISTS_KEPT` 20, the discography per Studio only), so Back draws the rows on the first
    frame and App's scroll restore lands where you were.
  - **Done rows look again** (`doneLooks`, pure in lib/requestsView.ts): an album filed while you
    watch isn't looked up before `DONE_SCAN_SETTLE_MS` (10 s - Navidrome's watcher waits about 5 s,
    then scans) after its row first shows (this device's clock, never the server's), a miss is
    looked up again after `DONE_RETRY_MS` (5 s) doubling to a minute, and songs are asked again,
    FRESH (`prefetchAlbum`'s new `fresh`), when a later download of the release may have added to
    them or the tab comes back after `DONE_FRESH_MS` (30 s) - a failure forgetting the album's id.
    The first cut looked once, straight after filing, when Navidrome never had it, and never again.
  - **Info's card is the song's own artist**: `cardArtist` - the album's only when it is the same
    person (same name, same Navidrome artist, or, two of them, the same MusicBrainz id by getArtist:
    a renamed artist's old credit goes to Ye's page). A Portishead track on a compilation showed
    Various Artists' facts, count and page under Portishead's name; and with no song artist known
    and the names differing, nobody's facts are drawn.
  - **Small ones**: a row looking for its album fades (`is-busy`) as a Get chip does; an artist's
    name that isn't a link is drawn plain (`app-hero-plain`; on the album page only once the album
    has said so, never in a flash); the hero's scrim darker from halfway down (`--dw-artist-scrim`:
    the name 3:1 over a white sky on one line or two, the facts 4.5:1 - test_app_css computes it);
    the order chips the Library's chips replaced are gone, rules and tokens; Requests' empty state
    points at Search, not "the main page".
- **Not built, on purpose**: the pin (S7 - the hero's top right is kept for it; built in
  2.0.0-player.18); grouping the
  discography by type (the board draws one "Albums" list; `types=album`, so EPs and singles you
  have appear as your own rows); an artist page for a collaboration (whose page?); the label from
  MusicBrainz (OpenSubsonic's `recordLabels` costs no request); `#/library?view=` in the address
  (the view is a device setting, as the order always was).
- **Verified**: 2111 Python tests (63 new: `test_navidrome_artists.py` 19, `test_store_lookup.py`
  26, `test_musicbrainz_routes.py` 7, nine in `test_app_css.py`, one each in `test_owned.py` and
  `test_navidrome_settings.py`), pyflakes, tsc, and all 35 sims (`artist` 115 new - its pure rules
  and, since the review, the page itself rendered with every answer given by hand; `app-rules` 138,
  `routes` 148, `requests` 188, `info` 117, `group` 69 and `search` 68 extended); 75 mutations
  before the review and 51 after it, one or more per fix, each caught and restored byte for byte -
  one first got past (a late answer checked against a ref as well as called off: the sim ran effects
  at once, so it gained a render whose effects wait, as Preact's do) and one showed a gate twice
  over (Play's wait for the library, kept on the prefetch alone). The engine guard is empty, and `player.sim.cjs`, `useDownloadJobs.ts` and
  `downloads.sim.cjs` are untouched.
  **NOT verified here**: the real page (the orchestrator builds the bundle and checks against the
  extended stub - Portishead with Third moved aside, Ye's Donda and BULLY, the 2014 vinyl's "Also",
  Info's folder); and against a real Navidrome 0.64.2: whether it sends an artist's
  `musicBrainzId`, whether search3 finds an album by its release MBID (the bridge falls back to the
  title), what an empty search3 lists, `displayComposer`, `playCount` and `recordLabels`, and an
  artist's picture.

### Pins, and a finished Home (2.0.0-player.18)

Slice 7 of the one app (`uplan/slices.md` S7, numbered .18: the turntable took .11, .14 and .16). The
boards are `Home.dc.html` (Pinned: two columns of cards, round artists, square albums, Edit; Not played
in a while), `Album.dc.html` and `Artist.dc.html` (where the pin goes) and `NowPlaying.dc.html` (the
••• button's "More: info, go to album, pin"). James (2026-09-29): Home is the PLAYER's, not the
librarian's; Arriving only while something is on its way; "Pinned albums and artists come next, at the
top (pin from an album or artist page)"; then Recently added and "Not played in a while" (liked). He
said Home "looks a bit empty" and accepted that these two are what fill it.

- **Pins are deadwax's own, NEVER Navidrome's stars.** A star is per Navidrome user (James has two other
  Navidrome users), Amperfy shows stars as favourites, and step 5 makes starred albums a person's own
  library. A pin is a place on deadwax's Home. `app-rules.sim.cjs` fails on any star, unstar or
  getStarred in ui/src; `test_pins_are_never_navidromes_stars` holds Navidrome to getAlbum and search3.
- **What a pin keys on** (`src/pins.py`, pure): an album's `store:<store_album.id>` - the store index's
  row, whose id stays put through a re-file (index_move), a release applied and a merge (merged_into
  followed) - not Navidrome's album id (new when the tags change enough; the scratch stub's is the
  folder's) nor the path. An album the index doesn't hold yet (pinned before the first scan) is
  `release:<mbid>`, and becomes `store:<id>` on the first read that finds it indexed. An artist's
  `mb:<mbid>`, or `name:<folded>` for one nobody can say an id for (artists.py's `_fold`: case, accents,
  which dash). `MBID_PATTERN` is written out there, held to search_musicbrainz's by a test, so the store
  imports no route.
- **The table** (store.py SCHEMA, so an old database gains it - tested): `pins(user DEFAULT 'local', kind
  CHECK album|artist, ref, label, sub, navidrome_id, cover, position, created_at, PK(user, kind, ref))`.
  `label`/`sub` are what the card said when made (shown when nothing better can be had), `navidrome_id`
  and `cover` the last Navidrome id it opened and its picture, refreshed as Home reads them. Methods:
  `pins()` (None when unreadable - not "nothing pinned"; with a store there, every route answers that
  None with a 503 "deadwax couldn't read its pins just now", which the page answers by keeping what it
  had - only NO store at all is `{pins: [], can_save: false}`), `write_pins()` (the whole list,
  renumbered, one transaction; False from it is a 503 for a PUT or a toggle - tested), `index_follow()`
  (merged_into followed, at most `MERGE_HOPS` 16 - a loop or a longer chain is None; None from the method
  itself when the index can't be read, which the GET answers with a 503 rather than every album "gone")
  and `adopt_local()`.
- **The routes** (`src/routes/pins.py`, prefix `/deadwax/me/pins`, through `current_user`, every write
  behind the same-origin guard): **GET**, **PUT** and **POST `/toggle`**, each answering the whole list.
  - **Brought up to date on every answer** (`_up_to_date`): a `release:` pin the index now holds becomes
    `store:`; a merge is followed; a live row whose folder has gone is marked `missing` (the bridge's
    `live_rows`, as Find's checks mark one); a pin whose album isn't present (missing, deleted, a merge
    that can't be followed) is pointed at a LIVE copy of its release when there is one - so an album
    deleted and got again opens the new copy; each (kind, ref) once (two pins come to one album - a
    deleted one and its copy - are one, in the first one's place; tested, or the table's key fails the
    write on every read). State: `present` (a live row in
    this LIBRARY_PATH's root, or a `release:` pin not indexed yet), `missing`, `gone`.
  - **Navidrome's id, checked** (`_navidrome_for`), for each present album pin: the bridge's kept id or
    the pin's last-known, asked with getAlbum - its `musicBrainzId` must still be the release; a 404 or
    another release has the bridge FORGET it (`forget_navidrome_id`, new in store_album.py beside
    `known_navidrome_id`/`remember_navidrome_id`/`is_release`/`live_rows`) and look afresh
    (`navidrome_album`: search3 by id, then title), its coverArt read with getAlbum; Navidrome that
    can't be asked leaves the last known standing. **This is what keeps a re-filed album opening from
    its pin**: the bridge's 600 s memo would otherwise hand out the id of an album Navidrome no longer
    has (the stub, whose ids are folders, shows it every time). One getAlbum per album pin per answer,
    side by side; Home holds `PINS_MAX` (50).
  - **Navidrome is asked OUTSIDE the per-user lock** (`_writing`, refcounted and dropped like
    store_index's `release_lock`): the lock covers read, change and write; what Navidrome said is written
    back in a second short locked pass onto the pins as they are by then. So a Navidrome slow to answer
    holds up no toggle.
  - **PUT** takes the WHOLE ordered list (`{pins: [{kind, ref}]}`, at most PINS_MAX, refs checked by
    `valid_ref`, nothing else taken): the list's refs brought up to date as the stored ones are (a
    `release:` pin upgraded since the list was drawn is still the pin it names), the stored pins it
    names in its order, the rest removed - it never adds. **`known`** (optional, the same shape): every
    pin the list was MADE FROM. `rules.ordered(stored, wanted, known)` then removes only pins the page
    knew of and left out: a stored pin it was never told of (pinned on another device since) keeps its
    place, and the page's pins fill the places its known pins held, in its order. The app always sends
    it (the server's word the list was made from); without it, the list is the whole of it.
  - **toggle** says what the thing IS and whether it should end up `pinned` - so it is idempotent. An
    album by `release_mbid`, or `navidrome_id` from which deadwax reads the release (getAlbum, through
    store_album's `album_release`, which RAISES where `navidrome_release` swallows): none at all is a
    422 (nothing would find it again); Navidrome answering it has no such album a 422 that says so; and
    a Navidrome that can't be asked a **503** "couldn't ask Navidrome about this album just now" - never
    "no release id", which is a fact about the album (an unpin needs no release, and is matched by
    Navidrome's id whatever Navidrome says). Its ref the first live row by path, else `release:`. An
    artist by `mbid`, or `navidrome_id` and `name` (a 422 without either). Matching (`same`) and
    lib/pins.ts's `isPinOf` give the same answer for every pin: an album by release where both sides
    have one, else by Navidrome's id; an artist by MusicBrainz id where both have one, by the `name:`
    ref where the page has none (the name folded alike - `foldArtistName` in lib/pins.ts is artists.py's
    `_fold`, and `tests/fixtures/name_folds.json` is what both answer, test_pins.py holding one and
    pins.sim the other), else by Navidrome's id where one side has no MusicBrainz id - so two Navidrome
    artists whose names fold alike ("Björk", "Bjork") are one pin, shown pinned on both pages, which
    the table's key made them on the server all along. A `name:` pin takes the `mb:` ref in its place
    when the id arrives with its Navidrome id. A new pin goes FIRST. A 409 past PINS_MAX, a 503 for a
    database that can't keep them.
- **`adopt_local(user)`** (store.py), step 3's take-over, written and tested now and called by nothing
  yet (users.py names it): local's `user_prefs` and `pins` become the first admin's in one transaction,
  theirs winning (INSERT OR IGNORE - a preference they chose, a pin they have, keeps its place), local's
  other pins after theirs in local's order while under PINS_MAX, local left with nothing; into `local`
  itself it takes nothing; None when the store can't.
- **The app's one store** (`app/usePins.ts`, a module, as useGetSettings is): asked `'fresh'` each time
  Home comes into view (App's `homeShown = watching === 'home'`, handed to Home and keying its memo);
  `usePins(true)` from the album and artist pages (only with nothing in hand or older than
  `PINS_KEPT_MS`, 30 s); App's `usePins(sheetOpen)` for the menu; never at start-up. A change is a
  `PinOp` laid over the server's word (lib/pins.ts `applyPinOp`): a pin (a pending one, `pending:N`,
  FIRST), an unpin (by what it is), a move or removal (by key); each sent in turn (`inTurn`), so the
  newest answer always lands last - what latestOnly() does for a fetch that draws. **A move's or
  removal's PUT is made at SEND time from the server's word as it stands then, and sends that word as
  `known`**: made at send time, it lands on what this page saved before it (pins.sim holds both
  orders); `known` is what keeps a pin another device added since this page last ASKED (a desktop
  left on Home while the phone pins) - the send-time list alone unpinned it unseen, and the first cut
  claimed it didn't (a review found it; `test_a_put_made_from_what_the_page_knew_keeps_a_pin_made_since_
  on_another_device`). `known` (in the hook's answer) is true once the pins answered or failed to. A
  refusal goes back to the server's word and is said WHERE IT WAS MADE: a pin or an unpin in the app's
  one notice (`PinNotice.tsx`, drawn once by App, fixed at the top over everything, `pointer-events:
  none`, a polite region always in the page - clipped, never hidden, while it says nothing - for
  `PIN_NOTICE_MS` 5 s), naming it ("Couldn't pin Dummy: Home holds up to 50 pins - unpin one first");
  one of Edit's as `problem`, "Not saved: …", under Home's list until the next change or a successful
  read. The first cut put every refusal on Home, naming nothing, until the next change - for a pin made
  on an album page or from the menu (which had closed), days later.
- **Home** (`app/Home.tsx`): Arriving, then inside the gate `Shelves` - Pinned, Recently added
  (unchanged; its tiles are now the shared `Tiles`, the board's markup test_app_css reads), Not played
  in a while. **The shelves are drawn (`.app-home-shelves`, `hidden` until then, Recently added asking
  all the while) once the pins have answered, or failed, or `PINNED_WAIT_MS` (1.5 s) has passed WHILE
  Home showed** - counted afresh each time Home comes into view until it has once run out (leaving
  mid-wait clears the timer; home.sim holds it) - Pinned is at the top, and landing after the shelves
  it would push them under a finger; counted out of sight, the wait could be over before the pins were
  asked. Don't "fix" it to time from the first showing: that is exactly the jump it exists to stop.
  Each shelf a memoised element.
- **Pinned** (`app/Pinned.tsx`, props only): the board's cards (64px, padding 7, a 48px picture - an
  artist's round - a 14px name of two lines over a 12px line that ellipsizes). A card that opens is a
  button - an album as a tile (prefetchAlbum on pointerdown, dropPrefetch on pointercancel, openAlbum on
  the click), an artist's page (openArtist: **by MusicBrainz id where the pin has one** - `mb:<id>`, so
  the page finds Navidrome's artist itself; the Navidrome id kept since pinning goes stale when a rename
  re-files their albums, and opened by it, getArtist failed with no way to the id the pin held; a
  `name:` pin by Navidrome's id) - and plays nothing; one that doesn't is words (`pinLine`: "Removed from
  the store", "Not on disk just now", "Not in Navidrome yet" - the last two shortened from "Not in your
  library just now" and "Navidrome hasn't found it yet", which a phone's card cut to "Navidrome
  has…"). **A closed card (and Edit row, `is-closed`) gives those words two lines and its title one**,
  in the sub-line's own colour (`--dw-text-2`; the tertiary was 3.9:1), and **under 374px the cards
  take one column** (`@media (max-width: 373px)`): measured in the bundled Noto Sans, "Removed from"
  is 83px and a card's text column 88.5 at 375, 61 at 320. Nothing pinned says how to pin
  (`NOTHING_PINNED`). Edit/Done is at least `--pl-hit` wide, its word flush right. **Edit** makes ONE
  column of rows: up, down, unpin - each a 32px face (`.app-pin-move-face`) in a 44px box, side by
  side with no gap (32px boxes 4px apart put unpin a few pixels from a thumb aimed at down) -
  aria-disabled at the ends and for a pin not saved yet, and a grip (aria-hidden - the buttons are the
  accessible way; `touch-action: none` on it alone, so the page scrolls under a finger anywhere else).
  **Focus is never dropped to the page**: a move by a button puts it back on that button where the row
  went; an unpin on the next row's unpin (the one before, at the end; Done, with none left); Done with
  nothing left pinned on the heading (`tabIndex -1`) - rows found by `dataset.pin`, never a selector
  built from a key with a colon. **A drag moves rows by transform only** (`dragOffset`: the dragged row
  follows the finger, the rows it passes make way) and the list never reorders under the pointer:
  moving the dragged row's element in the page would take the grip's pointer capture away (an element
  removed from the document loses it) and end the drag half way. A polite region says what changed;
  "Not saved: …" is a second one UNDER the list (`.app-pinned-note`, room taken only while `is-said`),
  so its arriving and going move no row.
- **The pin controls** (`app/PinToggle.tsx`, a leaf): the album page's 32px icon button named "Pin to
  Home" whichever way it is (`aria-pressed` says), the artist's chip "Pin"/"Pinned", both reaching 44px,
  aria-disabled - tap refused, focus kept - until what they pin is known **and the pins have answered**
  (usePins' `known`: a toggle live on "not pinned" for an album that is, on a cold link, was the first
  cut), or while deadwax can't keep pins (`PINS_UNSAVED` as the title, and a tap calls `onRefused`,
  which says it in the notice - a title never shows on a phone). **Album page**: pinned by the bridge's
  release (matched by Navidrome's id while that is coming); drawn from the first frame in the bar's
  right (`.app-album-bar` flexes the sticky bar), live once the bridge answered WITH a release, and gone
  once it answered without one or failed. **Artist page**: `{mbid, navidrome_id: libraryId, name, cover:
  picture}`, live once their id is known - or Navidrome and the library have both answered and nobody
  can say one; the hero's top row has a gap and `.app-artist-back` `min-width: 0` (its label is the
  page below's - an album's long title pushed the chip out of the hero, whose overflow clipped it).
  **The ••• menu**: "Pin album to Home" / "Unpin album from Home" after Go to album. What can be pinned
  NOW is `menuPinNow` (from the answer the song was played from: `musicBrainzId` "" means none; not
  sent: the server reads it; nothing while deadwax can't keep pins); **the menu takes it as it OPENS**
  (`menuPin`, set in openMenu), so a pins answer or the next song landing while it is up neither adds,
  removes nor re-aims a row - a row deadwax can no longer keep pins for stays, aria-disabled. It is
  aria-disabled until it is known whether the album is pinned (so no row moves as that lands); its tap
  closes the menu (focus back on •••), saves, and says the outcome in the notice either way
  (`setPinned(target, on, true)` - "Pinned Dummy to Home"). Now Playing's ••• is named "More: info, go
  to album, pin" only when App says the menu will have the pin (`pinnable`), "More: info, go to album"
  otherwise.
- **No playback action from any new file**: the app-rules allowlist is unchanged; app-rules holds the
  pin files (PinNotice.tsx among them) to that, the card to the tile's prefetch-and-open, the store's
  turns and its PUT with `known`, Home's asks and wait, the pages waiting for the pins, and the menu:
  its condition (`playingRelease !== ''`, `pins.canSave`), taken as it opens, close-then-save-and-say,
  `pinnable`, and PinNotice drawn once, by App.
- **Not played in a while** (`lib/home.ts`, pure): getAlbumList2 `recent` at `RECENT_LISTED` (500, the
  route's most), each album's OpenSubsonic `played` (now on player/api.ts's Album) MORE than
  `NOT_PLAYED_DAYS` (30) old, the longest ago first (ties by id, an album listed twice once), up to
  `NOT_PLAYED_SHOWN` (20); none at all with fewer than `NOT_PLAYED_FEWEST` (4) - which is also what a
  Navidrome sending no `played` comes to, every album being left out. No section, heading included,
  with nothing to show or after a failure (Recently added beside it says Navidrome failed for both);
  last, so landing late moves nothing. Plays past `recent`'s first 500 aren't looked at (the guide says
  so). Whether 0.64.2 sends `played` on an album list is unverified (it is omitempty, set once played).
- **Style** (tokens only): app.css `--app-pins-*`, `--app-pin-*`, `--app-z-pin-drag`, `--app-z-notice`
  (40, over the menu and Info's 30), over theme.css's toggled, danger, best and shadow tokens.
  `test_app_css.py` (61, seven new) holds the pin's box and reach, the artist hero's back link giving
  way, the two columns of cards and one under 374px, a closed card's two lines, Edit's 44px boxes and
  width, the note under the list, the grip as the one part taking a drag, and the notice.
- **Not built, on purpose**: pinning an album you don't have (decisions.md: it can't be pinned; the
  group page has no pin); a play button on a pinned card (tiles navigate - the gesture rule); keeping an
  artist pin's Navidrome id fresh (an `mb:` pin opens by its MusicBrainz id, so a stale one can't open a
  broken page - it once did, by the stored Navidrome id; a `name:` pin, which has nothing else, opens by
  it, and is pinned again from the artist's page if that id goes); the desktop's layout (S8, built on
  this); pins on the main page.
- **After review** (25 findings, merged to 17 fixes, each with a check that fails without it): the
  ••• label promising a pin the menu lacked; the artist chip pushed out of the hero by a long back
  label; a closed card's words cut on every phone width ("Navidrome has…") in 3.9:1 grey; Edit's PUT
  unpinning another device's pin (`known`); an `mb:` artist pin opening by a stale Navidrome id; a
  refused pin said only on Home, naming nothing, for ever (the notice, `problem` scoped to Edit and
  cleared by a read); the page pins live on "not pinned" before the pins answered; focus dropped to the
  page by an unpin and by Done; a pins read that failed answered as "nothing pinned, can't save" (a
  503 now); Edit's buttons 32px wide, unpin 4px from down; "Not saved" moving every row; Edit/Done a
  27px target; the menu's outcome unsaid and a greyed pin's reason only in a title; the menu's row
  coming or going while it was open; `name:` matching differing between server and app; two
  documented server rules untested (a refused write's 503, two pins come to one); the menu's
  no-release rule unpinned by any sim; pinning by Navidrome's id with Navidrome down called "no
  release id" (a 503 now); and the wait's wording ("since Home first showed" - it is while Home shows).
- **Verified**: 2180 Python tests (69 new: `test_pins.py` 62, seven in `test_app_css.py`), pyflakes,
  tsc, and all 37 sims (`home` 32 and `pins` 106 new; `app-rules` 158, `artist` 127 and `info` 123
  extended - home.sim and pins.sim fail if they stop before their end, which a check left waiting on an
  unanswered promise would otherwise do with exit 0); 57 mutations, one per rule pinned, each caught
  and restored byte for byte - three first got past (a merge chain longer than MERGE_HOPS, a removal's
  PUT made from the screen, a page's ask with a recent answer in hand - the last because the check
  awaited an answer that never came and the script quietly stopped) and gained the checks that catch
  them - and 30 more for the review's fixes (nine on the server, 21 in the app and the stylesheet),
  every one caught. The engine guard is empty, and `useDownloadJobs.ts`, `downloads.sim.cjs` and
  `player.sim.cjs` are untouched.
  **NOT verified here**: the real page (the orchestrator builds the bundle and checks against the
  stub's seeded plays - The Slow Rush 41 days, Dummy 64, Third 95, Wish You Were Here 210, Donda 3, so
  Not played shows exactly four, and `PLAYED_OFF=1` hides it - pins from an album page, the artist page
  and the ••• menu, Edit with buttons and a real drag, Dummy re-filed through the old editor still
  opening from its pin, a deleted album reading "Removed from the store" whole in two lines, the
  notice at the top over Now Playing, one column of cards at 320, an artist opened from a long-titled
  album keeping its chip in the hero), and everything on the iPhone: the drag under a real finger with
  the page still, VoiceOver's focus after an unpin, and whether 0.64.2 sends `played`.
