# Song credits: who played what

The design is `~/Desktop/Code/deadwax-plans/credits.md` (App Design session, 27 Nov 2026): the four cases, what is
shown, where, the server. James asked: "Also it would be great to be able to see who is playing what instruments in
each song", and said "Send it" to the design. His two open questions were built to the recommendation: the iPhone
and Mac apps first, no web; production credits as drawn. This file is what was built, slice by slice.

## C1 - the server: the lookup, the kept answers, the route

Built in two commits: the first, then the review's fixes and App Design's three rulings on it ("After review", at
the end, says what changed). What follows is how it stands after both.

### The lookup: `get_release_credits(release_mbid)`

- **Its own `inc`**, `CREDITS_INC` in src/api/musicbrainz_endpoint.py:
  `recordings+artist-credits+artist-rels+recording-level-rels+work-rels+work-level-rels+release-groups`. **Never
  added to RELEASE_FULL_INC**, which is fetched for every pressing looked at and would grow several times over for
  nothing. `test_the_credits_have_their_own_lookup_and_release_full_inc_is_untouched` holds RELEASE_FULL_INC to its
  exact value and to no `-rels`. `release-groups` is for the album's date (below).
- **Through request_with_retries** like every lookup: the pace, the user agent, ResponseCache's hour, the disk's
  month (a lookup's freshness: 30 days; an old answer answered at once and refreshed behind it), successes only.
- **Kept PARSED** (`_kept_parsed`): the one lookup the client parses before it keeps, in `_ask`, so memory, the disk
  and a refresh behind an old answer all hold `credits.kept()`'s shape, never MusicBrainz's. Back in Black's answer
  is 93 KB as sent (9.3 KB compressed on disk) and 20 KB kept (1.3 KB compressed). A box set's would be far more.
  The saved-search index reads nothing of it (`release/<id>` isn't an endpoint it reads).
- **The kept shape** (`credits.kept`), `{shape, fetched_at, id, first_released, compilation, artists, credits,
  media}`:
  - `first_released`: the release group's `first-release-date` (original_year's), null when it has none.
    `compilation`: whether the release group's `secondary-types` hold "Compilation". Both are always in the release
    group's JSON (musicbrainz-server's JSON ReleaseGroup serializer, read on 27 Nov).
  - `media`: per disc `{position, track_count, tracks}`, per track `{position, recording, credits, written}`.
    Positions are MusicBrainz's `position` (what deadwax writes as the track number), not its printed `number`
    ("A1"). A recording's own first release date is not kept: it was only ever the wrong date for the album.
  - `credits`, on a track and on the release: `{type, attributes, credited, id, name, begin, end}`, for the types
    drawn only (performers and production). `credited` is MusicBrainz's `attribute-credits`, a map from an
    attribute's name to the credited text ("guitar": "lead guitar"), only the ones it gives. Photography, design,
    art direction and liner notes are dropped, and so is `target-credit`: the artist's own name is the one kept.
  - `written`: the writer, composer, lyricist and librettist relations of each work the recording is a `performance`
    of.
  - `artists`: the release's artist credit, `{id, name, type}`, for case 3.
- **CREDITS_SHAPE** (src/credits.py, now 2) guards it as LASTFM_SHAPE guards Last.fm's rows. `_current` makes a kept
  answer of another shape a miss, in memory and on disk (`_saved_answer`), so MusicBrainz is asked afresh and the new
  answer replaces it. Bump it with any change to what kept() keeps. With MusicBrainz down, an old-shape answer is
  "unavailable".

### What is shown (src/credits.py, pure)

- **Performers** (`performers`), `{id, name, did: [..], joined, left}` a person, one row each. `joined` and `left` are
  null except on a band's line-up (case 3). A person's credits are joined in one list, lead vocals first, then the
  rest in MusicBrainz's order, each word once. The design's example, "guitar, background vocals", is MusicBrainz's
  own order, which lists instrument credits before vocal ones. The rows are ordered by each person's foremost credit:
  lead vocals, other vocals, instruments, then an orchestra, choir or conductor (`performing orchestra` is
  "orchestra", plus `conductor`, `chorus master` and `concertmaster`). MusicBrainz's order breaks ties.
  - **The credited form** (App Design's ruling a): an instrument or a voice is said as the release credits it, where
    MusicBrainz gives `attribute-credits` - Back in Black's Angus Young "lead guitar" and Malcolm Young "rhythm
    guitar", both "guitar" to MusicBrainz. Otherwise its name with a trailing bracketed qualifier dropped ("drums
    (drum set)" is "drums"). Its place in the order is its own name's: "lead vocals" credited as "voice" is still
    first. guest, solo and additional stay as words ("piano (guest)", "slide guitar (solo)"). A vocal with no
    attribute is "vocals" ("other vocals" too), an instrument with none "instruments", a bare `performer` credit
    "performer".
  - The name is always the artist's, never `target-credit`.
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
- **Other songs credited** (`others_credited`, App Design's ruling c): true when another song on the release - every
  song but the placed one, or every song when it isn't placed - has performer credits. The release's own credits are
  no song's. It's in every answer (false for unmatched and unavailable) and changes no level.

### The levels, in order (`answer`)

1. **song**: the song is placed and its recording has performer credits.
2. **album**: the release itself has performer credits.
3. **band**: no performer credit is anywhere on the release (`band_of`: no track's, not the release's), the release
   is no compilation, its one credited artist is a Group, and its line-up (below) has anyone in it. It is never
   "song", which the app words "on this song". Its `source_url` is the artist's page.
4. **song** again: the placed song has no performers, but has its own writers or production.
5. **album** again: there's no performer anywhere, but the release has production credits of its own. For example,
   an unplaced song on Back in Black gives its "Additional engineer" and "Remastering".
6. **none**: nothing at all.

The route adds two levels: **unmatched** (the album has no release id, or MusicBrainz has nothing at it: a 404) and
**unavailable** (MusicBrainz or Navidrome couldn't be asked and nothing was kept, the deadline passed, the band's
lookup failed where it would have decided, deadwax stopping, or a fault in deadwax). Both are `empty()` answers: the
same keys, empty lists.

`written` and `production` are returned at every level where they are known. A level names what the performers are.

"none" can come from a release whose OTHER songs have credits while this one has none: `others_credited` says so,
for the app's words (the design's 4a, "MusicBrainz has no credits for this album yet", would be wrong there).

### Case 3: the band on the album's date (`line_up`, `membership`, `album_date`)

- The members are the artist's `member of band` relations, **backward** (the other artist is a member of this one),
  from get_artist (ARTIST_INC, which already has `artist-rels`: the artist page's own lookup, so it often costs
  nothing). It is asked only when `band_of` says a band could stand in.
- **Anyone nothing rules out** (App Design's ruling b; `membership`): a member counts unless their time began after
  the album's date or ended before it, compared at the precision both dates have (`order`: "1980-04" against "1980"
  can't be ordered; against "1980-07-25" it is before). An unknown start or end rules nothing out, and an `ended`
  with no end date is an unknown end. Back in Black shows the line: Brian Johnson joined in April 1980, Bon Scott
  died that February, and the album came out on 25 July 1980. With the date, Brian is in and Bon is out.
- **Joined and left**: where a start or an end can't be ordered against the album's date - so it falls in the
  album's own year - the member is listed with `joined` (or `left`) as that year, for the app's "joined 1980" or "left
  1980". With Back in Black's year alone, Brian is "joined 1980" and Bon "left 1980". A person with two memberships
  (MusicBrainz often has one per instrument) has a year only when every membership that counts gives one - one
  plainly covering the date leaves nothing in doubt.
- **Undated** (`dated`): false when no member has any date, or the album's date isn't known. Then every member is
  listed, with no joined or left, and the app heads it "The band's members" rather than "The band in 1980". true
  otherwise. Only "band" answers carry it; it is null at every other level.
- **The album's date** (`album_date`): the release group's first release date (original_year's). Navidrome's
  `originalReleaseDate` wins where it is more precise and agrees (1980-07-25 over 1980), and stands alone when the
  lookup has none. **Never a recording's first release**: the first commit took the earliest of those, which is a
  single's date when one came out before the album, or a compilation's oldest song's. Case 3's first song is such a
  single (November 1977, the album June 1978): measured against it, Pat (left January 1978) would be in and Quin
  (joined February) out. **Never the pressing's date** either: with no original date at all, nothing is measured
  (`dated: false`).
- **A compilation never has the band** (`band_of`): its songs come from other times than its date, so a line-up on
  that date would say who was in the band later. This one was not in the review: it follows from fixing the date.
- **The year** (`album_year`): album_date's year, else Navidrome's `year` (the date tag, the pressing's) - for the
  answer's `year` alone. An MP4 can't hold originaldate, so its albums take the release group's.
- What each played: the membership's attributes, with "original" and "founder" dropped, the credited form or the
  bracket dropped, and guest, solo and additional kept as words. Lead vocals come first, then other vocals, then the
  rest, by when they joined. A member with nothing known of what they played has `did: []`.

### Finding the song on its release (the route, then `navidrome_place` and `place`)

**Navidrome alone, as the asker**, not the store index or the library scan. The route's id is Navidrome's, so its
access check is Navidrome's too: getSong as the asker, where a song they may not have is a 404. Navidrome also has
everything needed, with no disk read, logins on or off:

- **getSong**: `musicBrainzId` is the RECORDING's id (the file's musicbrainz_trackid, Picard's recording id), read in
  Navidrome v0.64.2's responses.go as notes/app.md records. deadwax writes no recording id, so every song it filed
  sends "". `discNumber` and `track` are omitempty: absent when unset.
- **getAlbum** of its `albumId`: `musicBrainzId` is the release id, from the folder's MUSICBRAINZ_ALBUMID, as
  stars.py and the id bridge read it. Its `song` list gives the track numbers on the song's disc.
  `originalReleaseDate` gives the date.

No new Navidrome call: getSong and getAlbum are already on the player's list. They're asked through `client_for`
internally, never relayed, so `test_there_is_no_general_proxy` is unaffected. Only an MBID-shaped release id is ever
put in a lookup's address (`release_of`).

**A wrong pairing is worse than none** (`place`):

- When the file has a recording id, only that matches. An id the release doesn't carry is no pairing, never a fall
  back to the position. A MusicBrainz merge that changed the recording's id lands here: the album's answer, until
  the files are retagged.
- Otherwise, disc and track, only when **the track numbers of the album's songs on that disc in Navidrome are
  exactly the release's positions there** (`Where.numbers`). So a song more or less, two songs of one number, a gap
  or a song with no number refuses it. A missing disc number is read as the one disc of a one-disc release, never a
  guess between two, and is counted with the album's other disc-less songs.
- A medium whose `track-count` is more than its listed `tracks` (MusicBrainz cutting a huge release short) is never
  paired by position. **A pregap and data tracks don't enter this**: MusicBrainz keeps them apart, in a medium's own
  `pregap` and `data-tracks` keys, and outside BOTH `tracks` and `track-count`. Read on 27 Nov in musicbrainz-server's
  source: Data/Medium.pm counts `cdtoc_track_count` as the tracks at a position above 0 that aren't data tracks; the
  JSON Medium serializer sets `track-count` from it and `tracks` from `cdtoc_tracks`, the same set. The review asked
  to add the pregap and data tracks to the listed ones before comparing; per that source it would let a disc listed
  short pass whenever it has a data track, so the comparison is unchanged and
  `test_a_pregap_and_data_tracks_are_neither_listed_nor_counted_with_the_tracks` holds both ways.
- Navidrome's album stands in for the folder. Two folders tagged with one release id are one Navidrome album with
  every song doubled, so the numbers refuse them, which is the right answer.

### The route: `GET /deadwax/credits/song/{song_id}` (src/routes/credits.py)

- **A user's route** (tests/test_logins.py ROUTES), included with `signed_in`, with no permission of its own. Its
  Navidrome calls are made as the asker (`client_for`). The MusicBrainz answers are shared by everyone, since
  MusicBrainz's data isn't anybody's own.
- **The answer**:
  `{level, year, dated, others_credited, performers: [{id, name, did: [str], joined, left}], written: [{job, people:
  [{id, name}]}], production: [{job, people: [{id, name}]}], recorded: {begin, end, words} | null, source_url}`.
  - `level` is one of `song`, `album`, `band`, `none`, `unmatched`, `unavailable`.
  - `dated`: for "band", whether the line-up was measured against dates; null otherwise.
  - `others_credited`: a boolean, always.
  - `joined`, `left`: a year or null, on every performer; only a band's line-up sets them.
  - `source_url` is the release's MusicBrainz page (the artist's for "band"), or null for unmatched and
    unavailable.
  - Every string passes `lastfm.answerable` (a lone surrogate becomes U+FFFD, never a 500).
- **One lookup at a time per key** (`_asking`, as lastfm_kept's `asking`): the release by its id, the band by its
  artist id. However many ask at once (a page and the app's prefetch, two people on one album), MusicBrainz is asked
  once, and every ask awaits that one under `asyncio.shield`, so one that stops waiting never cancels it for the
  rest. The entry goes when the lookup ends; the next ask finds it kept.
- **A band MusicBrainz has nothing at** (a 404 for its artist id: deleted, merged away) is an answer: no line-up, so
  "none" (or the song's writers and production), never "unavailable". The client keeps successes only, so the 404 is
  kept here (`_no_artist`) for a day (NO_ARTIST_KEPT_S), the newest 512, and not asked again on every visit.
- **The deadline**, CREDITS_DEADLINE_S, 8 s. Each ask's lookup runs in a held task (`_held`). Past the deadline the
  answer is "unavailable" and the task goes on, so what comes is kept and the next ask has it. Without a deadline a
  person would wait out request_with_retries' ten attempts. `stop()` at shutdown, before the MusicBrainz connection
  closes, cancels every lookup under way, each ask's and the shared ones; an ask still waiting answers "unavailable".
- **Never a 500.** MusicBrainz away, Navidrome away (anything but its "not found"), deadwax stopping and a fault in
  deadwax are all "unavailable". Only two answers aren't a 200: a song the asker may not have (404, Navidrome's own
  "not found") and a session Navidrome ended (401).
- **The logs.** The route's own lines ("credits: …") go to deadwax's log at info, a fault in deadwax at warning, and
  none is marked for the event log. But the MusicBrainz client's own lines are, as for every MusicBrainz question:
  its network-error retries, a 503, a refused user agent, and its "failed to get valid response from MusicBrainz after
  retries". So an outage a credits lookup meets can show in the event log. (The first commit said "never the event
  log", which was true only of the route's own lines.)

### The tests (tests/test_song_credits.py, 48)

Named test_SONG_credits because tests/test_credits.py was already the artist-credit tests (names.md).

- **The real sample** (case 1, `tests/fixtures/credits/back-in-black-2003-us.json`, unchanged from the plans
  folder): every one of its ten tracks placed and shown. It was fetched with the first `inc`, before
  `release-groups`, so it has no release group; `with_group()` in the tests adds one (1980-07-25), said so there.
- **Made fixtures** for cases 2, 3 (a release and its band) and 4a, and a compilation, each marked `_made` and
  described in the fixtures' README.md. Case 3's release now has its release group and a first song released as a
  single months before the album. 4b is Navidrome's album with no release id, made in the test.
- **Not fetched.** The coordinator relayed James's yes to fetching three real answers, but this session's permission
  check refused the request to musicbrainz.org, so the made ones stand. A real answer replaces its file whole (the
  README says how).
- **Mutations, each applied and reverted** (the first commit's four, then the review's): listed in the commits'
  messages, each with the tests that failed.

### Not verified

- Cases 2, 3 and 4 and the compilation against real MusicBrainz answers: the fixtures are made from the documented
  shape. Back in Black's release group date (1980-07-25) is added in the test, not fetched.
- MusicBrainz's member-of-band attribute names beyond the instruments and vocals (taken here: "original",
  "founder", "additional"), and whether a membership ever carries `attribute-credits` (read the same way if it does).
- Navidrome's `originalReleaseDate` on a real 0.64.2 answer (from OpenSubsonic's AlbumID3, as read). The song's
  `musicBrainzId` being the recording's is from notes/app.md's reading of 0.64.2's source, not from a real answer.
- A box set's size and time.
- Whether 8 s is the right wait on a real phone.

### After review (27 Nov, the second commit)

The review of the first commit, and App Design's three rulings on it:

- **The album's date** was the earliest recording's first release: a lead single's date, or a compilation's oldest
  song's. Now the release group's (`release-groups` in the inc), with Navidrome's original date where more precise.
  CREDITS_SHAPE 2.
- **One lookup in flight per key**, shielded (above). Before, N asks at once were N MusicBrainz requests.
- **Ruling a**, the credited form; **ruling b**, anyone nothing rules out, with `joined`, `left` and `dated` (it
  replaced "surely covers", which left out anyone not dated closely enough to be sure); **ruling c**,
  `others_credited`.
- **Duplicate track numbers**: pairing by position needed only the counts to agree; now the numbers themselves.
- **A band's 404** was "unavailable"; now "none", kept.
- **`_number`** read digits with `isdigit`, so "²" raised in int(); now `isdecimal`.
- **The pregap and data tracks**: checked against MusicBrainz's source and left as they were (above).
- **Tests that survived mutation in the first commit**, now each failing it: the disk's shape check in
  `_saved_answer`, the route's fault guard (`task.cancelled() or task.exception()`), and `stop()` as a no-op.
- **The docs** said a failure was "never the event log"; the logs paragraph above is what's true.
