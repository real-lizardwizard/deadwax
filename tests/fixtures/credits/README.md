Answers for tests/test_song_credits.py - a song's credits from MusicBrainz (credits, slice C1). One is real; the rest are
**made, not fetched**, and say so in their own `_made` field.

**`back-in-black-2003-us.json`** - REAL. MusicBrainz's answer for Back in Black's 2003 US release,
`83ff6988-2f79-40b9-82d5-437f2a5da5f3`, fetched by the App Design session on 2026-11-27 with
`inc=recordings+artist-credits+artist-rels+recording-level-rels+work-rels+work-level-rels&fmt=json` (the lookup's
own `inc`, src/api/musicbrainz_endpoint.py CREDITS_INC). Copied unchanged from deadwax-plans/credits-sample-back-in-black.json.
Case 1: ten tracks, each with performer, producer, engineer and mix credits and its work's writers; the release's own
mastering, engineers, photography, design and liner notes.

**Made** (27 Nov 2026), in the shape of MusicBrainz's documented /ws/2 JSON and of the real answer above - no such
release or artist exists on MusicBrainz, and every id is a made one:

| file | case | what it holds |
| --- | --- | --- |
| `made-case2-album-credits.json` | 2, "on the album" | two discs (3 and 2 tracks); performer credits on the release only (a join, a qualifier, guest and solo, an orchestra and a conductor, a `target-credit`), production, and photography, design and liner notes that are never shown; works with a composer and a lyricist, a writer and a composer, and two writers |
| `made-case3-band-release.json` | 3, "the band in 1978" | four tracks, no relations anywhere, by one Group; each recording first released 1978-06-02 |
| `made-case3-band-artist.json` | 3 | that Group as get_artist answers it (only its relations matter): members who joined before, during and after 1978, one who left before, one with no dates, one ended with no end date, an additional member, and two relations that aren't its members |
| `made-case4a-nothing.json` | 4a, nothing | two tracks by one Person, no relations anywhere |

Case 4b (the album isn't matched to a release) needs no MusicBrainz answer: it is Navidrome's album with no
`musicBrainzId`, made in the test itself.

**A fetch of real answers for cases 2, 3 and 4a** was relayed as James's yes on 27 Nov ("Yes, fetch them"), but the
building session's permission check refused the request to MusicBrainz, so these stay made. A real answer replaces its made file whole: one release lookup
with the `inc` above (and, for case 3, the band's `artist/<id>?inc=artist-rels`), a line here naming its id, the date
and the `inc`, and the tests' expected values read from it.
