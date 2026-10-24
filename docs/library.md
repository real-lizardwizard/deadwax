# The library

Your music folder (`LIBRARY_PATH`) is two things in deadwax. **The Library tab** is for listening:
your albums, artists, songs and playlists as Navidrome lists them, laid out as Apple Music's - see
[the app guide](player.md#the-library). This page is about **looking after** it: every album folder on
disk, including ones deadwax never downloaded, what's wrong with each, and the editors that fix them.

All of it is in the app, on a phone and on a desktop:

- **Edit** on an album's page opens [the Edit album panel](#editing-an-album): its release, its tags,
  its cover and CD art, its lyrics, and deleting it.
- **Needs a look** lists [the albums that want attention](#needs-a-look) - and those Navidrome doesn't
  list, so no folder on disk is out of reach.
- **Library care** has [Rescan and the bulk runs](#library-care) that fetch covers, CD art and lyrics.
- An artist's page has [their pictures, and moving their albums under their current name](#artist-pages).

On a desktop (a window 1024 pixels wide or more) Needs a look and Library care are the sidebar's,
under **Manage**; on a phone they're in **You → Manage**. They're there for an admin,
which with logins off is everyone - and for anyone an admin gives their permission to
([Sharing deadwax](sharing.md#admins-permissions-and-everyone-else)).

![Wish You Were Here's two-disc Experience Edition in the app: its discs headed "2011 Remaster" and "Unreleased Tracks", with Edit beside Play and Shuffle](../assets/images/library.png)

## Reading the library

The first time, deadwax reads the tags off every file in the library, which takes a while for a big
one. The result is saved in deadwax's database, so after that every page that reads the library -
Needs a look, Library care, the Edit panel - draws the saved copy **at once**, says how old it is,
and checks the folders for changes underneath it. Only folders that changed are read again, and after
a restart too nothing is read twice.

Albums filed from a download appear by themselves. **Rescan**, in [Library care](#library-care),
re-reads everything, and is what to press after changing files with another program: a tag edited
elsewhere doesn't change a folder's date, so it isn't noticed otherwise.

The Library tab itself is Navidrome's: an album filed shows there once Navidrome has scanned it,
usually seconds later.

## What needs attention

Each album is checked for these, fresh on every scan:

| issue | means | the fix |
| --- | --- | --- |
| Not matched to MusicBrainz | never matched to a release on MusicBrainz, so nothing else can be checked | pick its release in **Edit → Release** |
| No artist tag | no file names an artist, so the name shown came from the folder | apply a release |
| Mixed tags | the files disagree about which album they're from, often two albums sharing a folder | sort the files out, or apply a release |
| Split across folders | this folder holds only some discs of a release whose other discs are elsewhere | apply the release to each; the second merges into the first, which keeps anything you'd said was fine about it |
| Artist under two names | the artist's albums are under two folder names, usually a rename | **Move albums to …** on the artist's page |
| Folder name doesn't match the tags | the folder isn't named the way its tags say it should be | apply its release, which renames it to match |
| No original year | the tags don't record the album's first year (the `originaldate` tag), which the folder is named after | apply a release |
| No year | no date on any file | apply a release |
| Untitled tracks | some files have no title tag, so filenames are shown | apply a release |
| Unnumbered tracks | some files have no track number, so the order is alphabetical | apply a release |
| No cover art | no cover beside the tracks or inside them | **Edit → Artwork → Get cover** |
| Not in Navidrome | Navidrome doesn't list the album, so the app can't show or play it ([below](#not-in-navidrome)) | let Navidrome scan it, make its files readable to Navidrome, or point Navidrome at this music folder |

Each chip's line - in **Edit → Release**, and when you point at a chip in **Needs a look** - says the same in a
sentence or two: what's wrong, then what fixes it.

For an album that's right as it is (a bootleg that will never be on MusicBrainz, say), **It's fine
as it is**, in **Edit → Release**, marks it fine: it stops being flagged for the issues it has now.
It's still flagged if something new goes wrong, such as the cover going missing. Such an album leaves
the queue, and **Needs a look → Marked fine** lists it, so it can always be opened again - to undo
that with **Ask about it again**, fix it after all, or delete it ([below](#needs-a-look)).

### Not in Navidrome

The app's library is Navidrome's, so deadwax checks each album folder against the albums Navidrome
lists, and raises one it doesn't as **Not in Navidrome** in **Needs a look**. That way no folder on
disk is out of reach: the rest of the app can't show or play it, but the queue lists it and the Edit
panel opens on it like any other.

- **How it's checked.** A folder is in Navidrome when Navidrome has an album with its release id. A
  folder with no release id (or whose album Navidrome knows by none) is matched by its album title and
  artist instead, as both are spelled in the tags (case, accents and curly quotes aside) - a folder
  whose files name no artist at all as Navidrome's "[Unknown Artist]". A folder with no album artist
  tagged (or Various Artists) also matches an album Navidrome credits to Various Artists by its title
  alone; one with an album artist of its own never does, so Queen's *Greatest Hits* isn't taken for a
  compilation of that name. A folder whose files carry no album tag at all isn't checked: Navidrome
  files those under "[Unknown Album]", with no name to match.
- **When.** Each read of the library is checked against Navidrome's last answer, and never waits for
  Navidrome: when that answer is more than ten seconds old, a read from the disk asks Navidrome again
  behind it, for the next read. Only Navidrome's very first answer (after deadwax starts, or its
  Navidrome settings change) is waited for, at most three seconds, and **Rescan** always asks and waits
  as long, so Rescan is the way to see the check afresh. The saved scan drawn first asks nothing.
  Usually it's one quick question: Navidrome's albums are listed again only once it has finished a
  scan since the last time.
- **Never too soon.** A folder that changed after Navidrome's last scan began - filed a moment ago,
  filed while Navidrome was scanning, moved or copied in by hand (deadwax goes by when it arrived, not
  the old date `mv` or `rsync -a` keep on it), a release just applied, a cover just fetched - isn't
  newly flagged until a scan that began after it has finished (usually seconds later: Navidrome's file
  watcher scans a change about five seconds after it), and one already flagged stays flagged until
  then, also when deadwax renames or re-files it, and across a restart of deadwax. But not for ever:
  a folder outside Navidrome's music folder never wakes its watcher, so when no scan has come 15
  minutes after the change, the folder is checked anyway. While Navidrome is scanning, only the albums
  already found missing are marked.
- **Nothing raised without an answer.** Until Navidrome has answered, with Navidrome not set up, or
  when it can't be asked, no album is marked, and **Needs a look** says why once, in the line above its
  list where *Checking the library…* shows ([below](#needs-a-look)).
- **Fixing it** - see [troubleshooting](troubleshooting.md#an-album-says-not-in-navidrome): start a scan in
  Navidrome, make the files readable by the user Navidrome runs as, or point Navidrome at the folder
  `LIBRARY_PATH` reads. **It's fine as it is** marks it fine, as for any issue - and **Needs a look →
  Marked fine** keeps it in reach.

## Editing an album

An album's page has **Edit**. On a desktop it's after **Play** and **Shuffle**, and opens the **Edit
album** panel beside the page, showing pressed while the panel is open; click it again to close the
panel. On a phone - any window narrower, an iPad held upright included - **Edit** is at the top of the
page, beside the pin, and opens the same panel as a sheet over the whole screen, laid out for a phone:
its fields big enough that iOS doesn't zoom into them, **Apply** kept at the sheet's foot as you
scroll. It's there for an admin, which with logins off is everyone (and for anyone an admin gives Edit
albums or Look after the library - [Sharing deadwax](sharing.md#admins-permissions-and-everyone-else)).
A row of **Needs a look** opens the same panel on that album's folder.

The panel has five tabs - **Release**, **Tags**, **Artwork**, **Lyrics** and **Delete** - for someone
given Look after the library but not Edit albums, only **Delete**.

### Release: matching it to a release

**Release** opens already searching MusicBrainz using the album's artist and album tags - its search
box shows those words while it's blank (a blank box searches for exactly that album by that artist).
Above it, **Now:** says what the files claim to be: their edition (or *No edition*), year - *1999
(this pressing 2014)* for a reissue - track count, discs, and **Matched to MusicBrainz** or **Not
matched to MusicBrainz** (point at the first for the release id). You:

1. **Pick the release** the album really is from the list of pressings. The one the files
   already claim is marked **Current**. Each row shows year, format, country, catalogue number
   and track count; a track count in yellow doesn't match the files.
2. **Check the fields**: artist, album, year, original year, and edition. Blank fields are left
   alone rather than cleared. The edition is worked out from the release unless you type one.
3. **Read the preview**. It shows every tag that would change, file by file; whether the folder
   would move or be renamed (to follow the template, or the artist's current name); and, when
   the album is split across folders, whether it would merge.
4. **Cover art**: tick **Download cover art** to save the release's cover from the Cover Art
   Archive, and compare it with the one you have (**Compare full size…**) before replacing it.
5. **Apply** writes the tags, fetches the cover and moves the folder. There's no undo, which is
   why the preview shows everything first. When the apply changes both the album's tags and its
   folder, it writes the tags, pauses, then renames. That pause lets Navidrome see the new tags
   first and keep the album's plays, ratings and favourites, which it loses when both change at
   once. With Navidrome set up, deadwax asks it, and renames as soon as Navidrome has finished a
   scan that began after the tags were written, usually a few seconds; the button reads *Applying,
   waiting for Navidrome*. Without, it's a fixed pause (20 seconds by default,
   `RETAG_RENAME_WAIT`), and the button names it (*Applying, renaming in 20s*). The preview says
   which, up front. If Navidrome finishes no scan within 90 seconds, or can't be reached at all, the
   folder is left where it is and the editor says so. Apply the same release again once Navidrome
   has scanned: deadwax checks with Navidrome first and renames straight away if it has, or waits for
   a scan again if it hasn't. deadwax forgets a held-back rename when it restarts, and after that the
   next apply renames without asking
   ([troubleshooting](troubleshooting.md#applying-a-release-left-the-folder-where-it-was)).
   If a folder of the new name appears during the pause (another copy of the same release
   applied just before), the rename is refused and the album stays where it is, with its new
   tags.

   Navidrome can only say that a scan finished, not which folders it read. With one library
   that's enough, because a scan after a change is the one the change caused, or covers
   everything. With a second library in Navidrome, or an admin scanning some other folder at
   that moment, the rename can come before this album has been scanned.

**Cancel** closes the panel; nothing is written until **Apply**, which then says what it did (*Updated
the tags in 12 files, saved cover.jpg, moved the folder to match its tags.*), or what it couldn't. For
an album with issues, **It's fine as it is** marks it fine ([above](#what-needs-attention)) - the line
above the search then says **Marked fine:** and which - and **Ask about it again** takes that back.

![Needs a look with a stranger's rip of Portishead's Third, and the Edit album panel's Release tab on it: not matched to MusicBrainz, the folder's name not matching the tags, no original year, no cover - and Third's pressings on MusicBrainz, the first picked, with what applying it would change](../assets/images/editor.png)

### Tags: editing tags by hand

**Tags** lists the album's tracks with a box each to select it. Select some (on a desktop Shift selects
a run), then **Edit N tracks…**, or **Edit all tracks…** with none selected. You can edit title, artist,
album, album artist, track, disc, disc title, date, original date, genre and composer. A disc title is
the one to set for a box set or a bootleg whose discs MusicBrainz leaves untitled: select that
disc's tracks and type it once.

- A field whose value differs between the selected tracks starts empty and says **Several
  values**. Leave it alone and each track keeps its own.
- Only fields you change are written. Emptying a field you changed **removes** that tag.
- The preview shows each change before **Apply**. If anything is invalid (a track number that
  isn't a number), nothing is written at all.
- It edits tags only; no file or folder is renamed. **Release** is what moves an album's folder once
  its tags say it belongs somewhere else.
- A field that won't do is marked, and **Fix the marked field first.** says so; after **Apply**,
  *Saved 3 files.*

**Cancel**, **Close** or Escape goes back to the list.

A multi-disc set is split under **Disc 1**, **Disc 2** headings, on the album's page as in Tags. A
disc that has its own title says it too: **Disc 4 · Live at Wembley 1974**. The title is the
`DISCSUBTITLE` tag (Picard's name for it; Navidrome shows it as well). deadwax writes it when a
download or an applied release gives the disc a title, and you can set it by hand, as above.

### Inside a track

A track's **name** (not its box) in **Tags** opens it in the panel - the line above the list says so:

- **Tracks** at the top goes back to the list, where you left it - scrolled on just enough to show the
  track you were on, if **Previous** and **Next** took you past the ones in view; **2 of 11** says
  where the track is (a screen reader is told the track and where it is as it opens and at each step).
  Its title (with "No title tag - this is the file's name" for a file that has none), then where it
  sits - "Track 2", "disc 2 of 2 · <the disc's title>" for a set, "Unnumbered" for a file with no
  track number - its length and its format.
- **Previous** and **Next** step through the album's tracks in their order (by disc, then number),
  greyed at the first and the last. **Edit this track…** opens [the tag editor](#tags-editing-tags-by-hand)
  on that one file (from its top); closing it comes back here, as you left it, with **Edit this
  track…** in view.
- **Every field deadwax reads** - track and disc number, artist, genre, composer, label, catalogue
  number, ISRC, bitrate, sample rate, bit depth, channels, the MusicBrainz ids and more - under
  **Tags**, **Audio**, **MusicBrainz** and **File**, each with what the file says, or a dash for a
  field it doesn't carry. A field only the file carries shows `…` while the file is being read. A disc
  number shown faded is a default: the file has no disc tag, so it counts as disc 1 (point at it for
  why) - that's where it sorts, and how every player treats it.
- **Pictures in this file**: each picture embedded in it - its type (Front cover, Media (the disc
  itself)…), its size in pixels, its bytes and format. Click one to see it full size in [the cover
  viewer](#the-cover-viewer). This is where a song's odd sleeve comes from ([below](#why-a-song-can-show-a-different-picture)).
- **Lyrics**: the track's `.lrc`, else lyrics embedded in the file - synced lines with their times
  (and a gap between verses), marked **synced**, and where they came from. None, and it says so, with
  **Get lyrics** in the panel's **Lyrics** tab when some of the album's tracks have none.
- **All tags in this file (N)**: click it to see every tag in the file under its own name - including
  ones no field knows - and the file's name.

It reads the files as they are now and changes nothing. Escape while you're in the panel goes back
one step at a time: from the tag editor to the track, from the track to the list, then it closes the
panel; Escape in the cover viewer closes only the viewer.

![A track's synced lyrics inside the Edit panel, with the time beside each line](../assets/images/lyrics.png)

### Artwork: covers and CD art

**Artwork** shows the cover the album has and the CD art beside its tracks - as pictures, each with
its file name, opening in [the cover viewer](#the-cover-viewer) when you click them - with **Get
cover** and **Get CD art** where they can help. Each needs the album matched to a release, so an
untagged album is matched in **Release** first (*To get a cover, first match the album to a release in
the Release tab.*). While one works its button says so (*Getting the cover…*), and what came of it is
said in a line **under the button** - on a phone too, which shows no tooltips.

- **Get cover** fetches the cover of the release the album's tags name, from the Cover Art
  Archive, at `COVER_ART_SIZE`, and saves it as `cover.jpg` (or `.png`). It only appears on albums
  that have a release id and no cover, and it never replaces one. To replace a cover, use
  **Release**, where you can compare the two. *The Cover Art Archive has no front cover for that
  release.* and a failure (*The Cover Art Archive couldn't be reached - try again.*) are told apart,
  because only the second is worth trying again: the button reads **Look again** after the first and
  **Try again** after the second.
- **Get CD art** saves a picture of the disc itself, as `disc.jpg` (or `disc1.jpg`,
  `disc2.jpg`… per disc of a set), from the Cover Art Archive's scans of that exact release, and
  otherwise from fanart.tv if you've set a key. Navidrome shows it for the songs on that disc,
  and it's the face of the record on the player's [turntable](player.md#the-turntable). A `disc.*`
  file sits ahead of a download's `cd.jpg` in every player's order, so the scan stops being what
  shows without being deleted. It never replaces CD art that's already there. When neither has a
  picture of the disc the line under it says so (with, when you haven't set one, that a fanart.tv
  key in Server settings adds another source), and the button reads **Look again**.

#### Why a song can show a different picture

Some players (Navidrome, and so apps like Amperfy) show a picture *embedded in the file* over the
album's cover, and a disc scan (`cd.jpg`) for songs with a disc number. A track's **Pictures in this
file** lists the pictures inside it, so you can see which it is. If you'd rather songs always showed
the album's cover in Navidrome, that's two of *its* settings: `ND_ENABLEMEDIAFILECOVERART=false` and
`ND_DISCARTPRIORITY=cover.*, folder.*, front.*, embedded`.

### Lyrics

**Lyrics** says how many tracks have a `.lrc`, with **Get lyrics** for the rest: it looks up
lyrics on LRCLIB for the tracks that have none, and saves each as a `.lrc` beside its track, then
says how many it found on the button (**Lyrics · 9 of 10**) and the rest in the line under it
(*Saved lyrics for 9 tracks (all synced), 1 not on LRCLIB.*; a track that failed says *1 failed - try
again*, and pressing it again asks LRCLIB for those).
When synced lyrics appear (the lyrics lead), and re-timing the ones already saved, are under
**Lyrics** in **Server settings** (**Library**) - the tab says so ([Configuration](configuration.md#lyrics)).
How lyrics are matched and saved is in [organizing](organizing.md).

### Delete

**Delete** removes the album's folder and everything in it, **permanently**. The confirmation, read
as you open the tab, names the track count and size, and lists any files that aren't audio, in case
one is the only copy of a rip log. **Delete permanently** does it. It only ever deletes a folder that
holds audio directly, inside your library, and never the library folder itself. A deleted album
leaves **Needs a look** straight away. **Cancel** (or Escape) goes back to **Release** - or, for
someone whose panel has only **Delete**, closes it.

With logins on the confirmation also says **whose libraries it is in** - "In
ethan and sam's libraries: deleting it takes it out, and they'll see it was removed by an admin", or,
when it is in yours too, "In your library and ethan's: deleting it takes it out, and ethan will see it
was removed by an admin" - or that nobody has it. When deadwax can't read who has it (its database
unavailable) it says that instead, never "nobody". Each of the others then finds it in **You → Your
library** as **Removed by an admin.**, with **Get it again** (when they may Get albums) and **Dismiss**
([the app guide](player.md#your-library-with-logins-on)); it simply leaves yours, since you chose to
delete it.

### Which folder, and after an edit

**Which folder.** The album page knows the album by Navidrome's id; the editors work on a folder.
deadwax finds it by the album's MusicBrainz release, as the store index has it (the same lookup that
gives the album page its "Also: …" chips). An album Navidrome knows by **no** release - a rip that was
never tagged, exactly what the release editor is for - is found among the library's folders that
carry no release id either, by its name and artist (and its track count, when that still leaves
several); when more than one folder fits, the panel asks which (*2 folders have this album's name, and
none is matched to a release. Which one is it?*). A release kept one folder per disc
starts on the first folder, with a **Folder** choice above the tabs for the others - apply the
release to each, and they merge. When **no** folder is found - by release or by name - the panel says
so (*deadwax can't find this album's folder: …*), with **Look again** and **Choose the folder**: a list of every folder in the library's scan, each
with its artist and album tags (and "no release" for one with no release id), narrowed as you type -
every word you type has to be somewhere in the folder's path, artist or album, accents and capitals
aside; the first 50 are listed, and it says how many match. Click the one this album is, and the
panel edits it from then on, until the next **Edit**. The panel reads the library the first time you
press **Edit**, and again, behind what it shows, each time after - the app can be left open for hours,
and an album changed meanwhile on another device is shown as it is now.

**After an edit**, the album page asks Navidrome again at once and once more ten seconds later
(Navidrome notices a change about five seconds after it's made, then scans), and the app's marks of
what you hold are asked again. Applying a **different** release gives the album a new id in Navidrome:
the page follows it, in place, once Navidrome has scanned (it keeps looking for about 45 seconds,
whatever else you edit meanwhile), so it shows the album as it is now rather than one Navidrome no
longer has - and if you'd gone to another page meanwhile, going back to the album shows it under its
new id too. Deleting the album closes the panel and goes back from its page - unless it was one folder
of several, when the page stays and is asked again, at once and ten seconds later. The Library's grid
is Navidrome's, so it changes once Navidrome has scanned.

**The panel itself.** On a desktop it's a side panel like Sources and Info - a third column from 1280
pixels wide, lying over the right of the page below that - and one shows at a time: **Edit** puts
Sources and Info away, and either puts the Edit panel away. On a phone it's a sheet over the whole
screen, as Sources is there, and the page waits behind it. It closes when you go to another page;
widening or narrowing the window across 1024 pixels with it open turns the one into the other. The
close button, or Escape while you're in the panel (on a phone, any Escape), closes it - a tap on the
dimmed page beside the phone's sheet (a phone on its side, an iPad held upright) doesn't, so a stray
one can't throw away an edit you've half made; on a desktop, Escape out in the page (in the search
field, say) is the page's. Between 1024 and 1279 pixels wide, while it lies over the page, the album's
**Play**, **Shuffle** and **Edit** move under its cover, so **Edit** stays in view to close it.

## The cover viewer

Tap an album page's cover, on a phone or a desktop, to see it as Navidrome has it, unresized; and in
the Edit panel, **Artwork**'s cover and CD art and the pictures inside a track open in it. Click (or
tap) to zoom in on the point you touched, use the wheel to zoom, or pinch on a phone; drag to move
around; click again to fit. In **Release**, **Compare full size…** shows your cover and the release's
side by side, each zooming and moving on its own, with their real pixel sizes and the larger one
marked. Escape, **Close**, the ✕ or a click on the dimmed page round it closes it - and so does going
back (the browser's Back, a mouse's back button, a phone's back gesture), which goes back too.

## Needs a look

**Needs a look** - the desktop sidebar's first item under **Manage**, with how many albums need one
beside it, or **You → Manage → Needs a look** on a phone, with the same count - is the library's
review queue. The line at its top says what it's for: *Albums whose tags, folder or cover need fixing,
albums Navidrome doesn't list, and new downloads nobody has looked at yet. Open one to fix it, or to
mark it fine as it is.*

- **The albums, in order**: every album with an issue you haven't accepted, and every album deadwax
  filed that nobody has looked at yet - those first, then the worst first, then by artist and album.
  The count is that list's length: deadwax works it out from the library's saved scan, without
  reading the disk (an album filed since the last scan is counted too, as the list shows it once it
  has scanned).
- **Chips narrow it**: **All**, **Newly added** (when there is one), one for each kind of issue
  that has an album, with how many - and, last, **Marked fine**. The chip you press is in the page's
  address, so a reload keeps it; one whose last album gets fixed falls back to **All**.
- **A row** shows the album's cover, name, artist and edition, **New** for an album just filed, and
  its outstanding issues (hover one for what it means). The list is read the first time you open the
  page - the saved scan at once, then the disk, with *Checking the library…* meanwhile.

**Marked fine** is there only while an album has an issue marked fine with **It's fine as it is** and
nothing outstanding: those albums aren't in the queue any more, so this is where they're kept in
reach - a folder Navidrome doesn't list above all, which nothing else in the app can open. Each row
says **Marked fine**, quietly (point at it for which issues), and opens the Edit panel like any
other, where **Ask about it again** puts the album back in **All**. It's a view, not a count: **All**
and the count beside **Needs a look** go on counting what's outstanding and what's new.

**Not in Navidrome** is one of its chips ([above](#not-in-navidrome)): an album folder Navidrome doesn't
list, which the rest of the app can't reach - its row opens the **Edit album** panel like any other.
When no album can be checked against Navidrome, the line above the list (where *Checking the library…*
shows) says why once the disk has been read: *Navidrome isn't set up…* (with where to set it up:
Server settings (Connections)), *Couldn't ask Navidrome which albums it has…* (with Navidrome's own
words for whoever runs deadwax; anyone else is told to try again in a minute), *Navidrome was scanning when last
asked…*, or *Navidrome hasn't answered yet…* (it's asked again the next time the page reads the
library). It's kept to one line, so it never moves the rows; hover it for the whole of it.

**Marking fine needs the database.** When deadwax couldn't open its database (`DB_PATH`), the page
says so above the list: *deadwax can't save to its database (check DB_PATH), so an album you mark
"It's fine as it is" will come back.* See [Troubleshooting](troubleshooting.md#albums-marked-fine-come-back-to-needs-a-look).
A library that couldn't be read is said in a sentence too (*Couldn't read the library.*, with **Try
again**), with what went wrong under it for whoever runs deadwax.

**Click a row** and the **Edit album** panel opens on that album's folder, beside the list (on a phone,
as a sheet over it) - all five tabs ([above](#editing-an-album)), the row highlighted. **Release**
says where the album is in the queue (*3 of 17*), with **◁** (Previous album) and **Skip ▷**, and after **Apply** its
button becomes **Next album ▷**, so you can work through the queue without going back to the list -
or click another row. While the panel is open the list doesn't move: an album you fix, accept (**It's
fine as it is**) or delete stays where it was, faded, saying **Fixed**, **Marked fine** or **Deleted**
(after a delete the panel stays open, saying so, with **Next album ▷**). Moving on from an album -
Next, Previous, another row, closing the panel - counts as having looked at it, which is what clears
**New** (it keeps its issues). Closing the panel, choosing another chip or leaving the page ends the
run: the list is then read again and drawn as it is now. The chips hold still for the whole run too,
counts and all. Until that read has landed the rows stay as they were, faded, and a click on one does
nothing - click again once they are back to full strength.

An album page showing the same album elsewhere in the app isn't asked again after an edit made from
**Needs a look** - go back to it, or reload, to see the change.

## Library care

**Library care** - after **Needs a look** in the desktop sidebar's **Manage**, and in **You →
Manage** on a phone, where the page is laid out for it - says at its top what it's for (*Rescan the
library after changing tags in another program, and fill in missing covers, CD art and lyrics across
many albums at once - one album at a time, and Stop ends a run after the album it's on.*) and holds:

- **Rescan** - every file read again, ignoring the saved scan. Under it, what the library holds and
  how old the scan is (*7 albums · 87 tracks · 425 MB · Scanned 3 min ago in 2s*, or *Saved scan from
  2 h ago* while the saved copy is what's on screen). Press it after changing tags with another
  program: deadwax spots a changed album by its folder's date, which editing tags in place doesn't
  change.
- **Covers**, **CD art** and **Lyrics** - **Get covers · N**, **Get CD art · N** and **Get lyrics · N**:
  a cover for an album matched to a release with no cover, CD art for one matched to a release with no
  disc picture from deadwax yet (no `disc*` image - a download's `cd.jpg` doesn't count), lyrics for one
  with no lyrics at all. Each run asks for one album at a time, through the same step as that album's
  own **Get** button in the Edit panel, so you can watch it and stop it: while it runs its button is
  **Stop after this album · 3 of 12** (the third album is the one being fetched), and pressing it
  finishes that album and goes no further. When it ends it says what it did in sentences (*Got 10 covers. 1 has none in the Cover Art
  Archive. 1 failed - run it again to try it again.*; lyrics are counted in tracks, and a track that
  failed is tried again from its album's own **Get lyrics**), and that stays on the
  page until that run is started again - also when you go to another page, the **Event log** say, and come
  back. A run goes on while you're on another page of the app; reloading the app forgets what the
  last ones said. The three can run at once. When a run that saved something ends, the page reads the
  library again before it offers that run again - its line says *Checking the library…* for that
  moment - so its button never comes back over the albums it has just done.
- **Narrow to** - the runs act on the whole library, or on the album folders whose artist, album,
  edition or folder name hold every word you type there (*The runs act on 3 of 8 album folders: those
  matching "portishead"*). Before you start one, each says how many album folders it will take and
  what it writes - folders, as the line above counts them: an album you keep in two pressings is one
  album in the scan's count and two folders here.
- **In nobody's library** - with logins on, under the runs: the albums nobody has in their
  library (the first 20, then **Show all** - and **Show fewer**), and the flagged downloads with **Add for
  them** and **Dismiss** - see [who has an album](#who-has-an-album-with-logins-on).

The runs are offered once the library has been read from the disk - with the saved copy on screen
the page says *Checking the library…* first, since the saved copy can be behind.

## Artist pages

An artist's page ([the app guide](player.md#artist-pages)) has, under their albums, what your library
holds of them and who MusicBrainz says they are - their other names, when they began and ended, their
genres, their links (two of the same kind say where each one goes: **Official site ·
portishead.co.uk**, and **(archived)** for a page kept on the Wayback Machine) and their line-up. For
an admin (or someone given Edit albums, or Look after the library for the move) it has the
looking after too - [Managing an artist](player.md#managing-an-artist) has every step:

![Pink Floyd's artist page: what MusicBrainz says about them, and their albums from MusicBrainz, oldest first, with Get on the ones not in the library](../assets/images/artist.png)

**Artist images…** shows every picture found, from Wikimedia Commons, TheAudioDB (with a key)
and fanart.tv (with a key), and saves your choices into the artist's folder:

| saved as | is | read by |
| --- | --- | --- |
| `artist.*` | the square photo | Navidrome (no configuration needed), Jellyfin, Kodi |
| `banner.*`, `fanart.*`, `logo.*`, `landscape.*`, `clearart.*` | wide banners, backgrounds, logos | Jellyfin, Kodi, and the app's artist page (`fanart.*` and `logo.*`) |

The extension is the picture's own (`.jpg`, `.png`…). Any picture can go in any slot, and a
folder that holds tracks is refused, since an `artist.jpg` there would mean something else. The
square `artist.*` is the page's own picture, as Navidrome serves it; `fanart.*` fills the top of the
page and `logo.*` stands for the name, read from the folder by deadwax.

![Artist images for Pink Floyd: the pictures found for each slot, beside their page's In your library and About](../assets/images/artist-images.png)

**Which artist this is** comes from the files' MusicBrainz artist ids - the ones deadwax writes into
your files, which is how the page finds the artist's discography when Navidrome doesn't say who they
are. When the files have none, a name search is used, but only when exactly one artist has that name.
For a name several artists share (there are eight called Nirvana), **Which artist is this?** asks you
to choose. An album filed by another tool, without those ids, still shows on the page - just without
MusicBrainz's albums beside it.

**An artist who has renamed.** When MusicBrainz knows the artist by another name now, the page
says **Now: …**. If their albums are filed under a name that isn't theirs now, **Move albums to …**
moves them all under the current name, with a preview first - one page for every name the library
files the artist under, so Ye's page moves Donda out of `Kanye West/`. It rewrites the album-artist
tag, leaves each track's credited artist alone, and removes the old folder once it's empty. A Mac's
hidden `._` twin of a track (its resource fork, left beside every file copied from a Mac to a share)
isn't retagged - no tag can be written to it - and moves with its folder. Any other track deadwax
can't read - cut short, damaged, or not readable by the user deadwax runs as - keeps its album where
it is, and the preview says so ("'03 Three.flac' can't be read, so its tags can't be written"): moved,
it would still name the old artist, and Navidrome would show them as two artists again.

## Who has an album, with logins on

With logins on ([sharing deadwax](sharing.md)), every album in the collection is in the libraries of the people who
asked for it - their starred albums in Navidrome ([the app guide](player.md#your-library-with-logins-on)).
deadwax keeps that true as you look after the library:

- **Applying a release** keeps the album in everyone's library: an apply that renames the folder writes
  the tags first, waits for Navidrome's scan, and only then renames
  ([troubleshooting](troubleshooting.md#applying-a-release-pauses-before-the-folder-is-renamed)), so
  Navidrome's stars can follow the album - and afterwards deadwax stars it again for everyone who has it,
  whatever Navidrome did.
- **Merging a disc folder** into its album's folder puts the album in the library of everyone who had
  either.
- **Moving an artist's albums** under their current name changes only where they are: whoever had them
  still has them.
- **Deleting an album** takes it out of everyone's library, telling each of the others ([above](#delete)).
- **Library care → In nobody's library** (an admin's) lists every album in the collection that is in
  nobody's library - copied in by hand or by another program, or unstarred by everyone who had it - and
  the downloads **flagged** for you: ones whose every file was already in the folder they'd have been
  filed into, but that folder holds another pressing or an untagged rip, so deadwax gave the album to
  nobody on a guess. **Add for them** gives it to the people who asked after all; **Dismiss** leaves it.
  Either way their row in Requests says what you did.
