# How matching works

Every source a search finds - one user's folder of the album on Soulseek - is scored against the
release you picked, and its card shows the score as a percentage: **70%** is a 70% match. The score
is a weighted average of six signals. Each source card shows each one as a chip with its own
percentage, and what it measures written beside it, under **Why it's a 70% match**
([downloading](downloading.md#choosing-a-source)), so you can see *why* a source scored what it did
rather than just trusting the number.

| signal (as the card names it) | weight | measures |
| --- | --- | --- |
| **Track names** | 30% | how many of the release's tracks have a file in the folder whose name matches the track's title |
| **Track count** | 20% | whether the folder has as many audio files as the release has tracks |
| **Track lengths** | 15% | of the tracks matched by title, how many files are within 8 seconds of the release's track length |
| **Edition** | 15% | whether the folder's name agrees with the edition you picked - mentioning its year helps |
| **Format** | 12% | lossless or lossy, against your format preference |
| **Availability** | 8% | how soon you'd actually get the files: a free slot, a short queue, a fast connection |

The lines beside the chips say the same in a few words: *the pressing's tracks it has, found by
their names*; *how near its number of files is to the pressing's tracks*; *the tracks found whose
length is right, to within 8 seconds*; *whether its name says the same edition (deluxe, remaster…) - its
year there helps*; *lossless or not, as your Format asks*; *how soon it can start: a free slot, a short
queue, their speed*. (Until 2.0.6 the chips were *Titles*, *Count*, *Lengths* and *Peer*, with
bare numbers.)

## Each signal

**Track names.** Every track of the release is paired with the folder file whose name looks most
like its title. A name that contains the title outright ("03 - Strangers (remaster).flac"
contains "Strangers") is a perfect match; otherwise it's a fuzzy comparison, and anything below
60% similar doesn't count. Each file is used once. The signal is the share of tracks that found
a file. The same pairing is what later names and tags each file when the download is added to your library, so
a folder of `Track 04.mp3`s still gets proper titles. In a set shared one folder per disc, a
track only pairs with a file from its own disc's folder, because discs often repeat titles: a
second disc's "Wish You Were Here" is a different recording from the first's.

**Track count.** An exact match scores full marks. Each track more or fewer takes off a share: one
missing track out of twelve is a small penalty, and half the album missing is a large one.

**Track lengths.** The lengths MusicBrainz lists for the release, against the lengths the files
report. Different masterings drift by a second or two, and that's within tolerance; a live take
or a different recording won't line up. This is what catches a folder that has the right titles
but is the wrong recording.

**Edition.** Words like *remaster*, *deluxe* or *anniversary* in the folder's name, against the
edition of the release you picked. If you picked a special edition, the more of its words the
folder shares, the better. If you picked an ordinary pressing, a folder calling itself *DELUXE*
scores lower, because it's probably something else. A folder that mentions the release's year
gets a bonus, because reissues usually carry their year.

**Format.** With **Prefer lossless** (the default), a folder with FLAC or another lossless
format scores full marks and an all-lossy one scores less, but still counts. **Lossless only**
drops lossy folders from the list entirely. **Any format** ignores it.

**Availability.** Half the signal is a free upload slot, then a short queue, then the user's advertised
speed. It carries the least weight on purpose: it's an availability tiebreaker, not a measure
of whether the files are right. The advertised speed is the user's average to everyone over
their whole history, so it isn't a prediction of your download.

## When a signal has nothing to go on

A signal with no information is **left out**, not scored as zero, and the weights of the others
are rescaled. With a **Get** of the album as a whole (MusicBrainz couldn't list its pressings) there's no
tracklist, so track names, track count and track lengths
all drop out, and the score comes from edition, format and availability. With a release whose
lengths MusicBrainz doesn't know, track lengths drops out. A signal left out has no chip on the card.

## Why edition is never a filter

Soulseek folder names are typed by the people sharing them, and they very often leave out edition
text altogether. A folder that *is* the 2011 remaster may well be called just
`Pink Floyd - Wish You Were Here`. Hiding folders whose names don't mention the edition would hide
real matches. So edition only nudges the score, and the ranking shows its reasoning, so you
choose with the information in front of you.

This is also the honest limit of the whole approach: deadwax can't reliably tell a remaster from
the original when nobody wrote it down. The track lengths are often the best clue, and they're in
the score.

## Searching under every name

The artist isn't one of the signals: a folder filed under `Ye/` and one filed under
`Kanye West/` score the same. The name matters for *finding* folders, because Soulseek only
returns folders whose paths contain every word of the query. So each search runs under the
album's credited artist, the artist's current name, and any former names MusicBrainz records,
side by side.

## A manual search

A manual search is the iPhone and Mac app's **Search Soulseek**: an artist and an album typed by hand,
for an album MusicBrainz doesn't have or one you'd rather find by name. There's no release behind it,
so there's no tracklist, year or id: track names, track count and track lengths all drop out, as they
do for an album as a whole. On their own, edition, format and availability can't tell the album you
typed from another album the same words found, so a manual search adds a seventh signal, **Folder
name**: *how closely the folder's name is the artist and album you typed*. Nothing on the web sends
one, and every other search is scored exactly as above.

**Folder name** is mostly the album. The folder's own name (with its album folder, for a disc folder
like `OK Computer / CD 1`) is compared word for word with the album you typed, and the score is how
many words the two share out of all the words either has: `OK Computer` against
`OK Computer OKNOTOK` shares two words out of three. Before they're compared:

- the artist's words are taken out of the folder's name. When the album has them too - a
  self-titled album - only the artist's own are: the ones before a dash, or one too many. So typed
  *Weezer* / *Weezer*, `Weezer - Weezer (1994)` and a `Weezer (Blue Album)` folder inside `Weezer/` fit,
  while `Weezer - Pinkerton` doesn't;
- format words, years and other numbers, bitrates and sample rates, disc markers, *the*, *a*, *an*
  and *and* are taken out, unless the album you typed has them (`1989` still fits `1989 (2014)`), so
  `Radiohead - 1997 - OK Computer [FLAC 24-96]` is a perfect fit;
- edition words (*deluxe*, *remaster*, *instrumental*… and *edition*) are left to the Edition signal,
  so they're never counted twice;
- a folder whose name is nothing but those words - `FLAC` inside `OK Computer` - is read by the folder
  above it.

The rest of Folder name is the artist: the share of the artist's words found anywhere in the folder's
path, or in at least half its files' names. The album is 65% of it and the artist 35%.

The score is then **80% Folder name** and 20% the usual blend of edition, format and availability, so
the folders that are the album you typed come first, and among them, FLAC before MP3 and a free slot
before a queue: a perfect fit in MP3 from a slow user ranks above a FLAC from a fast one called
`OK Computer OKNOTOK`. An edition word you typed (*Deluxe*) is asked for as an edition, as it is for a pressing. The
80% and 65% are reasoned from how folders are named, not yet measured.
