# The library

The **Library** tab shows what's in your music folder (`LIBRARY_PATH`): every album, including
ones deadwax never downloaded. It flags what's wrong with them and lets you fix it.

This page is about the main page's Library tab, the one for looking after the library. The phone
app at `/player/` has a Library tab of its own, for listening - **Albums**, **Artists** and
**Songs** from Navidrome, and an [artist page](player.md#artist-pages) with their albums from
MusicBrainz and Play and Shuffle over the ones you have - which the [phone player
guide](player.md#what-it-does) covers. [The app on a desktop](#the-app-on-a-desktop), below, says
how that Library is laid out in a window 1024 pixels wide or more, and [Editing an album in the
app](#editing-an-album-in-the-app) how this page's editors work from an album's page there.

## Opening it

The first time, the tab reads the tags off every file, which takes a while for a big library.
The result is saved, so every visit after that draws the saved copy **at once**, marked with its
age, and checks the folders for changes underneath it. Only folders that changed are read
again.

Albums filed from a download appear by themselves. **Rescan** re-reads everything, and is what
to press after changing files with another program: a tag edited elsewhere doesn't change a
folder's date, so it isn't noticed otherwise.

The status bar at the bottom counts albums, artists, tracks and size, and says when the library
was last scanned.

## The tree

Laid out like a file explorer: **artists**, their **albums** underneath, and the **tracks**
under an album. An album you hold more than one pressing of says **N editions** on its row, and
opens to one row per edition first.

- **Click** a row to select it and open it. The **triangle** opens and closes without
  selecting.
- **Keyboard**: up and down move, right opens (or steps in), left closes (or steps out), Enter
  toggles, Home and End jump to the ends.
- Rows carry small chips: **New** for albums filed since you last looked, the first
  **issue** that needs attention, and the edition count.
- On a phone, tapping an album or a track opens its details as a sheet; tapping an artist opens
  it in place, and **tapping it again** opens the artist's page.

It stays quick on a big library: only the rows in view are ever drawn.

![The library tab: Pink Floyd open, Wish You Were Here's two editions under it, and the two-disc Experience edition in the details pane, its discs headed "2011 Remaster" and "Unreleased Tracks"](../assets/images/library.png)

### Arranging

**Arrange by**: **Artist** (the tree above), **Album**, **Release date** or **Date added**.
The last three list albums directly under headings (a letter, a year, a month). **A–Z** flips
the direction. "Date added" is when deadwax first saw the album, or its folder's date if that's
earlier, so a library that was there before deadwax still sorts sensibly.

### Searching

The search box matches artists, albums, editions, and **song titles** (from two letters). A song
match opens its album and shows just the matching songs. Every artist with a match opens by
itself.

### Views

The views list narrows the tree (behind **Show** on a phone):

- **All albums**;
- **Multiple editions**: albums you hold more than one pressing of;
- **Newly added**: filed from downloads since you last looked at them;
- **Needs attention**: anything with an outstanding issue (below), and one view per issue.

## The details pane

Whatever you select shows on the right (a sheet on a phone):

- **Nothing selected**: the library's totals, and the most recently added albums.
- **An album with several editions**: a table of the editions, each with its year, tracks,
  length, size, format and anything it needs.
- **An album**: the cover (click it for the [cover viewer](#the-cover-viewer)), its facts, a pill
  for each edition, the **tracks**, and **Properties**: every tag that matters, where the cover
  came from, whether tracks carry their own pictures, CD art, and lyrics.
- **A track**: every tag in the file, the pictures embedded in it, and its lyrics.

The command bar across the top holds the album's actions: **Edit metadata…**, **Edit all
tracks…** (or **Edit N tracks…** with some ticked), **Get cover**, **Get lyrics**, **Get CD
art**, **Find on MusicBrainz** and **Delete…**. On a desktop, **Fields ▾** chooses the track
table's columns.

### The track table

Choose its columns from **Fields ▾** (or by right-clicking the header): tags, audio details,
MusicBrainz ids, file details. Drag a header to move a column, drag its right edge to resize
it, and double-click the edge to reset it. On a phone the table is always number, title and
length.

A tag that's only in the file (not the saved scan) shows `·` until the files have been read. A
disc number shown faded is a default: the file has no disc tag, so it counts as disc 1.

A multi-disc set is split under **Disc 1**, **Disc 2** headings, here and in the tree. A disc
that has its own title says it too: **Disc 4 · Live at Wembley 1974**, and so does a set kept
one folder per disc, on each folder's row. The title is the
`DISCSUBTITLE` tag (Picard's name for it; Navidrome shows it as well). deadwax writes it when a
download or an applied release gives the disc a title, and you can set it by hand (below). The
**Disc title** column shows what each file carries, including one that disagrees with the rest
of its disc.

## What needs attention

Each album is checked for these, fresh on every scan:

| issue | means | the fix |
| --- | --- | --- |
| No release id | never matched to a MusicBrainz release, so nothing else can be checked | pick its release in the metadata editor |
| No artist tag | no file names an artist, so the name shown came from the folder | apply a release |
| Mixed tags | the files disagree about which album they're from, often two albums sharing a folder | sort the files out, or apply a release |
| Split across folders | this folder holds only some discs of a release whose other discs are elsewhere | apply the release to each; the second merges into the first, which keeps anything you'd said was fine about it |
| Artist under two names | the artist's albums are under two folder names, usually a rename | **Move albums to …** on the artist's page |
| Folder off-convention | the folder isn't named the way its tags say it should be | apply its release, which re-files it |
| No original year | no `originaldate` tag, which the folder name uses | apply a release |
| No year | no date on any file | apply a release |
| Untitled tracks | some files have no title tag, so filenames are shown | apply a release |
| Unnumbered tracks | some files have no track number, so the order is alphabetical | apply a release |
| No cover art | no cover beside the tracks or inside them | **Get cover** |

**Review N**, in the toolbar, walks through every album that needs attention (and every album
newly filed), one at a time, in the metadata editor. For an album that's right as it is (a
bootleg that will never be on MusicBrainz, say), **It's fine as it is** stops it being flagged
for the issues it has now. It's still flagged if something new goes wrong, such as the cover
going missing.

## The metadata editor

**Edit metadata…** opens the editor on an album, already searching MusicBrainz using its artist
and album tags. You:

1. **Pick the release** the album really is from the list of pressings. The one the files
   already claim is marked **Current**. Each row shows year, format, country, catalogue number
   and track count; a track count in yellow doesn't match the files.
2. **Check the fields**: artist, album, year, original year, and edition. Blank fields are left
   alone rather than cleared. The edition is worked out from the release unless you type one.
3. **Read the preview**. It shows every tag that would change, file by file; whether the folder
   would move or be renamed (to follow the template, or the artist's current name); and, when
   the album is split across folders, whether it would merge.
4. **Cover art**: tick **download cover art** to save the release's cover from the Cover Art
   Archive, and compare it with the one you have (**Compare full size**) before replacing it.
5. **Apply** writes the tags, fetches the cover and moves the folder. There's no undo, which is
   why the preview shows everything first. When the apply changes both the album's tags and its
   folder, it writes the tags, pauses, then renames. That pause lets Navidrome see the new tags
   first and keep the album's plays, ratings and favourites, which it loses when both change at
   once. With Navidrome set up (the [phone player's](player.md) settings), deadwax asks it, and
   renames as soon as Navidrome has finished a scan that began after the tags were written,
   usually a few seconds; the button reads *Applying, waiting for Navidrome*. Without, it's a
   fixed pause (20 seconds by default, `RETAG_RENAME_WAIT`), and the button names it
   (*Applying, renaming in 20s*). The preview says which, up front. If Navidrome finishes no
   scan within 90 seconds, or can't be reached at all, the folder is left where it is and the
   editor says so. Apply the same release again once Navidrome has scanned: deadwax checks with
   Navidrome first and renames straight away if it has, or waits for a scan again if it hasn't.
   deadwax forgets a held-back rename when it restarts, and after that the next apply renames
   without asking
   ([troubleshooting](troubleshooting.md#applying-a-release-left-the-folder-where-it-was)).
   If a folder of the new name appears during the pause (another copy of the same release
   applied just before), the rename is refused and the album stays where it is, with its new
   tags.

   Navidrome can only say that a scan finished, not which folders it read. With one library
   that's enough, because a scan after a change is the one the change caused, or covers
   everything. With a second library in Navidrome, or an admin scanning some other folder at
   that moment, the rename can come before this album has been scanned.

![The metadata editor on an untagged rip of Third: its issues listed, the release picked, and the preview of the tags, the cover and the folder move](../assets/images/editor.png)

## Editing tags by hand

Tick tracks in the track table (Shift-click for a range, Ctrl/Cmd-click for one at a time), then
**Edit N tracks…**, or **Edit all tracks…** with none ticked. You can edit title, artist, album,
album artist, track, disc, disc title, date, original date, genre and composer. A disc title is
the one to set for a box set or a bootleg whose discs MusicBrainz leaves untitled: tick that
disc's tracks and type it once.

- A field whose value differs between the ticked tracks starts empty and says **Several
  values**. Leave it alone and each track keeps its own.
- Only fields you change are written. Emptying a field you changed **removes** that tag.
- The preview shows each change before **Apply**. If anything is invalid (a track number that
  isn't a number), nothing is written at all.
- It edits tags only; no file or folder is renamed.

## Covers, CD art and lyrics

- **Get cover** fetches the cover of the release the album's tags name, from the Cover Art
  Archive, at `COVER_ART_SIZE`, and saves it as `cover.jpg` (or `.png`). It only appears on albums
  that have a release id and no cover, and it never replaces one. To replace a cover, use the
  metadata editor, where you can compare the two. **Get covers · N** in the toolbar does every
  album in view that's missing one, one at a time; press it again to stop. "No cover on the
  Archive" and "the request failed" are counted separately, because only the second is worth
  trying again.
- **Get CD art** saves a picture of the disc itself, as `disc.jpg` (or `disc1.jpg`,
  `disc2.jpg`… per disc of a set), from the Cover Art Archive's scans of that exact release, and
  otherwise from fanart.tv if you've set a key. Navidrome shows it for the songs on that disc,
  and it's the face of the record on the phone player's [turntable](player.md#the-turntable).
  **Get CD art · N** does every album in view.
- **Get lyrics** looks up lyrics on LRCLIB for the tracks that have none, and saves each as a
  `.lrc` beside its track. The button then reports how many it found (**Lyrics · 9 of 10**, with
  the details in its tooltip). **Get lyrics · N** does every album in view that has no lyrics at
  all.

![A track's synced lyrics, with the time beside each line](../assets/images/lyrics.png)

**Why a song can show a different picture from its album:** some players (Navidrome, and so
apps like Amperfy) show a picture *embedded in the file* over the album's cover, and a disc scan
(`cd.jpg`) for songs with a disc number. An album's **Properties** and a track's view list the
pictures inside the files, so you can see which it is.

### The cover viewer

Click an album's cover to see it full size. Click (or tap) to zoom in on the point you touched,
use the wheel to zoom, or pinch on a phone; drag to move around; click again to fit. In the
metadata editor it shows your cover and the release's side by side.

## Artist pages

Select an artist (on a phone, tap it twice) for their page: a photograph, the facts MusicBrainz
has (type, origin, active years, other names, members), links, and their albums in your library.
Two links of the same kind say where each one goes (**Official site · portishead.co.uk**, and
**(archived)** for a page kept on the Wayback Machine), and every link's full address is in its
tooltip.

Which artist this is comes from the files' MusicBrainz artist ids. When the files have none, a
name search is used, but only when exactly one artist has that name. For a name several artists
share (there are eight called Nirvana), the page asks you to choose.

![Portishead's artist page](../assets/images/artist.png)

**Artist images…** shows every picture found, from Wikimedia Commons, TheAudioDB (with a key)
and fanart.tv (with a key), and saves your choices into the artist's folder:

| saved as | is | read by |
| --- | --- | --- |
| `artist.*` | the square photo | Navidrome (no configuration needed), Jellyfin, Kodi |
| `banner.*`, `fanart.*`, `logo.*`, `landscape.*`, `clearart.*` | wide banners, backgrounds, logos | Jellyfin, Kodi, and this page |

The extension is the picture's own (`.jpg`, `.png`…). Any picture can go in any slot, and a
folder that holds tracks is refused, since an `artist.jpg` there would mean something else.

![The Artist images dialog: the pictures found for each slot, and the square image already on disk](../assets/images/artist-images.png)

**An artist who has renamed.** When MusicBrainz knows the artist by another name now, the page
says **Now: …**. If their albums are filed under two folder names, **Move albums to …** moves
them all under the current name, with a preview first. It rewrites the album-artist tag, leaves
each track's credited artist alone, and removes the old folder once it's empty.

**In the phone app** an artist has a page too (since 2.0.0-player.17; [the phone player
guide](player.md#artist-pages) has it): the square `artist.*` picture saved here is its hero, as
Navidrome serves it, and the MusicBrainz artist ids deadwax writes into your files are how it
finds the artist's discography when Navidrome doesn't say who they are. An album filed by
another tool, without those ids, still shows there - just without MusicBrainz's albums beside it.

## The app on a desktop

The app at `/player/` (not this page) has a desktop layout since 2.0.0-player.19, in a window 1024
pixels wide or more - [the phone player guide](player.md#on-a-desktop) has all of it. For the
Library:

- **Its views are in the sidebar**: **Recently added**, **Albums**, **Artists** and **Songs**, the
  one showing highlighted - and its title is that view's name ("Albums"), with the sort and the count
  at the title's right. **Recently added** is Navidrome's albums newest first, a view of its own, so
  **Albums** keeps the order you chose for it; it's the desktop's alone, and isn't remembered on the
  device (a phone shows the albums for it). **Songs** is left out when Navidrome won't list songs,
  as on a phone.
- **Albums** are a grid six covers across (fewer while a panel is a column beside it, so a cover
  stays a cover's size); **Artists** and **Songs** are the phone's lists, kept a readable width.
- Clicking the view that's showing works like the phone's Library tab: from elsewhere in the app it
  shows the Library as you left it (an album you opened from it still open), and on the Library it
  goes back to its first page (and, there, to the top). Another view shows that view - where you
  left it if you were already on the Library's first page, at its top from anywhere else.
- **Editing an album** - this page's metadata editor, tag editor, covers, lyrics and delete - is on
  the album's own page, its **Edit** button (since 2.0.0-player.21; [below](#editing-an-album-in-the-app)).
  The albums that need a look (**Review N**), the bulk runs (**Get covers · N** and the rest), an
  artist's pictures and **Move albums to …** are still this page's: the sidebar's **Managing** opens
  it in a new tab.

## Editing an album in the app

In the app at `/player/`, on a desktop (a window 1024 pixels wide or more), an album's page has
**Edit** after **Play** and **Shuffle** (since 2.0.0-player.21). It opens the **Edit album** panel
beside the page, and shows pressed while the panel is open; click it again to close the panel. It's
there for an admin, which with logins off is everyone. There's no editor on a phone.

The panel holds this page's own editors, not copies of them - so everything this page says about
them is true there too:

- **Release** is [the metadata editor](#the-metadata-editor): it searches MusicBrainz as it opens,
  you pick the pressing, check the fields, read the preview and **Apply**, with the same pause before
  a rename (*Applying, waiting for Navidrome*, or *Applying, renaming in 20s*) and **Compare full
  size…** for the cover. **Cancel** closes the panel; nothing is written until **Apply**. **It's
  fine as it is** is there for an album with issues, as here.
- **Tags** lists the album's tracks with a tick box each. Tick some (Shift ticks a run), then **Edit
  N tracks…**, or **Edit all tracks…** with none ticked, for [the tag editor](#editing-tags-by-hand):
  only the fields you change are written. **Cancel**, **Close** or Escape goes back to the list.
- **Artwork** shows the cover the album has and what CD art is beside its tracks, with **Get cover**
  and **Get CD art** where they can help ([as here](#covers-cd-art-and-lyrics)): each needs the
  album's release id, so an untagged album is matched in **Release** first. A cover you have is
  replaced from **Release**, comparing the two.
- **Lyrics** says how many tracks have a `.lrc`, with **Get lyrics** for the rest. The lyrics lead,
  and re-timing what is saved, are in this page's settings.
- **Delete** is [the delete confirmation](#deleting-an-album): what the folder holds, read as you
  open the tab, and **delete permanently**. **Cancel** (or Escape) goes back to **Release**.

**Which folder.** The album page knows the album by Navidrome's id; the editors work on a folder.
deadwax finds it by the album's MusicBrainz release, as the store index has it (the same lookup that
gives the album page its "Also: …" chips). An album Navidrome knows by **no** release - a rip that was
never tagged, exactly what the release editor is for - is found among the library's folders that
carry no release id either, by its name and artist (and its track count, when that still leaves
several); when more than one folder fits, the panel asks which. A release kept one folder per disc
starts on the first folder, with a **Folder** choice above the tabs for the others - apply the
release to each, as here, and they merge. The panel reads the library the first time you press
**Edit**, and again, behind what it shows, each time after - the app can be left open for hours, and
an album changed meanwhile from this page or another device is shown as it is now.

**After an edit**, the album page asks Navidrome again at once and once more ten seconds later
(Navidrome notices a change about five seconds after it's made, then scans), and the app's marks of
what you hold are asked again. Applying a **different** release gives the album a new id in Navidrome:
the page follows it, in place, once Navidrome has scanned (it keeps looking for about 45 seconds,
whatever else you edit meanwhile), so it shows the album as it is now rather than one Navidrome no
longer has - and if you'd gone to another page meanwhile, going back to the album shows it under its
new id too. Deleting the album closes the panel and goes back from its page - unless it was one folder
of several, when the page stays and is asked again, at once and ten seconds later. The Library's grid
is Navidrome's, so it changes once Navidrome has scanned.

The panel is a side panel like Sources and Info - a third column from 1280 pixels wide, lying over
the right of the page below that - and one shows at a time: **Edit** puts Sources and Info away, and
either puts the Edit panel away. It closes when you go to another page, and when the window narrows
to a phone's. The close button, or Escape while you're in the panel, closes it - in the tag editor or
the delete confirmation, Escape closes that first, back to its tab; Escape out in the page (in the
search field, say) is the page's. Between 1024 and 1279 pixels wide, while it lies over the page, the
album's **Play**, **Shuffle** and **Edit** move under its cover, so **Edit** stays in view to close it.

## Deleting an album

**Delete…** removes the album's folder and everything in it, **permanently**. The confirmation
names the track count and size, and lists any files that aren't audio, in case one is the only
copy of a rip log. It only ever deletes a folder that holds audio directly, inside your library,
and never the library folder itself. A deleted album leaves the **New** count and the review
queue straight away.
