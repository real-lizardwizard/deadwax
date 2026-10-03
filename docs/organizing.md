# Organizing

When a download finishes, its files are tagged from the release you picked and filed into your
library. This is the only thing deadwax does to your filesystem on its own, so it's cautious by
default.

## The four modes

`ORGANIZE_MODE`, set in Settings → Library → Organizing or in your compose file:

| mode | what happens when a download finishes |
| --- | --- |
| `off` | nothing; the files stay where slskd put them |
| `dry_run` *(the default)* | the event log says where each file would be filed, and nothing is written. Use it to check your paths. |
| `copy` | files are tagged and **copied** into the library, and slskd's copies stay where they are |
| `move` | files are tagged and **moved** into the library, and slskd's folder is cleaned up afterwards (below) |

Settings → Library says whether organizing is ready, and lists everything stopping it (a
path that doesn't exist from inside the container, say) all at once.

## Where an album goes

```
<LIBRARY_PATH>/<artist>/<album folder>/<NN - title>.<ext>
Pink Floyd/Wish You Were Here (1975) [2011 remaster]/01 - Shine On You Crazy Diamond, Parts 1–5.flac
```

- **The artist folder** is the artist's **current** name on MusicBrainz, even when the album
  was credited to an older one. Donda (credited "Kanye West") and BULLY (credited "Ye") both go
  in `Ye/`. The credit is still what's written in each track's artist tag, because it's what
  the sleeve says. A collaboration gets a folder of its own (`JAY-Z & Ye/`).
- **The album folder** follows the template below.
- **Tracks** are named by their number and title from the release (`01 - Mysterons.flac`). A
  multi-disc set is numbered straight through, so it stays in order inside one folder; the disc
  numbers go in the tags. A file that couldn't be matched to a track keeps its own name.
- **A second copy isn't filed beside the first.** If the folder already has a track, whatever
  its format, the new file is left in slskd's folder. When the folder holds the same release,
  "already has" means the same disc and track number; when it holds another pressing, or files
  with no release id, it means the same title, since two pressings can number their tracks
  differently (the US *Dummy* has an extra song at 6). A download of an album already there
  ends as *already in the store*. A track the folder is missing still files, so a second
  download can finish an album a first one left partial. When any track is left behind, so are
  the download's cover and sidecars (log, cue and so on): they describe the copy they came with,
  not the one already filed.

### Folder names

The album folder is named from `ALBUM_FOLDER_TEMPLATE`, by default
**`{album} ({year}) [{edition}]`**. The tokens:

| token | is |
| --- | --- |
| `{album}` | the album title (required) |
| `{artist}` | who it's by, in their current name |
| `{year}` | the **album's** year, its first release |
| `{release_year}` | **this pressing's** year: a 2011 remaster says 2011 |
| `{edition}` | the edition, when there's one to tell pressings apart |
| `{format}` | CD, 12" Vinyl, Digital Media… |
| `{country}` | GB, US, JP… |
| `{catalog}` | the catalogue number |

A token that comes out empty takes its brackets with it: an album with no edition is just
`Dummy (1994)`, not `Dummy (1994) []`. A template can't contain `/` (it names the album folder
only), and it has to include `{album}`. The settings tab refuses one that breaks those rules,
and shows what two example albums would be called.

**Changing the template moves nothing already filed.** Albums filed under the old one show as
*folder off-convention* in the library, and move when you next apply a release to them in the
metadata editor.

**Why `{year}` is the album's year:** a 2011 remaster of a 1975 record files under
`Wish You Were Here (1975) [2011 remaster]`, next to the original, rather than in a different
decade depending on which copy you happened to get. The pressing's own year is still written to
its `date` tag, and the album's to `originaldate`.

### Editions

The edition is what lets two pressings of one album sit side by side instead of colliding. It
comes from, in order:

1. what MusicBrainz calls the release (its *disambiguation*, such as "2011 remaster");
2. edition words in the release's details: remaster, deluxe, super deluxe, expanded,
   anniversary, limited, special edition, box set, instrumental, acoustic, a cappella;
3. a notable format, such as vinyl or cassette;
4. the country, only if `COUNTRY_IN_FOLDER` is on.

An ordinary, one-edition album gets no edition in its folder name, so the common case stays
clean. If a **different** release would still land in the same folder, its catalogue number,
and failing that its release id, is added. A folder with **no MusicBrainz tags at all** (an old
rip) is never treated as a different release, because forking every album that predates deadwax
would be worse than sharing a folder.

Instrumental, acoustic and a cappella versions count as editions for a reason: they have the
same titles and track count as the album itself, so without one every file would look like one
already there, and nothing would be filed.

## What's written into each file

From the release you picked: title, artist (the track's own credit, so a compilation keeps its
eighteen artists), album, album artist, track number, disc number (on multi-disc releases), the
disc's own title where MusicBrainz gives it one (a box set's "Live at Wembley 1974"), date,
original date, catalogue number, release country, media, and the MusicBrainz release,
release-group and artist ids.

Existing files are never overwritten. If a track of the same name is already in the library,
that track is skipped and the job says so, so an album that didn't arrive can't be marked done
without a word.

## Covers, sidecars and lyrics

- **Covers and other sidecars** (images, `.cue`, `.log`, `.nfo`, `.txt`, `.m3u`, `.sfv`) that
  are in slskd's download folder next to the tracks come along into the library. Only audio is
  downloaded from Soulseek, so these are there only if slskd happened to fetch them. An album
  that arrives without a cover shows up in the library's review queue, and **Get cover** fetches
  one from the Cover Art Archive (see [The library](library.md#covers-cd-art-and-lyrics)).
- **Lyrics** are looked up on [LRCLIB](https://lrclib.net) for each track once the album is
  filed (unless `FETCH_LYRICS` is off), and saved as a `.lrc` file with the track's own name,
  beside it. Synced lyrics are saved when LRCLIB has them, plain ones otherwise; an
  instrumental gets nothing. Navidrome, Jellyfin and Kodi read `.lrc` files with no
  configuration. Nothing is fetched in dry run.

## Clean-up after a move

In `move` mode, once every file of a download has been filed, the folder slskd downloaded into
is removed, along with anything left in it. That's the files nobody chose to keep
(`Thumbs.db`, checksums, a `Scans/` folder), since the sidecars worth keeping have already moved
with the tracks. The log names what was removed.

**Audio stops it.** If any audio file is still anywhere in that folder, it's left alone and
reported: that's music that was never filed, perhaps from a second download into the same
folder that's still arriving. Nothing is removed if any file of the download failed or was
skipped.

With `SLSKD_INCOMPLETE_PATH` set, the empty folders slskd leaves behind in its incomplete
folder are also swept every ten minutes. It only ever removes *empty* folders, never one that
changed in the last ten minutes, and never a partial file or the folders holding one.

## Correcting an album afterwards

Filing a download - and the lyrics fetched with it, unless `FETCH_LYRICS` is off - is all deadwax
writes into your library on its own. Correcting an album afterwards - applying the release it really
is, editing tags by hand, fetching a missing cover, CD art or lyrics later, deleting it - is something
you ask for, previewed first where it can be: in the main page's Library tab
([the library guide](library.md#the-metadata-editor)), or, in the app at `/player/` on a desktop,
from an album's own page with **Edit** (since 2.0.0-player.21, [editing an album in the
app](library.md#editing-an-album-in-the-app)). Both are the same editors with the same rules: a
re-applied release files the album where a fresh download of it would go - this page's template,
its edition, the artist's current name - and a rename that comes with new tags waits for Navidrome
to see the tags first.
