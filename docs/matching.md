# How matching works

Every folder a Soulseek search finds is scored against the release you picked, from 0 to 100.
The score is a weighted average of six signals. The candidates panel shows each one as a chip,
so you can see *why* a folder scored what it did rather than just trusting the number.

| signal | weight | measures |
| --- | --- | --- |
| **titles** | 30% | how many of the release's tracks have a file in the folder whose name matches the track's title |
| **count** | 20% | whether the folder has as many audio files as the release has tracks |
| **lengths** | 15% | of the tracks matched by title, how many files are within 8 seconds of the release's track length |
| **edition** | 15% | whether the folder's name agrees with the edition you picked, and mentions its year |
| **format** | 12% | lossless or lossy, against your format preference |
| **peer** | 8% | how soon you'd actually get the files: a free slot, a short queue, a fast connection |

## Each signal

**Titles.** Every track of the release is paired with the folder file whose name looks most
like its title. A name that contains the title outright ("03 - Strangers (remaster).flac"
contains "Strangers") is a perfect match; otherwise it's a fuzzy comparison, and anything below
60% similar doesn't count. Each file is used once. The signal is the share of tracks that found
a file. The same pairing is what later names and tags each file when the download is filed, so
a folder of `Track 04.mp3`s still gets proper titles. In a set shared one folder per disc, a
track only pairs with a file from its own disc's folder, because discs often repeat titles: a
second disc's "Wish You Were Here" is a different recording from the first's.

**Count.** An exact match scores full marks. Each track more or fewer takes off a share: one
missing track out of twelve is a small penalty, and half the album missing is a large one.

**Lengths.** The lengths MusicBrainz lists for the release, against the lengths the files
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

**Peer.** Half the signal is a free upload slot, then a short queue, then the user's advertised
speed. It carries the least weight on purpose: it's an availability tiebreaker, not a measure
of whether the files are right. The advertised speed is the user's average to everyone over
their whole history, so it isn't a prediction of your download.

## When a signal has nothing to go on

A signal with no information is **left out**, not scored as zero, and the weights of the others
are rescaled. With **Find** on an album card there's no tracklist, so titles, count and lengths
all drop out, and the score comes from edition, format and peer. With a release whose lengths
MusicBrainz doesn't know, lengths drops out.

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
