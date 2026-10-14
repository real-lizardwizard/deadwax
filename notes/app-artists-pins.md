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
  error. Three tests in `test_musicbrainz_routes.py` (and five MBID cases). **In full since
  2.0.0-player.45** - the trim was the build's, not James's ("The artist page, as the main page had it").
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

### The artist page, as the main page had it (2.0.0-player.45)

James (2026-10-14): finish the web app. The parity audit (`uplan/parity-audit.json`, the "manage" area
and the critic's gap list, section 3) found the main page's artist page (`components/ArtistDetails.tsx`
and its two dialogs, `ArtistImagePicker` and `ArtistRefileDialog` - notes/library.md "The artist page",
"One artist under two names", notes/names.md "Artists who have renamed") missing from the app's. James
decided the phone gets all managing, so this is both frames: a side panel on a desktop, a sheet over
the whole screen on a phone. The spec: `uplan/slice-artists-manage.md`.

- **The MusicBrainz half, in full**: `ARTIST_FACT_FIELDS` gains `links` and `members` - the light facts
  were a build trim, not a decision, and they ride in the very answer `get_artist` already asks for
  (its `inc` has url-rels and artist-rels), so the whole set is still ONE request, cached. The TS type
  `ArtistFactsLight` is gone (`ArtistFacts` for both); Info's artist card reads the same answer.
  `test_artist_is_the_full_facts_in_one_request`: the links told apart (`_tell_apart`), the same page
  once however written, the line-up current first and only the members OF the band, every field and
  no other, one request whose `inc` carries the relations.
- **Which names** (`lib/artistManage.ts`, pure, artist.sim). The main page's artist routes all take the
  LIBRARY's name for an artist (the scan's album artist - how its tree groups), while the app's page is
  one per artist: Ye's holds Donda, filed as "Kanye West", and BULLY, filed as "Ye". `libraryNames`
  reads /library/owned's folders: a folder of several artists (a collaboration) never counts, even one
  Navidrome lists under them; a folder of one artist counts when that is the page's MusicBrainz id -
  or, with no id known, when it goes by the page's name (folded as `foldName` folds); a folder carrying
  no artist id counts when Navidrome lists its album under them (by release) or it goes by their name.
  Each name is one `GET /library/artist?name=` (through one latestOnly; a name that fails is null,
  and every name failing is no answer at all - below), kept in the session with the page's other
  answers. It is NAMES the routes take, not folders: a name
  two acts share (the US and UK Nirvanas both tagged "Nirvana") answers for both - one summary, one
  images folder - as the main page, which groups by name too, always has (review: a sim's label said
  "only its own folder").
- **Under the albums, drawn in one go** - "In your library", "About", "Line-up" - once the albums are
  drawn and the library's word (owned, Navidrome, every summary) and MusicBrainz's facts have answered,
  or `ABOUT_WAIT_MS` (3 s, from the page opening) has gone; once drawn they stay drawn. Under the
  albums so nothing above moves as they land (the page's rule from 2.0.0-player.17); In your library
  first (local, fast), the facts-fed parts after it. A fact landing late fills About in place, with
  only the Line-up under it. The library ISN'T always fast (review): the first /library/owned after a
  restart walks the whole library, so when the wait draws the sections with the library's half still
  out, In your library is drawn LAST (`libraryLast`, latched as they are drawn) saying "Looking in your
  library…", filled in where it is - "Nothing of theirs in your library." if it comes back empty - so
  it never lands above an About on screen (on a desktop, never a third column appearing ahead of the
  other two). Once it has said something, that stays while the library is asked again (the names
  changed), as the albums do; once drawn, it stays drawn. The library answering for NONE of their names
  (second review) is said - "deadwax couldn't read your library just now", with Try again, busy while
  it asks and asking once at a time - over what it said before when it had said something ("... - this
  is what it said before."; the hero and Artist images… keep that word too), and with nothing said
  before, Artist images… is still drawn, stepped back with `imagesFolder`'s reason. Such an answer is
  never kept in the session, so the page come back to asks rather than drawing a failure. **In your library** (`libraryFacts`): albums, tracks, size, years and the
  folder (a folder per line, broken anywhere) - added up over every name, and under several names the
  folders and "Their albums are filed under 2 names - Kanye West and Ye"; one name's own
  `folder_problem` otherwise. **About**: the disambiguation, **Now: <name>** when a name the library
  files them under isn't MusicBrainz's for them now (`namesToMove` - the main page's own test: the names
  differ as written), Type, From (where they began, else their area, else country), `lifeRows` - Born
  and Died for a person, Founded and Dissolved for a group (an orchestra, a choir), Began and Ended
  otherwise, dates in words (`factDate`: "8 June 1977"), an end with no date "yes, date not known" -
  and Other names; genres as tags; the links (`LINKS_SHOWN` 8, then "N more links") as rows opening
  beside the app (`target="_blank" rel="noopener"`, the address in the tooltip). MusicBrainz failing:
  About says so, with Try again (it used to leave only the line under the name out). **Line-up**:
  `MEMBERS_SHOWN` 10, current first, roles (three) and years, a past member stepped back
  (`--app-artist-past`), then "N earlier members". Each fold opens downward (`aria-expanded`).
- **The hero**: their `fanart.*` where it is in the images folder (`artistArtUrl`), else Navidrome's
  picture - or, once pictures were saved this visit (or with no Navidrome picture), the `artist.*` on
  disk, asked with the session's `version` past the browser's five-minute cache; their `logo.*` in the
  name's place (`<img alt={name}>` inside the h1), at most `--app-artist-logo` (72px) tall. A picture
  that won't load falls back.
- **Managing, an admin's** (`admin` from App's `/deadwax/me` - asked on a phone too now, as an artist
  page comes on top there; true with logins off): **Artist images…** under In your library,
  **Move albums to <name>** in About's Now row, **Which artist is this?** under "MusicBrainz doesn't
  know who this is" - each `aria-pressed` while the panel shows it, and pressed again on its page,
  closed. Artist images… writes into ONE folder (`imagesFolder`): the current name's where the library
  files them under it, else the only name's; under several names and none current it is aria-disabled
  with the reason under it ("move them under Ye first"), as for a name whose albums share no folder
  (the summary's own words). An artist chosen is the page's for the visit (`kept.chosen`, used only when
  nothing else says who they are): About says "You chose who this is, for this visit." with Change, and
  focus goes to Change as the panel that chose closes. The facts are kept WITH the id they answered for
  (`factsOf`, review): another artist chosen, the last one's are never shown as theirs - About asks,
  then fills or says MusicBrainz didn't answer, with Try again - and Change is drawn whatever the facts
  are doing, so a choice whose facts won't come can still be changed. On their page by the name they
  have now (Navidrome's "Ye", or `mb:<Ye>`), the Now row reads **Also filed as: Kanye West** - "Now: Ye"
  there said nothing.
- **The artist page's panel** (`app/ArtistPanel.tsx`): the main page's two dialogs drawn for the app over
  the same routes (ArtistDetails.tsx has no diff - its dialogs are modal floating windows that take
  Escape on `window`'s capture, which the frame's panel rule can't host), plus "Which artist is this?" on
  its own. **By the frame's rule** (`lib/appFrame.ts`: `Side` gains `'artist'`; `sideOf` Info, then
  Edit, then the artist's, then Sources): a side panel on a desktop (the shared side panel rules,
  470px, a column from 1280 or a drawer, not modal, Escape only from inside it); a sheet over the whole
  screen on a phone (modal: App's `covered` gains it, so the page behind is inert; its own scroll lock,
  `app-artist-panel-open`). One at a time: it puts Sources, Info and Edit away and each of them puts it
  away. It is the page's, on the tab it was opened on (App's request keeps `tab`): it closes as that page
  stops being on top there (`artistShown`) - the same artist on top of another tab is another copy of the
  page, which the panel's answers (a choice, a save) wouldn't reach, and only the opening tab's copy
  shows its button pressed (second review) - and it stays open across 1024px, a panel one side and a sheet the other, as Sources does. Each request is a new body
  (keyed): **RefileBody** previews every name in `moveNames` through the refile route (one latestOnly),
  drawn as one (`refileView`): each move (path → where it goes, "27 tracks, 27 retagged"), each album
  that stays and why, the problems; **Move N albums** (`canMove`) applies each name with something to
  move in turn - the route recomputing its plan every time - and says what became of it with Done
  (focus to Done); **ImagesBody** is the picker: who it shows with **Not them?** (the search, for the
  pictures alone, as on the main page), the notes on keys not set (`imageNotes`: keys go "in deadwax's
  settings, under Connections"), slot by slot with the file on disk or "none found for this", best
  chosen first, a tap to choose and again to leave the slot (`toggleChoice`), **Use another picture
  (N)**, **Replace pictures that are already there**, **Save** (the route honours only a picture the
  artist's own sources just offered); an ambiguous preview opens the search with MusicBrainz's matches;
  **WhoBody** searches the page's name as it opens and lists MusicBrainz's artists for it (`matchLine`:
  "as Kanye West · US rapper · Person · US"). Every preview and search through a latestOnly with its
  signal; **a write is never called off**: a move's and a save's requests carry no signal, and what they
  did is told whether the panel still shows or not - the page follows albums that moved even from a
  panel closed mid-move; only the drawing waits on the ticket.
- **The page follows the artist - from an old name's page only** (App's `artistMoved`, from the page's
  `onMoved`): the library's listeners told (`announceAlbumsFiled` - the owned marks, the folders the
  page reads) and the count asked again ("Artist under two names" was theirs). The page FOLLOWS only
  when it says to: it is a page by MusicBrainz id (already where a move takes it - App changes nothing),
  or its Navidrome artist's name is one of the names every album of which moved (`refileAfter`'s
  `emptied`: nothing refused at the preview or the apply, nothing failed). Then it becomes `mb:<their id>`
  (`router.become` - its entry replaced, the panel's request following it), the move is remembered
  (`artistMoves`) for a page of the old id coming back on top, and its scroll is put back once it has
  drawn: the page it became has nothing kept, so it draws nothing on its first frame and App's own
  scrollTo clamps to 0 - the page tells App as its albums, then its sections, are drawn (`onDrawn`), and
  App scrolls to where it was (`artistDrawn`, only while that route still shows, and only on that page's
  own word: App hands each artist page an `onDrawn` that names its route, so an artist page in a hidden
  tab drawing meanwhile can't use the scroll up - second review). Any OTHER page stays
  (review): Navidrome's "Ye" is still Navidrome's artist after Kanye West's albums join it, and an old
  name an album stayed under still has a Navidrome artist - following from either sent the page to
  `mb:<Ye>`, where two Navidrome artists carry the id until the scan (for good, after a partial move)
  and `libraryArtistFor` finds neither, and redirected the old id there for the session. What the
  session kept of both pages is forgotten (`forgetKeptArtist`). The panel's wait of `EDIT_SETTLE_MS`
  (10 s - by when Navidrome's watcher has usually scanned; nothing watches the scan itself), the panel
  being never unmounted, App holding no timer (app-rules): App bumps the `refresh` of the page they were
  moved from under the id it has now (`artistRefreshes`, through `artistMoves`) - Navidrome's artist found
  afresh (`libraryArtists(true)`) and asked again, and the library's word on their names. What the
  panel gives focus back to is re-pointed to the new page's back link while the old opener is gone.
  A Navidrome slower than ten seconds leaves the page as it was before the scan until it is opened again.
- **Needs a look's "Artist under two names"** says how the app fixes it: its hint (metadata_health.py,
  server-side for both pages) now names the button - "Move albums to … on the artist's page moves them
  all under the name MusicBrainz uses now"; artist.sim holds the hint to the page's button.
- **A fix to the eighth writer, found by the real page**: `plan_artist_refile` counted every `*.flac` by
  name, so a Mac's AppleDouble twin (`._01 - Donda Chant.flac`, the resource fork a Mac leaves beside
  every file it copies to a share; the stub library has them) was planned as a retag, failed ("a tag
  wouldn't write: ... is not a valid FLAC file") and kept the whole album where it was - on the main
  page too. A name starting `._` is passed over now and the twin moves with its folder
  (`test_an_appledouble_twin_is_never_retagged_and_moves_with_its_folder`); any OTHER audio file that
  won't open keeps its album where it is, refused in the plan with its name (notes/library.md "One
  artist under two names" - the first fix passed over every unreadable file, review). The old artist
  folder holding only the twin of the moved album folder stays (rmdir only, never rmtree - the standing
  decision).
- **Style** (tokens only): app.css `--app-artist-logo`, `--app-artist-list-gap`, `--app-artist-genre*`,
  `--app-artist-member-gap`, `--app-artist-past`, `--app-artist-panel-*`, `--app-artist-close-icon`,
  `--app-artist-option*`, `--app-artist-chosen-ring`, `--app-artist-move-gap`, `--app-artist-said`; the
  page's lists are the app's grouped lists (`.app-group`, `.app-row`), its buttons the secondary
  `.app-button`, toggled while its panel shows and stepped back (`--app-pin-off`) while aria-disabled;
  the sheet from the very top, its words clear of the status bar and its foot of the home indicator by
  padding, placed clear of a notch by left and right, its body the one part that scrolls (touch-action
  pan-y), its search 17px. app-desktop.css: the panel joins the side panels' shared rules and close
  button; In your library, About and Line-up side by side (`--app-desk-artist-column` 300px, auto-fit),
  their rows a desktop row's (`--app-desk-row`, a finger's where the pointer is coarse); the panel's
  pills and field at the panel's sizes, a finger's and 17px where the pointer is coarse.
- **No playback action from any new file**: ArtistPanel reaches no action and reads no player (app-rules);
  the allowlist is unchanged; the engine files have no diff.
- **Not built, on purpose**: keeping "Which artist is this?"'s choice past the visit (a store of its
  own; the release editor writes who an album is by into its files, which is how it sticks); a picture
  for a name whose albums sit in several folders (the main page refuses it too); refiling a
  collaboration (its folder is its own); telling apart two acts the files give one album-artist name
  (the US and UK Nirvanas both "Nirvana" share one In your library and one images folder - the library's
  routes take a name, as the main page's tree groups by one); the main page's dialogs reused as they are (above); the
  Sidebar's and You's "Open the main page" still say what is left there (the bulk runs, in this base).
- **After review** (each confirmed by a majority of skeptics; the fixes, beyond the bullets above):
  - **Two names moving folders of one name to one place** (`Kanye/Graduation (2007)` and `Kanye
    West/Graduation (2007)`, both to `Ye/Graduation (2007)`): each name's plan is the route's for it
    alone, so both planned the move and the button said "Move 2 albums" while one silently stayed.
    `refileView` now shows the later staying ("another album moves to 'Ye/Graduation (2007)'"), and the
    loop applies only names with a move left. And whatever an apply's recomputed plan refuses that the
    preview showed moving (a folder come since) is said in the outcome (`refileAfter`'s `stayed`),
    never dropped - the main page's dialog drops it too, one name at a time.
  - **The Move loop's rules pinned**: the page told only when something moved (an apply where every tag
    failed tells it nothing and starts no wait), no apply after one that fails (what the preview said
    is no longer what is on disk), and the failure's words said.
  - **The Move panel's subtitle** is the names whose albums move → the current name ("Kanye West → Ye",
    "Kanye and Kanye West → Ye"); it was the page's own name, "Ye → Ye" on Ye's page.
  - **Artist images…'s Save** can't be pressed while another artist's pictures are being looked for -
    the slots give way to "Looking for pictures of Nirvana…" - nor after that look failed and took the
    slots away: both times what it would have written was the last artist's, rejected or not on screen.
    Try again asks for the artist last picked, not the page's. A search has its own latestOnly (it no
    longer calls off a look out), its button busy while out.
  - **A picture to choose sits in a box of its slot's shape** (`.is-square` for the square, wide for the
    rest, the picture fitted inside): the box followed each picture's shape as it loaded - lazily, full
    size from fanart.tv - so the options after it moved and wrapped under a finger.
  - **Which artist is this?'s body**, the one with no foot, pads its own end clear of the home indicator
    (`.app-artist-panel-body:last-child`, as Info's scroller); on a desktop off the panel's foot.
  - **On a phone on its side** (`max-height: 500px`) the sheet scrolls as one, head, body and foot: the
    fixed head and foot left the pictures about 140px at 844x390, a slot taller than its window.
  - **Docs**: the page asks again "ten seconds later, by when Navidrome has usually scanned the move"
    (it said "once Navidrome has scanned"); the README's hero is the background in the picture's place
    and the logo in the name's (it said "behind their picture"); In your library goes by name, as the
    main page does; a stale "light facts" comment in useInfoDetails.ts.
  - **Pinned where only wiring was**: the re-ask after a move (artist.sim re-renders the page with a new
    `refresh` - Navidrome's albums and every summary asked again, a page by MusicBrainz id finding its
    artist in a fresh list; app-rules pins `artistSettled`'s body and the `refresh` wiring), App's
    follow (its guard, the old id's page redirected, the focus re-point, the scroll put back), the
    sections' wait (artist.sim's timers fire by delay now: nothing under albums still to come, the
    facts waited for until ABOUT_WAIT_MS and not after), and the smaller rules: the years across names
    in any order, the choice kept for the visit (its check was always true), a save or a search
    answered after the panel closed, a failed summary saying "deadwax couldn't read their folder just
    now", a tap on the stepped-back Artist images… refused, the square on disk only once saved here.
  - Left as found: `askQueueSummary()` in `artistMoved` is redundant with `announceAlbumsFiled()`
    (useQueueSummary listens for it) - kept, as albumChanged has both, and not pinned.
- **After the second review** (each confirmed by a majority of skeptics):
  - **In your library when the library couldn't be read** for any of their names (a dropped request
    over WireGuard, a 5xx, a scan snapshot behind /library/owned): the all-null answer counted as an
    answer, so the section either vanished (and Artist images… and its "couldn't read their folder"
    reason with it - the docs said the button greys), said "Nothing of theirs in your library." under
    their albums (drawn last), or - a re-ask after a save or a move failing - took away the section
    already on screen, About jumping up. Now `summaryFailedFor` holds the names whose ask failed
    entirely: `summaries` keeps the last real answer, the section stays drawn once drawn
    (`libraryOnScreen`), the failure is said with Try again over what it said before, and it is never
    written to `kept.summaries` (on the next visit it made About draw at once, In your library then
    landing above it). The main page's ArtistDetails turned a failure into null too but kept the
    section and a disabled Artist images….
  - **The panel and the same artist on two tabs**: `artistShown` and `managing` compared only the page
    id, so the non-modal desktop panel stayed open over another tab's copy (pressed there), and a choice
    or a save updated the hidden copy - the request's callbacks belong to the copy that opened it. The
    request keeps its tab; both compare it.
  - **The scroll put back after a follow** was taken by whichever artist page drew - one in a hidden tab
    could use it up (narrow: a page opened within ~3 s of a slow apply finishing). `artistDrawn` now
    takes the drawing page's route key and acts only for the one `artistMoved` recorded.
  - **Pinned where nothing held it** (each rule mutated, every sim passing): mutagen ANSWERING None for an
    .m4a, .ogg or .opus it can't recognise (the four refile tests all made it raise - notes/library.md);
    `refileAfter`'s "nothing refused at the apply" for `emptied`; the files' word over a choice
    (`said ?? chosen`); the sections waiting for Navidrome too (`libraryKnown`); a picture on disk that
    won't load falling back (the background, the logo); "Fewer members"; a choir Founded; the move's
    problems said once; and the facts' Try again showing "Asking MusicBrainz…" while it asks.
- **Verified**: 2412 Python tests (2410 passed, 2 skipped; six new - the AppleDouble refile test, three in
  `test_app_css.py`, two in `test_app_desktop_css.py` - and the light facts' route test rewritten for the
  full facts), pyflakes, tsc, the bundle,
  and all 47 sims (`artist` 224 - its pure rules in `lib/artistManage.ts`, the page's new sections,
  hero and managing rendered with every answer given by hand, and the panel's three bodies and its
  frame; `app-rules` 317 and `routes` 256 extended). 52 mutations, one or more per rule pinned, each
  restored byte for byte: 49 caught at once; one got past (a collaboration's folder counted - no case
  reached it) and gained the check that catches it; one was equivalent (imagesFolder's two branches
  swapped give the same answer for every input) and was replaced by one that isn't, caught. The engine
  guard is empty; `ui/src/components/` and `ui/src/hooks/` have no diff.
  **After review**: 2420 Python tests (2418 passed, 2 skipped; eight more - four in
  `test_artist_refile.py` for the tracks that won't open, three in `test_app_css.py`, one in
  `test_app_desktop_css.py`), pyflakes, tsc, the bundle, all 47 sims (`artist` 270, `app-rules` 320,
  `routes` 256). 51 mutations of the fixes, each restored byte for byte (sha256 checked): 50 caught at
  once; one got past (a name counted empty with a failure in it - the moved count already said so,
  except when an album was filed under the name between the preview and the apply) and gained the case
  that catches it.
  **After the second review**: 2423 Python tests (2421 passed, 2 skipped; three more - the None branch,
  one per extension), pyflakes, tsc, the bundle, all 47 sims (`artist` 291, `app-rules` 321, `routes`
  256). 26 mutations of the fixes in a scratch copy, each restored byte for byte (sha256
  checked): all 26 caught first time - ten of the failed-library rules, two of the scroll's own word,
  three of the panel's tab, the None branch, the apply's refusal, and nine for the seven rules pinned
  (a picture that won't load three ways: the background's onError dropped, the logo's, an address never
  matched).
- **Verified in the real page** (headless Chromium over plain http as `deadwax.test`, the builder's own
  deadwax on 8110 against its own stand-in Navidrome on 8111 over a copy of the stub library with
  `Kanye West/Donda (2021)` staged - album artist "Kanye West", Ye's MusicBrainz id - MusicBrainz live;
  31 checks, no console errors): at 390x844 Navidrome's "Kanye West" page draws In your library (two
  names, 2 albums, both folders, why there is no one), About (Now: Ye with Move albums to Ye, Person,
  Atlanta, Born 8 June 1977, other names, "formerly Kanye West", genres, eight links opening beside and
  a fold) and no line-up; Move albums to Ye opens the sheet over the whole screen (page inert, focus on
  its close) previewing `Kanye West/Donda (2021) → Ye/Donda (2021) · 27 tracks, 27 retagged`; Move moves
  it (album artist Ye, each track still Kanye West, Ye's id, the AppleDouble twins along), says so with
  Done, the page becomes `mb:<Ye>`, Done gives focus to its back link, and once the stand-in has scanned
  the page plays both albums, one folder, no Now; Artist images… shows the six slots, the note on keys,
  the best chosen, and Save writes `artist.jpg` and `logo.png` into `Ye/` (Commons and Wikidata, no key
  needed), the hero then the saved square and the logo in the name's place; at 375x667 "Which artist is
  this?" on Test Signal lists MusicBrainz's artists, a pick gives the page About and "You chose who this
  is" with focus on Change; at 1440x900 Portishead's page draws the three sections side by side, the
  line-up's past members stepped back, Artist images… opens as a 470px third column (`.has-side`, not
  modal, the page live, the button pressed), Escape in the page leaves it and from inside closes it. No
  overflow at any size, the sheets open or not.
  **After review, in the real page** (the fixer's own deadwax on 8112 against its own stand-in Navidrome
  on 8113, the same staged copy; 18 checks, no console errors): at 390x844 Navidrome's "Ye" reads
  **Also filed as: Kanye West**, the sheet's subtitle "Kanye West → Ye", the move leaves the page on
  `ar-6f59522e3981` with Play live, and once the stand-in has scanned it plays both albums from there;
  Kanye West's page with a copy of Donda whose first track is chmod 000 previews Donda moving and the
  copy staying ("'01 - Donda Chant.flac' can't be read, so its tags can't be written"), moves one, and
  stays on Kanye West's page; at 1440x900 Kanye West's page scrolled to About (4030) follows to
  `mb:<Ye>` and, two frames at 0 later, is put back (4016, the new page 14px shorter); at 390x844 with a
  34px home indicator, Which artist is this?'s eighth match ends at 788 (body padded 54px); at 844x390
  Artist images… scrolls as one (body 715px in a 390px sheet), Save on screen at its end, the square's
  box 72px and the logo's 168px. No overflow at any of them.
  **NOT verified here**: an iPhone (the sheet's safe areas, VoiceOver through the panel), fanart.tv and
  TheAudioDB's pictures (no keys here), a real Navidrome 0.64.2 (whether it keeps an artist's id across
  the move - the page follows by MusicBrainz id either way), the drawer between 1024 and 1279px, a
  coarse pointer, a move of several old names at once against a real library (the sim has it), a phone
  on its side on a real iPhone, and a Navidrome slower than ten seconds to scan a move (the page shows
  what it had until it is opened again). The second review's fixes were not run in a real page: a
  /library/artist that fails (the note, Try again, the stepped-back Artist images…), the panel with
  the same artist on top of two tabs, and the scroll put back with another tab's artist page drawing.
