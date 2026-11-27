# Song credits: who played what

The design is `~/Desktop/Code/deadwax-plans/credits.md` (App Design session, 27 Nov 2026): the four cases, what is
shown, where, the server. James asked: "Also it would be great to be able to see who is playing what instruments in
each song", and said "Send it" to the design. His two open questions were built to the recommendation: the iPhone
and Mac apps first, no web; production credits as drawn. This file is what was built, slice by slice.

## C1 - the server: the lookup, the kept answers, the route

### The lookup: `get_release_credits(release_mbid)`

- **Its own `inc`**, `CREDITS_INC` in src/api/musicbrainz_endpoint.py:
  `recordings+artist-credits+artist-rels+recording-level-rels+work-rels+work-level-rels`. **Never added to
  RELEASE_FULL_INC**, which is fetched for every pressing looked at and would grow several times over for nothing.
  `test_the_credits_have_their_own_lookup_and_release_full_inc_is_untouched` holds RELEASE_FULL_INC to its exact
  value and to no `-rels`.
- **Through request_with_retries** like every lookup: the pace, the user agent, ResponseCache's hour, the disk's
  month (a lookup's freshness: 30 days; an old answer answered at once and refreshed behind it), successes only.
- **Kept PARSED** (`_kept_parsed`): the one lookup the client parses before it keeps, in `_ask`, so memory, the disk
  and a refresh behind an old answer all hold `credits.kept()`'s shape, never MusicBrainz's. Back in Black's answer
  is 93.5 KB as sent (9.3 KB compressed on disk) and 18.7 KB kept (1.2 KB compressed). A box set's would be far more.
  The saved-search index reads nothing of it (`release/<id>` isn't an endpoint it reads).
- **The kept shape** (`credits.kept`), `{shape, fetched_at, id, artists, credits, media}`:
  - `media`: per disc `{position, track_count, tracks}`, per track `{position, recording, first_released, credits,
    written}`. Positions are MusicBrainz's `position` (what deadwax writes as the track number), not its printed
    `number` ("A1").
  - `credits`, on a track and on the release: `{type, attributes, id, name, begin, end}`, for the types drawn only
    (performers and production). Photography, design, art direction and liner notes are dropped, and so is
    `target-credit`: the artist's own name is the one kept.
  - `written`: the writer, composer, lyricist and librettist relations of each work the recording is a `performance`
    of.
  - `artists`: the release's artist credit, `{id, name, type}`, for case 3.
- **CREDITS_SHAPE** (src/credits.py, 1) guards it as LASTFM_SHAPE guards Last.fm's rows. `_current` makes a kept
  answer of another shape (in memory or on disk) a miss, so MusicBrainz is asked afresh and the new answer replaces
  it. Bump it with any change to what kept() keeps. With MusicBrainz down, an old-shape answer is "unavailable".

### What is shown (src/credits.py, pure)

- **Performers** (`performers`), `{id, name, did: [..]}` a person, one row each. A person's credits are joined in
  one list, lead vocals first, then the rest in MusicBrainz's order, each word once. The design's example, "guitar,
  background vocals", is MusicBrainz's own order, which lists instrument credits before vocal ones. The rows are
  ordered by each person's foremost credit: lead vocals, other vocals, instruments, then an orchestra, choir or
  conductor (`performing orchestra` is "orchestra", plus `conductor`, `chorus master` and `concertmaster`).
  MusicBrainz's order breaks ties.
  - A trailing bracketed qualifier is dropped ("drums (drum set)" is "drums"). guest, solo and additional stay as
    words ("piano (guest)"). A vocal with no attribute is "vocals" ("other vocals" too), an instrument with none
    "instruments", and a bare `performer` credit "performer".
  - The name is always the artist's, never `target-credit`.
  - Not used: `attribute-credits` (the sample's "lead guitar" and "rhythm guitar" for Angus and Malcolm). The
    design names the attribute ("guitar"). Whether to show the credited form is open for C2 and James.
- **Written by** (`writing`): writers alone make one line, "Written by". When a work names a composer or a
  lyricist, there are two lines, "Music by" (writers and composers) and "Words by" (writers, lyricists and
  librettists). Each person appears once a line. Several works (a medley) are pooled.
- **Production** (`production`), `{job, people: [{id, name}]}`: the song's own jobs first. Then the release's, for
  every KIND of job the song doesn't list. So the release's remastering is added, and its "additional" engineers
  aren't, because the song names its engineers. The rows are ordered producer, engineers (engineer, recording,
  audio, sound), programming, editing, mix, remix, mastering, a job with no attribute before its assistants. A job's
  attributes come before its noun: "Assistant engineer", "Executive producer", "Co-producer", "Remastering" (the
  sample's George Marino is `mastering` with `re`).
- **Recorded** (`recorded`): from the performer credits' dates only, as `{begin, end, words}`, for example
  `{"1980-04", "1980-05", "April to May 1980"}`, or null. The words are English month names: "December 1979 to
  January 1980", "12 April 1980".

### The levels, in order (`answer`)

1. **song**: the song is placed and its recording has performer credits.
2. **album**: the release itself has performer credits.
3. **band**: no performer credit is anywhere on the release (`band_of`: no track's, not the release's), the
   release's one credited artist is a Group, and at least one member surely covers the album's date. It is never
   "song", which the app words "on this song". Its `source_url` is the artist's page. Members come from `line_up`
   (below).
4. **song** again: the placed song has no performers, but has its own writers or production.
5. **album** again: there's no performer anywhere, but the release has production credits of its own. For example,
   an unplaced song on Back in Black gives its "Additional engineer" and "Remastering".
6. **none**: nothing at all.

The route adds two levels: **unmatched** (the album has no release id, or MusicBrainz has nothing at it: a 404) and
**unavailable** (MusicBrainz or Navidrome couldn't be asked and nothing was kept, the deadline passed, the band's
lookup failed where it would have decided, or a fault in deadwax). Both are `empty()` answers: the same keys, empty
lists.

`written` and `production` are returned at every level where they are known. A level names what the performers are.

**For C2:** "none" can come from a release whose OTHER songs have credits while this one has none. The design's 4a
words ("MusicBrainz has no credits for this album yet") would be slightly wrong there. The answer doesn't say which
case it is.

### Case 3: the band that year (`line_up`, `covers`, `album_when`)

- The members are the artist's `member of band` relations, **backward** (the other artist is a member of this one),
  from get_artist (ARTIST_INC, which already has `artist-rels`: the artist page's own lookup, so it often costs
  nothing). It is asked only when `band_of` says a band could stand in.
- **"Surely covers"**: the membership began no later than the album's earliest possible day, and hadn't ended (or
  ended no earlier than the album's latest possible day). An unknown start, or `ended` with no end date, is not
  sure. A line-up short a name beats one with someone who wasn't there. Back in Black shows why: Brian Johnson
  joined in April 1980, Bon Scott died that February, and the album came out on 25 July 1980. With the year alone,
  neither is sure. With the date, Brian is in and Bon is out.
- **The album's date** (`album_when`): Navidrome's full `originalReleaseDate` of that year when it has a month.
  Otherwise the earliest `first-release-date` among the release's recordings in that year (1980-07-25 for Back in
  Black). Otherwise the year alone. deadwax writes `originaldate` as the year only, so the recordings' dates are
  what usually make it exact.
- **The year** (`album_year`): Navidrome's `originalReleaseDate.year` (the originaldate tag: `original_year`), else
  the earliest recording's first release, else Navidrome's `year` (the date tag, the pressing's). An MP4 can't hold
  originaldate, so its albums take the second.
- What each played: the membership's attributes, with "original" and "founder" dropped, a bracket dropped, and
  guest, solo and additional kept as words. Lead vocals come first, then other vocals, then the rest, by when they
  joined. A member with nothing known of what they played has `did: []`.

### Finding the song on its release (the route, then `navidrome_place` and `place`)

**Navidrome alone, as the asker**, not the store index or the library scan. The route's id is Navidrome's, so its
access check is Navidrome's too: getSong as the asker, where a song they may not have is a 404. Navidrome also has
everything needed, with no disk read, logins on or off:

- **getSong**: `musicBrainzId` is the RECORDING's id (the file's musicbrainz_trackid, Picard's recording id), read in
  Navidrome v0.64.2's responses.go as notes/app.md records. deadwax writes no recording id, so every song it filed
  sends "". `discNumber` and `track` are omitempty: absent when unset.
- **getAlbum** of its `albumId`: `musicBrainzId` is the release id, from the folder's MUSICBRAINZ_ALBUMID, as
  stars.py and the id bridge read it. Its `song` list counts the songs on the song's disc. `originalReleaseDate` gives
  the year.

No new Navidrome call: getSong and getAlbum are already on the player's list. They're asked through `client_for`
internally, never relayed, so `test_there_is_no_general_proxy` is unaffected. Only an MBID-shaped release id is ever
put in a lookup's address (`release_of`).

**A wrong pairing is worse than none** (`place`):

- When the file has a recording id, only that matches. An id the release doesn't carry is no pairing, never a fall
  back to the position. A MusicBrainz merge that changed the recording's id lands here: the album's answer, until
  the files are retagged.
- Otherwise, disc and track, only when the release's track count on that disc equals the album's song count there
  in Navidrome. A missing disc number is read as the one disc of a one-disc release, never a guess between two, and
  is counted with the album's other disc-less songs. A medium whose `track-count` is more than its listed tracks
  (MusicBrainz cutting a huge release short) is never paired by position.
- Navidrome's album stands in for the folder. Two folders tagged with one release id are one Navidrome album with
  every song doubled, so the count refuses them, which is the right answer.

### The route: `GET /deadwax/credits/song/{song_id}` (src/routes/credits.py)

- **A user's route** (tests/test_logins.py ROUTES), included with `signed_in`, with no permission of its own. Its
  Navidrome calls are made as the asker (`client_for`). The MusicBrainz answers are shared by everyone, since
  MusicBrainz's data isn't anybody's own.
- **The answer**:
  `{level, year, performers: [{id, name, did: [str]}], written: [{job, people: [{id, name}]}], production: [{job,
  people: [{id, name}]}], recorded: {begin, end, words} | null, source_url}`.
  - `level` is one of `song`, `album`, `band`, `none`, `unmatched`, `unavailable`.
  - `source_url` is the release's MusicBrainz page (the artist's for "band"), or null for unmatched and
    unavailable.
  - Every string passes `lastfm.answerable` (a lone surrogate becomes U+FFFD, never a 500).
- **The deadline**, CREDITS_DEADLINE_S, 8 s. The lookups run in a held task (`_held`, stopped by `stop()` at shutdown,
  before the MusicBrainz connection closes). Past the deadline the answer is "unavailable" and the task goes on, so
  what comes is kept and the next ask has it. Without a deadline a person would wait out request_with_retries' ten
  attempts.
- **Never a 500.** MusicBrainz away, Navidrome away (anything but its "not found") and a fault in deadwax are all
  "unavailable", logged at info as "credits: …" in deadwax's own log, never the event log. Only two answers aren't a
  200: a song the asker may not have (404, Navidrome's own "not found") and a session Navidrome ended (401).

### The tests (tests/test_song_credits.py, 32)

Named test_SONG_credits because tests/test_credits.py was already the artist-credit tests (names.md).

- **The real sample** (case 1, `tests/fixtures/credits/back-in-black-2003-us.json`, unchanged from the plans
  folder): every one of its ten tracks placed and shown.
- **Made fixtures** for cases 2, 3 (a release and its band) and 4a, each marked `_made` and described in the
  fixtures' README.md. 4b is Navidrome's album with no release id, made in the test.
- **Not fetched.** The coordinator relayed James's yes to fetching three real answers, but this session's permission
  check refused the request to musicbrainz.org, so the made ones stand. A real answer replaces its file whole (the
  README says how).
- **Mutations, each applied and reverted**:
  - case 3 answered as "song": `test_with_no_credits_the_band_s_members_that_year_stand_in_and_never_on_the_song`,
    `test_the_made_cases_through_the_route`;
  - a mismatched count paired anyway: `test_by_disc_and_track_only_when_the_disc_s_track_counts_agree`,
    `test_a_folder_whose_disc_count_differs_is_never_paired_by_position`;
  - `target-credit` for the name: four tests, the real sample's "Benji Armbrister" among them;
  - RELEASE_FULL_INC given the relations: `test_the_credits_have_their_own_lookup_and_release_full_inc_is_untouched`,
    `test_the_lookup_asks_its_own_inc_and_is_kept_parsed`.

### Not verified

- Cases 2, 3 and 4 against real MusicBrainz answers: the fixtures are made from the documented shape.
- MusicBrainz's member-of-band attribute names beyond the instruments and vocals (taken here: "original",
  "founder", "additional").
- Navidrome's `originalReleaseDate` on a real 0.64.2 answer (from OpenSubsonic's AlbumID3, as read). The song's
  `musicBrainzId` being the recording's is from notes/app.md's reading of 0.64.2's source, not from a real answer.
- A box set's size and time.
- Whether 8 s is the right wait on a real phone.
