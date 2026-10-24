# The deadwax guide

Everything deadwax does, explained for someone opening it for the first time. deadwax is one app,
at `/player/` (`/` opens it too), on a phone and on a desktop. The [project README](../README.md) is
the tour; this is the manual.

## Start here

1. **[Getting started](getting-started.md)**: what you need, the compose file, and the first run,
   step by step, including the one path that trips everyone up.
2. **[Configuration](configuration.md)**: every setting, what it does, its default, and where to
   change it.

## Using it

| page | covers |
| --- | --- |
| [Finding music](finding-music.md) | Search: one box, your library first, then MusicBrainz's artists, albums and songs; what deadwax has saved; the album you don't have and its pressings, and "in your library" marks |
| [Downloading](downloading.md) | Get, and choosing a source: what the scores mean, the chips and Match details, Requests, cancelling and retrying a failed download, downloads per person |
| [Organizing](organizing.md) | what happens when a download finishes: dry run, copy or move, folder names and templates, editions, tags, covers, lyrics, and clean-up |
| [The library](library.md) | looking after it: what needs attention, the Edit panel (release, tags, artwork, lyrics, delete), Needs a look, Library care, artist pages |
| [Sharing deadwax](sharing.md) | letting other people use it: logins through their own Navidrome accounts, what each person gets and what stays shared, admins and everyone else, adding and removing people, turning logins off again |
| [The app](player.md) | the app itself: setting up Navidrome, adding it to the home screen, the tabs, the player and the turntable, how plays are counted, looking after deadwax from a phone, the desktop layout, and what it can't do yet |
| [How matching works](matching.md) | the six signals a candidate is scored on, and why edition is never a filter |
| [Troubleshooting](troubleshooting.md) | what to do when something doesn't work, by symptom |

## The ideas it's built on

A few words mean something specific here, and the rest of the guide leans on them.

- **Release group**: an album as an idea. *Dummy* by Portishead is one release group, whatever
  format or country or year you hold it in. Search results are release groups.
- **Release**: one specific pressing of it. The 1994 UK CD, the 2014 20th-anniversary vinyl, the
  Japanese SHM-CD. MusicBrainz lists them all, and each has its own tracklist, catalogue number
  and id. This is the level deadwax works at: you pick the pressing you actually want.
- **Edition**: what tells one pressing of an album apart from another in *your* library: "2011
  remaster", "Deluxe edition", "Instrumental". It goes in the folder name, so two editions of
  one album sit side by side instead of overwriting each other.
- **Source** (or candidate): one folder on one Soulseek user's share that might be the release you
  picked. A search usually finds several; deadwax scores each against the release's real tracklist.
- **Peer**: the Soulseek user sharing a source.
- **Job**: one download as deadwax remembers it. It keeps the release it's for, which is what
  lets a finished download be tagged and filed even if MusicBrainz is down at the time.
- **Dry run**: organizing that only *reports* what it would do. It's the default, because
  organizing is the one thing that writes to your music library.

## The flow, end to end

1. **Search** MusicBrainz for an album, open it, and pick the exact pressing you want.
2. **Get the album** searches Soulseek through slskd, under every name the artist has gone by, and
   ranks what comes back against that pressing's tracklist.
3. **Get** on a source queues that folder in slskd. **Requests** follows it.
4. When it finishes, the files are tagged from MusicBrainz and filed into your library (or, in
   dry run, the log says where they would have gone), and lyrics are fetched for each track.
5. Navidrome scans it, and it's in your Library to play. **Needs a look** flags what's wrong with an
   album (a missing cover, say), and **Edit** fixes it.

## On a phone and on a desktop

It's one app with five tabs - **Home**, **Library**, **Search**, **Requests** and **You** - and a
player inside them, made to be added to an iPhone's home screen and opened like an app
([adding it](player.md#adding-it-to-an-iphones-home-screen)). Each tab keeps its own pages, as an
iPhone app's do, and looking after deadwax is in **You → Manage**, laid out for a phone.

In a window 1024 pixels wide or more it has [a desktop's layout](player.md#on-a-desktop): a sidebar
for the tabs and for **Manage** (Needs a look, Library care, People, Server settings and Event log), a player
bar along the bottom, an album's sources, Info and the Edit panel beside the page, and a full-screen
[visualizer](player.md#the-visualizer) from the player bar. Resizing across 1024 pixels swaps the
layout without stopping the music.

<p>
<img src="../assets/images/mobile.png" width="280" alt="Search on a phone">
&nbsp;&nbsp;
<img src="../assets/images/mobile-library.png" width="280" alt="An album's page on a phone">
</p>

## For developers

[CLAUDE.md](../CLAUDE.md) holds the project's rules, its settled decisions and the map of the code,
and [`notes/`](../notes/) every design decision in full, and why.
