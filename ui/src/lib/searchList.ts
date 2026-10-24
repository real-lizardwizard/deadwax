/**
 * Search like Apple Music (2.0.0-player.55) - what the Search tab's one list is made of, pure: no fetch, no
 * playback, no DOM (app-rules.sim.cjs checks), pinned by ui/test/searchList.sim.cjs on real answers.
 *
 * James, 2026-10-15: "can we add something to the search so that it also searches songs and artists like apple
 * music?" - and of the looks offered, "Top results first (the best artist, album or song, yours or not, yours
 * marked), then Artists, Albums, Songs - each with yours first, then MusicBrainz's. Chips narrow it to one kind.
 * Keeps 'library first' inside every section."
 *
 *  - THE POOL (`pool`): everything in hand for a text, one thing shown once. The library's rows (Navidrome's
 *    search3 - yours, then with logins on the store's) and MusicBrainz's, deduped: a MusicBrainz artist the
 *    library has is the library's (`newArtists`, by id, else by name only when one MusicBrainz artist in the
 *    answer answers to it); a MusicBrainz song a library song of the answer already is (its title and credit)
 *    is dropped, one held with its album that search3 didn't list is BROUGHT in (`newSongs`); and an album the
 *    library holds that search3 didn't list (`heldUnlisted`) is brought in too - James's held-groups decision
 *    kept (notInLibrary's MusicBrainz block, as ever) and extended, so a held album never shows nowhere.
 *  - TOP RESULTS (`topResults`): one ranking across kinds - tier (deadwax's exactness test, `matchTier`:
 *    exact, by the box's artist, starts with, the rest), then source (yours, the store's, MusicBrainz's - a row
 *    BROUGHT in through MusicBrainz's answer ranks as MusicBrainz's, at its MusicBrainz position), then kind,
 *    then position - the best first, then what it belongs to (its album and artist, as Apple pulls them in),
 *    then round by round over the kinds. `decidedTop` is the part the library alone can settle: run with one
 *    PHANTOM per MusicBrainz kind still out, at least as good as anything that kind could bring, the picks
 *    before the first phantom are drawn at once and never move.
 *  - THE SECTIONS (`sectionRows`): yours, then the store's, then MusicBrainz's, each source capped on its own
 *    (`PREVIEW`), decided when drawn and never re-sorted - a whose that changes later changes only words.
 *  - THE MOMENTS (`sectionsReady`, `lateKinds`, `drawInOrFold`, `nextBehind`): every tappable thing drawn for a
 *    search keeps its place until you do something; a later answer lands only below everything tappable, or
 *    inside a place one fixed height already drawn for it. app/Search.tsx wires them; this file holds the
 *    rules, in one place.
 *  - WHAT'S SAVED (2.0.0-player.56, "search what's saved"): what MusicBrainz's saved answers hold matching the words
 *    (/search_musicbrainz/saved - in MusicBrainz's own shapes, so its rows are MusicBrainz's rows, marked `saved`)
 *    leads each kind's MusicBrainz rows, deduped against the library as MusicBrainz's are and MusicBrainz's own
 *    answer deduped against it by key (`pool`'s `saved` block); in Top results it ranks after yours and the
 *    store's and before MusicBrainz's answer (SOURCE.saved), so a song you came across on a saved album page is a
 *    Top result at the library's moment. Only for the kinds MusicBrainz is asked for, read as it is (`savedFor`).
 */

import type { ArtistMatch, ReleaseGroup } from '../api/types'
import type { Album, Artist, LibraryResults, Song as LibrarySong } from '../player/api'
import { matchLine } from './artistManage'
import { libraryArtistFor, mbidOf, soleCredit } from './artistPage'
import { heldReleases } from './idBridge'
import { foldName, ownedForGroup, type OwnedIndex } from './owned'
import { creditName } from './release'
import { NOISY_SECONDARY_TYPES, VARIOUS_ARTISTS, quoteTerm, typeFilter, withTypeFilter, type SearchPlan } from './searchQuery'
import { artistLine, groupHeld, groupKind, groupPlace, groupYear, notInLibrary } from './searchResults'
import {
  heldWords, namedAlbum, songAlbumHeld, songAlbumHolding, songAlbumWords, titleKey, type Song as FoundSong, type SongAlbum, type SongEvidence,
} from './songs'
import { anyYours, IN_THE_STORE, IN_YOUR_LIBRARY, libraryPlace, navidromeYours } from './whose'

/* ===== the constants ===== */

/** How many Top results: three plain rows on a phone (as iPhone shows them), six tiles three across on a desktop. */
export const TOP_RESULTS = { phone: 3, desktop: 6 } as const

/** How long the sections wait, after MusicBrainz is asked, for every kind asked - then a kind still out is late. */
export const RESULTS_WAIT_MS = 1500

/** How long the list waits for the library before it is drawn as if the library found nothing (with a place
 *  kept at its top for it). */
export const LIBRARY_LATE_MS = 1500

/** How many artists MusicBrainz is asked for a page - the route's own default (src/routes/search_musicbrainz.py
 *  ARTIST_SEARCH_LIMIT; tests/test_musicbrainz_routes.py holds the two to one number). */
export const ARTIST_SEARCH_LIMIT = 10

/** What a kind chip asks Navidrome's search3 for: that kind alone, a long page of it (inside the route's bounds:
 *  50 artists, 50 albums, 500 songs) - "More from your library" asks its next by offset. */
export const CHIP_LIBRARY_COUNTS = {
  artists: { artistCount: 50, albumCount: 0, songCount: 0 },
  albums: { artistCount: 0, albumCount: 50, songCount: 0 },
  songs: { artistCount: 0, albumCount: 0, songCount: 100 },
} as const

export type Kind = 'artists' | 'albums' | 'songs'
export type View = 'all' | Kind
export type Frame = 'phone' | 'desktop'

/** Apple's section order - and Top results' kind order. */
export const KINDS: readonly Kind[] = ['artists', 'albums', 'songs']

/** The All view's preview of each section: [the library's rows - yours and the store's together - MusicBrainz's
 *  rows], each capped on its own, so MusicBrainz's show even for an artist with many of yours. */
export const PREVIEW: Record<Frame, Record<Kind, readonly [number, number]>> = {
  phone: { artists: [2, 2], albums: [3, 3], songs: [3, 3] },
  desktop: { artists: [3, 3], albums: [4, 4], songs: [4, 4] },
}

/* ===== the rows ===== */

/** One row of the list - a section's, or a Top result. Its key is what keeps it in its place (and what the sims
 *  and the invariant check go by): a library row's Navidrome id, a MusicBrainz row's MusicBrainz id. */
export type Row =
  | { type: 'artist'; key: string; artist: Artist }
  //? `saved` (2.0.0-player.56): from what's saved, not MusicBrainz's answer to these words - the same row, marked
  | { type: 'mb-artist'; key: string; match: ArtistMatch; saved?: true }
  | { type: 'album'; key: string; album: Album }
  | { type: 'group'; key: string; group: ReleaseGroup; saved?: true }
  | { type: 'song'; key: string; song: LibrarySong }
  | { type: 'mb-song'; key: string; song: FoundSong; saved?: true }
  //? a MusicBrainz song's named album, pulled into Top results from the song's own fields (not a ReleaseGroup)
  | { type: 'song-album'; key: string; song: FoundSong; album: SongAlbum; saved?: true }

export const artistRow = (artist: Artist): Row => ({ type: 'artist', key: `artist:${artist.id}`, artist })
export const mbArtistRow = (match: ArtistMatch): Row => ({ type: 'mb-artist', key: `mb-artist:${match.mbid}`, match })
export const albumRow = (album: Album): Row => ({ type: 'album', key: `album:${album.id}`, album })
export const groupRow = (group: ReleaseGroup): Row => ({ type: 'group', key: `group:${group.id}`, group })
export const songRow = (song: LibrarySong): Row => ({ type: 'song', key: `song:${song.id}`, song })
export const mbSongRow = (song: FoundSong): Row => ({ type: 'mb-song', key: `mb-song:${song.key}`, song })
export const songAlbumRow = (song: FoundSong, album: SongAlbum): Row => ({ type: 'song-album', key: `group:${album.id}`, song, album })
/** A MusicBrainz row from what's saved (2.0.0-player.56): the very row MusicBrainz's answer would draw - the same key,
 *  so the two are never both drawn - marked as saved. */
export const savedRow = (row: Row): Row => (row.type === 'mb-artist' || row.type === 'group' || row.type === 'mb-song' || row.type === 'song-album' ? { ...row, saved: true } : row)

/** Which kind a row is. */
export function kindOf(row: Pick<Row, 'type'>): Kind {
  switch (row.type) {
    case 'artist':
    case 'mb-artist':
      return 'artists'
    case 'album':
    case 'group':
    case 'song-album':
      return 'albums'
    default:
      return 'songs'
  }
}

/** A MusicBrainz artist made from a credit (Top results' relatives): no disambiguation, type or country - its line is
 *  "Artist" alone. */
export function creditArtist(artist: { mbid: string; name: string }): ArtistMatch {
  return { mbid: artist.mbid, name: artist.name, disambiguation: '', country: '', type: '', matched_as: '' }
}

/* ===== whose: the marks (lib/whose.ts's rules) ===== */

/** What says whose a library row is, with logins on and a library of your own (`personal`). */
export interface Marks {
  personal: boolean
  /** /library/owned's answer */
  index: OwnedIndex | null
  /** your albums' Navidrome ids (yourAlbums()) - null until it has answered */
  yourAlbums: ReadonlySet<string> | null
  /** how many of your albums each artist has (yourArtists over yourAlbums()) - null until it has answered */
  yourArtists: ReadonlyMap<string, number> | null
  /** an album as search3 or the album's own answer has it, by id - its `starred` and release */
  albumOf?: (id: string) => Pick<Album, 'starred' | 'musicBrainzId'> | null
}

/** Whose a library album is: one among your albums' ids is yours, whatever search3's `starred` said (it was asked
 *  before an Add); else navidromeYours (starred, or held by a folder of yours); null while that can't be told. An
 *  album row made of a song's own fields (Top results' family) carries no star or release id: it is read as search3
 *  or `ready` has it, and is unknown when neither does - never "in the store" on a guess (review). */
export function albumYours(album: Pick<Album, 'id' | 'starred' | 'musicBrainzId'>, marks: Marks): boolean | null {
  if (!marks.personal) return true
  if (marks.yourAlbums?.has(album.id)) return true
  if (!album.starred && !album.musicBrainzId && marks.albumOf) {
    const known = marks.albumOf(album.id)
    return known ? navidromeYours(known, marks.index) : null
  }
  return navidromeYours(album, marks.index)
}

/** Whose a library song is: its ALBUM's whose - yours if its album is among your albums, else navidromeYours of the
 *  album as search3 or `ready` has it, else unknown. A song's own `starred` doesn't count. */
export function songYours(song: Pick<LibrarySong, 'albumId'>, marks: Marks): boolean | null {
  if (!marks.personal) return true
  if (!song.albumId) return null
  if (marks.yourAlbums?.has(song.albumId)) return true
  const album = marks.albumOf?.(song.albumId)
  return album ? navidromeYours(album, marks.index) : null
}

/** Whose a library artist is: yours when you have albums of theirs, the store's when you have none - unknown until
 *  your albums have answered. */
export function artistYours(artist: Pick<Artist, 'id'>, marks: Marks): boolean | null {
  if (!marks.personal) return true
  if (!marks.yourArtists) return null
  return (marks.yourArtists.get(artist.id) ?? 0) > 0
}

/** Whose a MusicBrainz group the store holds is: a folder of it yours. */
export function groupYours(group: Pick<ReleaseGroup, 'id'>, marks: Marks): boolean {
  if (!marks.personal) return true
  return anyYours(ownedForGroup(marks.index, { groupId: group.id }).held)
}

/** Whose a library row is (anything else: null). */
export function rowYours(row: Row, marks: Marks, evidence: SongEvidence = {}): boolean | null {
  switch (row.type) {
    case 'artist':
      return artistYours(row.artist, marks)
    case 'album':
      return albumYours(row.album, marks)
    case 'song':
      return songYours(row.song, marks)
    case 'group':
      return groupHeld(marks.index, row.group.id) ? groupYours(row.group, marks) : null
    case 'mb-song': {
      const held = namedAlbum(row.song, marks.index, evidence).held
      return held.length ? (!marks.personal || anyYours(held)) : null
    }
    case 'song-album': {
      //? a MusicBrainz song's named album, held: a tile's third line says so, as its row's place does (review)
      const held = songAlbumHeld(marks.index, row.album, row.song, evidence)
      return held.length ? (!marks.personal || anyYours(held)) : null
    }
    default:
      return null
  }
}

/** A library row's holder, for the order: yours, or the store's - and a whose not yet known is yours (isYours' rule:
 *  never "not yours" on a guess), never moved once it is known. */
const holder = (yours: boolean | null): 'yours' | 'store' => (yours === false ? 'store' : 'yours')

/* ===== one thing, shown once ===== */

/** A row in its place in the pool: whose block it is in, and its index in its own answer - `saved` when that answer is
 *  what's saved (2.0.0-player.56). */
export interface Placed {
  row: Row
  holder: 'yours' | 'store'
  position: number
  saved?: boolean
}

/** One kind's rows in hand: the library's (search3, in its order), those brought in through MusicBrainz's answer or
 *  what's saved (held, but not listed by search3), what's saved (2.0.0-player.56) and MusicBrainz's own. */
export interface KindPool {
  library: Placed[]
  brought: Placed[]
  saved: Placed[]
  musicbrainz: Placed[]
}

/* ===== what's saved (2.0.0-player.56) ===== */

/** How long the library's moment waits for what's saved, from when it was asked - it answers in milliseconds; past
 *  this it is given up for the words (a slow index degrades to MusicBrainz alone), so nothing waits on it. */
export const SAVED_WAIT_MS = 400

/** Top results' sources, best first: yours, the store's, what's saved, MusicBrainz's answer. What's saved ranks before
 *  MusicBrainz's answer because it is in hand at the library's moment - MusicBrainz's phantoms (source 2) can never
 *  outrank it, so a saved row can be decided early and never moves - and it is what you have come across before. */
export const SOURCE = { yours: 0, store: 1, saved: 1.5, musicbrainz: 2 } as const

/** What's saved for some words, as Search keeps it: artists as /artists answers them, release groups, the groups
 *  credited to exactly the words (`credited`, in studio order - the artist reading's, chosen from all theirs saved),
 *  songs (groupSongs of its recordings). */
export interface SavedFound {
  matches: readonly ArtistMatch[]
  groups: readonly ReleaseGroup[]
  credited?: readonly ReleaseGroup[]
  songs: readonly FoundSong[]
}

/** ...and as a view draws it (savedFor): the block `shown` worked out from the library's index as it is drawn. */
export interface SavedAnswer {
  matches: readonly ArtistMatch[]
  groups: readonly ReleaseGroup[]
  shown: readonly ReleaseGroup[]
  songs: readonly FoundSong[]
}

/** How many of an artist's saved albums the artist reading draws at most: MusicBrainz's page (MUSICBRAINZ_LIMIT). */
export const SAVED_ARTIST_ALBUMS = 12

/** A studio album or EP, as the studio clause reads one: an Album or EP with none of the noisy secondary types. */
export function studioGroup(group: ReleaseGroup): boolean {
  const primary = (group['primary-type'] ?? '').toLowerCase()
  const noisy = new Set(NOISY_SECONDARY_TYPES.map((type) => type.toLowerCase()))
  return (primary === 'album' || primary === 'ep') && !(group['secondary-types'] ?? []).some((type) => noisy.has(String(type).toLowerCase()))
}

/**
 * What's saved that a view draws for words read this way: only the kinds MusicBrainz is asked for (`kinds` - the
 * artist reading asks no songs, album-by-artist no artists: the saved ones of those aren't drawn either), and under
 * the ARTIST reading only albums credited to that artist - from `credited`, all of theirs that are saved, not the
 * albums the words found (which titles naming them fill first: the review's catch) - the studio ones when
 * MusicBrainz is asked the studio clause (`studio`), as the line under them says, read in the studio order an
 * artist's albums are (studioOrder), SAVED_ARTIST_ALBUMS of them.
 *
 * `shown` (what isn't held) is worked out from `index` as it is drawn - none until the library's index is in hand
 * (the review's catch: worked out as the answer landed, before /library/owned had, an album you have was drawn twice -
 * yours, and the saved one among MusicBrainz's). What's saved answers in milliseconds, so it never waits for the index
 * (a first /library/owned can walk a sleeping array); its albums are drawn once the index is in, MusicBrainz's below.
 */
export function savedFor(reading: Reading, saved: SavedFound | null, kinds: readonly Kind[], studio: boolean, index: OwnedIndex | null): SavedAnswer | null {
  if (!saved) return null
  const artist = reading.kind === 'artist' ? foldName(reading.artist) : ''
  const keep = (group: ReleaseGroup) => (!artist || foldName(creditName(group['artist-credit'])) === artist) && (!studio || studioGroup(group))
  const albums = kinds.includes('albums')
  const groups = !albums ? [] : artist ? studioOrder((saved.credited ?? saved.groups).filter(keep)).slice(0, SAVED_ARTIST_ALBUMS) : saved.groups.filter(keep)
  return {
    matches: kinds.includes('artists') ? saved.matches : [],
    groups,
    shown: index ? notInLibrary(groups, index) : [],
    songs: kinds.includes('songs') ? saved.songs : [],
  }
}

/**
 * A kind view's rows below its library's (2.0.0-player.56, after review): what's saved, then MusicBrainz's answer -
 * and once drawn, each row kept in its place, and as what it was drawn as. The All view's list is frozen as it is
 * drawn; a kind view is drawn from what is in hand at every render, so without this a saved answer landing after
 * MusicBrainz's rows (asked again on a chip's tap, say) went ABOVE them, taking MusicBrainz's copies of the same
 * things away - rows moving under a finger, and changing their lines.
 *
 * `before`: what the view drew for these words last (null: nothing yet); `saved` and `musicbrainz`: its rows now, in
 * their order (MusicBrainz's may hold what's saved holds - one key is drawn once); `above`: the keys drawn above them
 * (the library's); `problem`: MusicBrainz's failure (its words and Try again) is drawn now, below the lead. What's
 * saved leads (`lead`) while nothing of MusicBrainz's - its rows, or its failure - has been drawn below it; anything
 * new after that goes at the foot (`rest`, drawn below the failure too) - so what lands late never moves what was
 * drawn, a Try again under the finger included (second review).
 */
export interface KindArea {
  lead: readonly string[]
  rest: readonly string[]
  /** what each key was drawn as: what's saved, or MusicBrainz's answer */
  from: Readonly<Record<string, 'saved' | 'musicbrainz'>>
  /** MusicBrainz's failure has been drawn below the lead for these words (it stays so: once drawn, below is taken) */
  problem: boolean
}

export function kindArea(
  before: KindArea | null, saved: readonly Row[], musicbrainz: readonly Row[], above: ReadonlySet<string>, problem = false,
): { lead: Row[]; rest: Row[]; area: KindArea } {
  const savedBy = new Map(saved.filter((row) => !above.has(row.key)).map((row) => [row.key, row]))
  const answerBy = new Map(musicbrainz.filter((row) => !above.has(row.key)).map((row) => [row.key, row]))
  const from: Record<string, 'saved' | 'musicbrainz'> = {}
  const placed = new Set<string>()
  const lead: Row[] = []
  const rest: Row[] = []
  const put = (into: Row[], row: Row | undefined, source: 'saved' | 'musicbrainz') => {
    if (!row || placed.has(row.key)) return
    into.push(row)
    placed.add(row.key)
    from[row.key] = source
  }
  //? what was drawn, where it was, as what it was (else as what still holds it)
  const again = (into: Row[], key: string) => {
    const was = before?.from[key] === 'musicbrainz' ? 'musicbrainz' : 'saved'
    const same = was === 'musicbrainz' ? answerBy : savedBy
    if (same.has(key)) put(into, same.get(key), was)
    else if (was === 'musicbrainz') put(into, savedBy.get(key), 'saved')
    else put(into, answerBy.get(key), 'musicbrainz')
  }
  for (const key of before?.lead ?? []) again(lead, key)
  for (const key of before?.rest ?? []) again(rest, key)
  //? what is new: what's saved leads only while nothing is drawn below it; then everything new at the foot
  const below = !!before?.rest.length || !!before?.problem
  for (const row of savedBy.values()) put(below ? rest : lead, row, 'saved')
  for (const row of answerBy.values()) put(rest, row, 'musicbrainz')
  return { lead, rest, area: { lead: lead.map((row) => row.key), rest: rest.map((row) => row.key), from, problem: problem || !!before?.problem } }
}

/** How many of a drawn section's rows are the library's (and brought in) and how many MusicBrainz's (what's saved
 *  among them) - what its late kind's rows are capped by. */
export function drawnCounts(kind: KindPool, rows: readonly Row[]): [number, number] {
  const library = new Set([...kind.library, ...kind.brought].map((each) => each.row.key))
  const fromLibrary = rows.filter((row) => library.has(row.key)).length
  return [fromLibrary, rows.length - fromLibrary]
}

/** How many MusicBrainz artists in an answer answer to a name - by their name, or the name they were matched as. */
function answering(matches: readonly ArtistMatch[], name: string | null | undefined): number {
  const wanted = foldName(name)
  if (!wanted) return 0
  return matches.filter((match) => foldName(match.name) === wanted || (!!match.matched_as && foldName(match.matched_as) === wanted)).length
}

/**
 * MusicBrainz's artists less the library's (2.0.0-player.55): one is the library's when libraryArtistFor finds them
 * in `known` (the full getArtists list, else search3's artists) - by id; by the name the owned folders with that id
 * are filed under; by MusicBrainz's name for a Navidrome artist with no id. The NAME steps are believed only when
 * exactly one MusicBrainz artist in the answer answers to that name - two "Nirvana"s stay two rows, each with its
 * disambiguation (libraryArtistFor checks uniqueness only on Navidrome's side). A matched row is dropped: the
 * library's artist shows instead, BROUGHT in when search3 didn't list them. That is how "kanye west" shows your Kanye
 * West and no "Ye".
 */
export function newArtists(
  matches: readonly ArtistMatch[], known: readonly Artist[], index: OwnedIndex | null, listed: readonly Artist[],
): { musicbrainz: { match: ArtistMatch; position: number }[]; brought: { artist: Artist; position: number }[] } {
  const musicbrainz: { match: ArtistMatch; position: number }[] = []
  const brought: { artist: Artist; position: number }[] = []
  const listedIds = new Set(listed.map((artist) => artist.id))
  matches.forEach((match, position) => {
    const found = libraryArtistFor(known, match.mbid, index, match.name)
    const byId = !!found && mbidOf(found.musicBrainzId) === mbidOf(match.mbid)
    const believed = found && (byId || answering(matches, found.name) === 1)
    if (!found || !believed) {
      musicbrainz.push({ match, position })
      return
    }
    if (!listedIds.has(found.id) && !brought.some((each) => each.artist.id === found.id)) brought.push({ artist: found, position })
  })
  return { musicbrainz, brought }
}

/**
 * MusicBrainz's songs less the library's: one is dropped when a library song of the answer is it - its title
 * (titleKey; step 7 already merges live and remaster takes) and its credit (foldName); one held with an album it is on
 * (songAlbumHeld on any of them) that search3 didn't list is BROUGHT in, marked as step 7 marks it. No match by
 * recording id: deadwax never writes one, so it would only work for Picard rips.
 */
export function newSongs(
  found: readonly FoundSong[], library: readonly LibrarySong[], index: OwnedIndex | null, evidence: SongEvidence = {},
): { musicbrainz: { song: FoundSong; position: number }[]; brought: { song: FoundSong; position: number; yours: boolean }[] } {
  const heard = new Set(library.map((song) => `${titleKey(song.title)}\n${foldName(song.artist)}`))
  const musicbrainz: { song: FoundSong; position: number }[] = []
  const brought: { song: FoundSong; position: number; yours: boolean }[] = []
  found.forEach((song, position) => {
    if (heard.has(`${titleKey(song.title)}\n${foldName(song.credit)}`)) return
    const held = song.albums.flatMap((album) => songAlbumHeld(index, album, song, evidence))
    if (held.length) brought.push({ song, position, yours: anyYours(held) })
    else musicbrainz.push({ song, position })
  })
  return { musicbrainz, brought }
}

/**
 * The groups notInLibrary left out (held by group) whose album is NOT among the library's rows of this answer - no
 * library album's release is one the library holds of the group. Search3 lists eight albums and matches words its own
 * way, so in one list the letter of the old rule could hide an album from both halves; these are brought in instead,
 * at the end of their holder's block, marked, with no Get, opening the album you have. (For James to confirm.)
 */
export function heldUnlisted(groups: readonly ReleaseGroup[], index: OwnedIndex | null, libraryAlbums: readonly Pick<Album, 'musicBrainzId'>[]): ReleaseGroup[] {
  if (!index) return []
  const shown = new Set(notInLibrary(groups, index).map((group) => group.id))
  const listed = new Set(libraryAlbums.map((album) => (album.musicBrainzId ?? '').trim().toLowerCase()).filter(Boolean))
  return groups.filter((group) => !shown.has(group.id) && !heldReleases(index, group.id).some((release) => listed.has(release)))
}

/** The artist the box named, under the album-by-artist reading - by foldName, believed only when exactly one artist
 *  of `artists` answers to the name. */
export function namedArtist(reading: Reading, artists: readonly Artist[] | null | undefined): Artist | null {
  if (reading.kind !== 'album-by-artist' || !reading.artist) return null
  const wanted = foldName(reading.artist)
  const found = (artists ?? []).filter((artist) => foldName(artist.name) === wanted)
  return found.length === 1 ? found[0]! : null
}

/** The library's artists a MusicBrainz artist is looked for among: the full getArtists list when it has answered,
 *  with search3's own artists beside it (an artist search3 just found is in the library, whatever an older list
 *  said) - each once. */
export function knownArtists(list: readonly Artist[] | null | undefined, listed: readonly Artist[]): Artist[] {
  const known = new Map<string, Artist>()
  for (const artist of [...(list ?? []), ...listed]) if (!known.has(artist.id)) known.set(artist.id, artist)
  return [...known.values()]
}

/** How the box read, for ranking - SearchPlan's kind, artist and title. */
export type Reading = Pick<SearchPlan, 'kind' | 'artist' | 'title'>

/** Everything in hand for a text, as `pool` takes it. A kind not in hand is null. */
export interface PoolInput {
  reading: Reading
  /** All's search3 (or a kind chip's: only its kind is read) */
  library: LibraryResults | null
  /** the full getArtists list, once it has answered (libraryArtists()) */
  artistList: readonly Artist[] | null
  index: OwnedIndex | null
  marks: Marks
  evidence?: SongEvidence
  artists: readonly ArtistMatch[] | null
  /** MusicBrainz's groups, and the block shown (notInLibrary, as drawn) */
  albums: { groups: readonly ReleaseGroup[]; shown: readonly ReleaseGroup[] } | null
  songs: readonly FoundSong[] | null
  /** (2.0.0-player.56) what's saved for these words, as this view draws it (savedFor) - null when none */
  saved?: SavedAnswer | null
}

/** Everything in hand, each thing once, in its block (`newArtists`, `heldUnlisted`, `newSongs`). */
export function pool(input: PoolInput): Record<Kind, KindPool> {
  const { reading, library, index, marks, evidence = {} } = input
  const listedArtists = library?.artists ?? []
  const known = knownArtists(input.artistList, listedArtists)
  const named = namedArtist(reading, known)
  const artistsLibrary: Placed[] = []
  if (named && !listedArtists.some((artist) => artist.id === named.id)) {
    artistsLibrary.push({ row: artistRow(named), holder: holder(artistYours(named, marks)), position: -1 })
  }
  listedArtists.forEach((artist, position) => artistsLibrary.push({ row: artistRow(artist), holder: holder(artistYours(artist, marks)), position }))
  const saved = input.saved ?? null
  const artists: KindPool = { library: artistsLibrary, brought: [], saved: [], musicbrainz: [] }
  //? (2.0.0-player.56) what's saved first, then MusicBrainz's answer less what's saved (by MusicBrainz id) - read as ONE
  //? list by newArtists, so a library artist is brought in once, and "answers to that name" counts both
  const savedMatches = saved?.matches ?? []
  if (savedMatches.length || input.artists) {
    const savedIds = new Set(savedMatches.map((match) => match.mbid))
    const live = (input.artists ?? []).filter((match) => !savedIds.has(match.mbid))
    const listed = named ? [...listedArtists, named] : listedArtists
    const split = newArtists([...savedMatches, ...live], known, index, listed)
    const fromSaved = (position: number) => position < savedMatches.length
    const at = (position: number) => (fromSaved(position) ? position : (input.artists ?? []).indexOf(live[position - savedMatches.length]!))
    for (const { match, position } of split.musicbrainz) {
      const row = mbArtistRow(match)
      if (fromSaved(position)) artists.saved.push({ row: savedRow(row), holder: 'yours', position, saved: true })
      else artists.musicbrainz.push({ row, holder: 'yours', position: at(position) })
    }
    artists.brought = split.brought.map(({ artist, position }) => ({
      row: artistRow(artist), holder: holder(artistYours(artist, marks)), position: at(position), ...(fromSaved(position) ? { saved: true } : {}),
    }))
  }

  const libraryAlbums = library?.albums ?? []
  const albums: KindPool = {
    library: libraryAlbums.map((album, position) => ({ row: albumRow(album), holder: holder(albumYours(album, marks)), position })),
    brought: [],
    saved: [],
    musicbrainz: [],
  }
  const savedGroups = saved?.groups ?? []
  const savedGroupIds = new Set(savedGroups.map((group) => group.id))
  if (savedGroups.length) {
    const at = new Map(savedGroups.map((group, position) => [group.id, position]))
    albums.saved = (saved?.shown ?? []).map((group) => ({ row: savedRow(groupRow(group)), holder: 'yours', position: at.get(group.id) ?? 0, saved: true }))
    const shown = new Set((saved?.shown ?? []).map((group) => group.id))
    albums.brought = heldUnlisted(savedGroups, index, libraryAlbums)
      .filter((group) => !shown.has(group.id))
      .map((group) => ({ row: groupRow(group), holder: holder(groupYours(group, marks)), position: at.get(group.id) ?? 0, saved: true }))
  }
  if (input.albums) {
    const groups = input.albums.groups.filter((group) => !savedGroupIds.has(group.id))
    const at = new Map(input.albums.groups.map((group, position) => [group.id, position]))
    albums.musicbrainz = input.albums.shown.filter((group) => !savedGroupIds.has(group.id))
      .map((group) => ({ row: groupRow(group), holder: 'yours', position: at.get(group.id) ?? 0 }))
    //? MusicBrainz's block is the one worked out as its answer landed (`shown`); a group found held only since stays
    //? in it, marked in place - never brought in as well, which drew it twice (review)
    const shown = new Set(input.albums.shown.map((group) => group.id))
    albums.brought.push(...heldUnlisted(groups, index, libraryAlbums)
      .filter((group) => !shown.has(group.id))
      .map((group) => ({ row: groupRow(group), holder: holder(groupYours(group, marks)), position: at.get(group.id) ?? 0 })))
  }

  const librarySongs = library?.songs ?? []
  const songs: KindPool = {
    library: librarySongs.map((song, position) => ({ row: songRow(song), holder: holder(songYours(song, marks)), position })),
    brought: [],
    saved: [],
    musicbrainz: [],
  }
  const savedSongs = saved?.songs ?? []
  const savedKeys = new Set(savedSongs.map((song) => song.key))
  if (savedSongs.length) {
    const split = newSongs(savedSongs, librarySongs, index, evidence)
    songs.saved = split.musicbrainz.map(({ song, position }) => ({ row: savedRow(mbSongRow(song)), holder: 'yours', position, saved: true }))
    songs.brought = split.brought.map(({ song, position, yours }) => ({ row: mbSongRow(song), holder: marks.personal && !yours ? 'store' : 'yours', position, saved: true }))
  }
  if (input.songs) {
    const live = input.songs.filter((song) => !savedKeys.has(song.key))
    const position = new Map(input.songs.map((song, at) => [song.key, at]))
    const split = newSongs(live, librarySongs, index, evidence)
    songs.musicbrainz = split.musicbrainz.map(({ song }) => ({ row: mbSongRow(song), holder: 'yours', position: position.get(song.key) ?? 0 }))
    songs.brought.push(...split.brought.map(({ song, yours }) => ({ row: mbSongRow(song), holder: (marks.personal && !yours ? 'store' : 'yours') as Placed['holder'], position: position.get(song.key) ?? 0 })))
  }
  return { artists, albums, songs }
}

/* ===== the sections ===== */

/**
 * A section's rows, in the order they are drawn and kept: yours (the library's, then what MusicBrainz brought in that
 * you hold), then - logins on - the store's (the same two), then MusicBrainz's in its order. `cap`: the All view's
 * preview, [the library's rows, MusicBrainz's], each on its own; none for everything.
 */
export function sectionRows(kind: KindPool, cap: readonly [number, number] | null = null): Row[] {
  const ofHolder = (who: 'yours' | 'store') => [...kind.library, ...kind.brought].filter((each) => each.holder === who)
  const library = [...ofHolder('yours'), ...ofHolder('store')].map((each) => each.row)
  //? (2.0.0-player.56) what's saved leads MusicBrainz's rows, the preview's cap for MusicBrainz's taking both
  const musicbrainz = [...kind.saved, ...kind.musicbrainz].map((each) => each.row)
  return cap ? [...library.slice(0, cap[0]), ...musicbrainz.slice(0, cap[1])] : [...library, ...musicbrainz]
}

/** The rows a late kind brings to its slot: held ones first, then MusicBrainz's - never in the yours block above it,
 *  which would move the rows under it. `drawn`: the keys already drawn in its section, left out (2.0.0-player.56:
 *  what's saved is drawn before MusicBrainz answers, and MusicBrainz's answer adds only what isn't there). */
export function lateRows(kind: KindPool, cap: readonly [number, number] | null = null, drawn: ReadonlySet<string> = new Set()): Row[] {
  const fresh = (each: Placed) => !drawn.has(each.row.key)
  const brought = [...kind.brought.filter((each) => each.holder === 'yours'), ...kind.brought.filter((each) => each.holder === 'store')].filter(fresh).map((each) => each.row)
  const musicbrainz = [...kind.saved, ...kind.musicbrainz].filter(fresh).map((each) => each.row)
  return cap ? [...brought.slice(0, cap[0]), ...musicbrainz.slice(0, cap[1])] : [...brought, ...musicbrainz]
}

/** The All view's preview counts for a frame. */
export function previewRows(frame: Frame): Record<Kind, readonly [number, number]> {
  return PREVIEW[frame]
}

/* ===== Top results ===== */

/** The best tier each MusicBrainz kind can reach under a reading - null where it isn't asked. */
export function bestTier(reading: Reading, kind: Kind): number | null {
  if (reading.kind === 'artist') return kind === 'artists' ? 0 : kind === 'albums' ? 1 : null
  if (reading.kind === 'album-by-artist') return kind === 'artists' ? null : 0
  return 0
}

/** A row's name or title, and whom it is credited to - what its tier is read from. */
function facts(row: Row): { name: string; credit: string } {
  switch (row.type) {
    case 'artist':
      return { name: row.artist.name, credit: row.artist.name }
    case 'mb-artist':
      return { name: row.match.name, credit: row.match.name }
    case 'album':
      return { name: row.album.name, credit: row.album.artist ?? '' }
    case 'group':
      return { name: row.group.title ?? '', credit: creditName(row.group['artist-credit']) }
    case 'song':
      return { name: row.song.title, credit: row.song.artist ?? '' }
    case 'mb-song':
      return { name: row.song.title, credit: row.song.credit }
    case 'song-album':
      return { name: row.album.title, credit: row.album.credit }
  }
}

/**
 * Deadwax's exactness test - Top results' tier (MusicBrainz has no popularity, and its scores tie at 100 across
 * strangers): 0 exact - an artist whose name folds to the box (foldName: accents, case, brackets, a leading "the";
 * a MusicBrainz artist also when its name-or-alias match says so, `matched_as`), an album or song whose title does
 * (a song's by titleKey), and under the album-by-artist reading one titled as read and credited to the artist read;
 * 1 by the box's artist - under the artist or album-by-artist reading, a row credited to that artist (and under
 * album-by-artist, the artist themselves); 2 starts with - the box has three characters or more and the name or
 * title starts with it (Navidrome matches prefixes); 3 the rest. Under the ARTIST reading titles never count as
 * exact: typing "portishead" means them, and the self-titled album is a coincidence.
 */
export function matchTier(row: Row, box: string, reading: Reading): number {
  const typed = foldName(box)
  const { name, credit } = facts(row)
  const kind = kindOf(row)
  const fold = kind === 'songs' ? titleKey : foldName
  const own = fold(name)
  const artist = foldName(reading.artist)
  if (kind === 'artists') {
    const matched = row.type === 'mb-artist' && !!row.match.matched_as
    if (reading.kind === 'album-by-artist' && artist && foldName(name) === artist) return 1
    if (foldName(name) === typed || (matched && reading.kind !== 'album-by-artist')) return 0
  } else if (reading.kind === 'album-by-artist') {
    if (own && own === fold(reading.title) && foldName(credit) === artist) return 0
    if (artist && foldName(credit) === artist) return 1
  } else if (reading.kind === 'artist') {
    if (artist && foldName(credit) === artist) return 1
  } else if (own && own === fold(box)) {
    return 0
  }
  if (typed.length >= 3 && own.startsWith(kind === 'songs' ? titleKey(box) : typed)) return 2
  return 3
}

/** One thing Top results may pick: its row, and the keys it is compared by. A phantom stands for a MusicBrainz kind
 *  still out. */
export interface Candidate {
  row: Row | null
  key: string
  kind: Kind
  tier: number
  /** 0 yours, 1 in the store and not yours, 2 MusicBrainz's */
  source: number
  position: number
  phantom: boolean
}

const KIND_RANK: Record<Kind, number> = { artists: 0, albums: 1, songs: 2 }

/** The order candidates are compared in: tier, source, kind, position. */
export function rank(a: Candidate, b: Candidate): number {
  return a.tier - b.tier || a.source - b.source || KIND_RANK[a.kind] - KIND_RANK[b.kind] || a.position - b.position
}

/** Top results' candidates from the pool: the library's (yours 0, the store's 1, by the whose known now), what's
 *  saved and what it brought in (1.5 - SOURCE.saved), and MusicBrainz's AND what MusicBrainz brought in (2, at their
 *  MusicBrainz positions) - so a decision taken before MusicBrainz answered stays sound. */
export function candidatesOf(rows: Record<Kind, KindPool>, box: string, reading: Reading): Candidate[] {
  const out: Candidate[] = []
  for (const kind of KINDS) {
    const add = (placed: Placed, source: number) => out.push({
      row: placed.row, key: placed.row.key, kind, tier: matchTier(placed.row, box, reading), source, position: placed.position, phantom: false,
    })
    for (const placed of rows[kind].library) add(placed, placed.holder === 'store' ? SOURCE.store : SOURCE.yours)
    for (const placed of rows[kind].brought) add(placed, placed.saved ? SOURCE.saved : SOURCE.musicbrainz)
    for (const placed of rows[kind].saved) add(placed, SOURCE.saved)
    for (const placed of rows[kind].musicbrainz) add(placed, SOURCE.musicbrainz)
  }
  return out
}

/** A MusicBrainz kind still out, as Top results' phantom: the best tier its kind can reach under the reading,
 *  MusicBrainz's source, before every position - at least as good as anything that kind could bring. */
export function phantom(kind: Kind, reading: Reading): Candidate | null {
  const tier = bestTier(reading, kind)
  return tier === null ? null : { row: null, key: `phantom:${kind}`, kind, tier, source: SOURCE.musicbrainz, position: -Infinity, phantom: true }
}

/** What Top results' family is built from - every relative from the best's own fields, nothing asked. */
export interface Family {
  library: LibraryResults | null
  artistList: readonly Artist[] | null
  index: OwnedIndex | null
  evidence?: SongEvidence
  /** MusicBrainz's albums answer: a song's named album is that answer's own group when it holds the same id */
  groups: readonly ReleaseGroup[]
  /** (2.0.0-player.56) which of those groups are from what's saved - a relative made of one is marked so */
  saved?: ReadonlySet<string>
}

/** A MusicBrainz artist credited somewhere, as a row: the library's artist when the library knows them (over the full
 *  getArtists list), else MusicBrainz's. */
function creditedRow(artist: { mbid: string; name: string }, family: Family): Row {
  const library = family.artistList ? libraryArtistFor(family.artistList, artist.mbid, family.index, artist.name) : null
  return library ? artistRow(library) : mbArtistRow(creditArtist(artist))
}

/** A library artist by id, for a relative: search3's row, else getArtists', else one made of the name - drawn with the
 *  round placeholder. */
function libraryArtist(id: string | undefined, name: string | undefined, family: Family): Row | null {
  if (!id) return null
  const found = family.library?.artists.find((artist) => artist.id === id) ?? family.artistList?.find((artist) => artist.id === id)
  return artistRow(found ?? { id, name: name ?? '' })
}

/**
 * What the best match belongs to, as Apple pulls it in ("glory box": the song, then Portishead, then Dummy): a library
 * song's album (search3's row when it has one, else made of the song's own fields) then its artist; a library album's
 * artist; a MusicBrainz song's named album (the albums answer's group when it holds it, else made of the song's own
 * album - not a ReleaseGroup) then its sole credited artist; a MusicBrainz album's sole credited artist.
 */
export function familyOf(row: Row, family: Family): Row[] {
  switch (row.type) {
    case 'song': {
      const song = row.song
      const out: Row[] = []
      if (song.albumId) {
        const album = family.library?.albums.find((each) => each.id === song.albumId)
        out.push(albumRow(album ?? {
          id: song.albumId, name: song.album ?? '', ...(song.artist ? { artist: song.artist } : {}), ...(song.coverArt ? { coverArt: song.coverArt } : {}),
        }))
      }
      const artist = libraryArtist(song.artistId, song.artist, family)
      if (artist) out.push(artist)
      return out
    }
    case 'album': {
      const artist = libraryArtist(row.album.artistId, row.album.artist, family)
      return artist ? [artist] : []
    }
    case 'mb-song': {
      const named = namedAlbum(row.song, family.index, family.evidence).album
      const group = family.groups.find((each) => each.id === named.id)
      //? (2.0.0-player.56) a relative made of what's saved - a saved song's own album, a saved group - is marked saved
      const kept = (relative: Row) => (row.saved || (relative.type === 'group' && family.saved?.has(relative.group.id)) ? savedRow(relative) : relative)
      const out: Row[] = [kept(group ? groupRow(group) : songAlbumRow(row.song, named))]
      const sole = row.song.artists.length === 1 ? row.song.artists[0]! : null
      if (sole && mbidOf(sole.id)) out.push((row.saved ? savedRow : (each: Row) => each)(creditedRow({ mbid: mbidOf(sole.id)!, name: sole.name || row.song.credit }, family)))
      return out
    }
    case 'group': {
      const sole = soleCredit(row.group['artist-credit'])
      return sole ? [(row.saved ? savedRow : (each: Row) => each)(creditedRow(sole, family))] : []
    }
    default:
      return []
  }
}

/**
 * Top results: `n` picks from the candidates, continuing a prefix already drawn (`fixed`) as if those had been picked
 * first. Without one: the best (the lowest by tier, source, kind, position), then its family - each skipped if
 * already picked. Then round by round over the kinds, in kind order: a kind with fewer picks than the round number
 * takes its best remaining candidate, until there are `n` (fewer candidates, fewer picks; a kind with none skipped).
 * A phantom picked is returned as one - decidedTop stops there.
 */
export function topResults(candidates: readonly Candidate[], n: number, family: Family, fixed: readonly Row[] = []): Candidate[] {
  const picked: Candidate[] = fixed.map((row) => ({ row, key: row.key, kind: kindOf(row), tier: 0, source: 0, position: 0, phantom: false }))
  const keys = new Set(picked.map((each) => each.key))
  const left = [...candidates].filter((each) => !keys.has(each.key)).sort(rank)
  const take = (each: Candidate) => {
    picked.push(each)
    keys.add(each.key)
  }
  if (!picked.length && left.length) {
    const best = left[0]!
    take(best)
    if (best.row) {
      for (const relative of familyOf(best.row, family)) {
        if (picked.length >= n) break
        if (keys.has(relative.key)) continue
        take({ row: relative, key: relative.key, kind: kindOf(relative), tier: 3, source: 2, position: 0, phantom: false })
      }
    }
  }
  for (let round = 1; picked.length < n; round++) {
    let took = false
    for (const kind of KINDS) {
      if (picked.length >= n) break
      if (picked.filter((each) => each.kind === kind).length >= round) continue
      const next = left.find((each) => each.kind === kind && !keys.has(each.key))
      if (!next) continue
      take(next)
      took = true
    }
    if (!took && !KINDS.some((kind) => left.some((each) => each.kind === kind && !keys.has(each.key)))) break
  }
  return picked.slice(0, n)
}

/**
 * Top results decided before MusicBrainz has answered, without anything moving: topResults over what is in hand plus
 * one phantom per MusicBrainz kind still out. The picks before the first phantom are the decided `prefix`, drawn at
 * once and frozen; `place` when a phantom was picked - one place is kept at Top results' foot for the rest, filled
 * in the render that draws the sections (topResults with the prefix fixed). A phantom first: no prefix, and no Top
 * results section until then.
 */
export function decidedTop(candidates: readonly Candidate[], phantoms: readonly Candidate[], n: number, family: Family): { prefix: Row[]; place: boolean } {
  const picks = topResults([...candidates, ...phantoms], n, family)
  const first = picks.findIndex((each) => each.phantom)
  const prefix = (first < 0 ? picks : picks.slice(0, first)).map((each) => each.row!)
  return { prefix, place: first >= 0 }
}

/* ===== the requests ===== */

/** The library songs among Top results' decided picks - whose albums the prefetch asks for first. */
export function preferredSongs(rows: readonly Row[]): LibrarySong[] {
  return rows.flatMap((row) => (row.type === 'song' ? [row.song] : []))
}

/**
 * What the All view's Albums section asks MusicBrainz, by the box's reading (`studio`: the studio clause is on, and
 * named on screen): an artist you have alone is their studio albums and EPs - `artist:"A"` with
 * typeFilter({primary: Album and EP, studioOnly}) - because their first page unfiltered is live albums, an interview,
 * compilations and singles (measured: Portishead's twelve held no Dummy and no Third; the studio clause brought six,
 * Third and Dummy among them). Never for Various Artists, whose records are compilations by nature (the clause
 * excludes Compilation by name): today's `artist:"Various Artists"`, unfiltered. Anything else as read.
 */
export function allAlbumsQuery(plan: SearchPlan): { query: string; studio: boolean } {
  if (plan.kind !== 'artist' || !plan.artist || plan.artist === VARIOUS_ARTISTS) return { query: plan.query, studio: false }
  return { query: withTypeFilter(`artist:${quoteTerm(plan.artist)}`, typeFilter({ primary: ['Album', 'EP'], studioOnly: true })), studio: true }
}

/** The studio clause's answer in the order an artist's albums are read: Album before EP, no secondary type first, the
 *  earliest first - MusicBrainz's order (it scores them all 100) breaking ties. */
export function studioOrder(groups: readonly ReleaseGroup[]): ReleaseGroup[] {
  const primary = (group: ReleaseGroup) => ((group['primary-type'] ?? '').toLowerCase() === 'album' ? 0 : (group['primary-type'] ?? '').toLowerCase() === 'ep' ? 1 : 2)
  const secondary = (group: ReleaseGroup) => ((group['secondary-types'] ?? []).length ? 1 : 0)
  const date = (group: ReleaseGroup) => `${group['first-release-date'] || ''}~`
  return groups
    .map((group, at) => ({ group, at }))
    .sort((a, b) => primary(a.group) - primary(b.group) || secondary(a.group) - secondary(b.group)
      || (date(a.group) < date(b.group) ? -1 : date(a.group) > date(b.group) ? 1 : 0) || a.at - b.at)
    .map(({ group }) => group)
}

/** The line under an artist read's Albums in All when the studio clause asked them: the active filter, always shown. */
export const STUDIO_NOTE = "MusicBrainz's studio albums and EPs - See all for everything they made."

/* ===== the moments ===== */

/**
 * Whether the sections are drawn now (moment 2): the library settled, and - when MusicBrainz is to be asked - it has
 * been, and every kind asked has answered or failed, or RESULTS_WAIT_MS has passed since it was asked. MusicBrainz not
 * to be asked (under three characters, no Enter): at once, the library alone.
 */
export function sectionsReady({ librarySettled, musicBrainz, asked, out, capPassed }: {
  librarySettled: boolean
  /** MusicBrainz is to be asked for these words */
  musicBrainz: boolean
  /** ...and has been */
  asked: boolean
  /** the kinds asked still out */
  out: readonly Kind[]
  capPassed: boolean
}): boolean {
  if (!librarySettled) return false
  if (!musicBrainz) return true
  if (!asked) return false
  return !out.length || capPassed
}

/** The kinds still out at moment 2: each gets a slot in its section, one fixed height, for its answer to land in. */
export function lateKinds(wanted: readonly Kind[], inHand: (kind: Kind) => boolean): Kind[] {
  return wanted.filter((kind) => !inHand(kind))
}

/**
 * Where a late kind's answer goes as it lands: drawn straight IN when nothing tappable is drawn below its section -
 * every drawn section has See all in its head, so only the last section drawn - else FOLDED into its slot ("Show 3
 * albums from MusicBrainz", or why there are none), so nothing drawn below it moves.
 */
export function drawInOrFold(kind: Kind, drawn: readonly Kind[], footTappable = false): 'in' | 'fold' {
  const at = drawn.indexOf(kind)
  return at >= 0 && at === drawn.length - 1 && !footTappable ? 'in' : 'fold'
}

/** What a search's MusicBrainz asks came to, for Behind. */
export type Outcome = 'in-time' | 'late' | 'failed' | 'superseded' | 'refused'

/**
 * Behind: after a search whose MusicBrainz missed RESULTS_WAIT_MS with a kind out (while it was still the search
 * shown) or failed as MusicBrainz away, the next searches draw at the library's moment, MusicBrainz's in slots - your
 * rows don't wait 1.5 s each time while MusicBrainz is shedding. It ends after a search whose every kind asked
 * answers in time. A search superseded before its cap counts for nothing; nor does one refused (the words, not
 * MusicBrainz being slow).
 */
export function nextBehind(was: boolean, outcome: Outcome): boolean {
  if (outcome === 'late' || outcome === 'failed') return true
  if (outcome === 'in-time') return false
  return was
}

/* ===== the words ===== */

/** A row's place, as a Top results tile's third line says it: "In your library", "In the store", "On MusicBrainz" -
 *  '' while it can't be told. */
export function placeLabel(row: Row, marks: Marks, evidence: SongEvidence = {}): string {
  const library = row.type === 'artist' || row.type === 'album' || row.type === 'song'
  const yours = rowYours(row, marks, evidence)
  if (library) return yours === null ? '' : yours ? 'In your library' : 'In the collection'
  if (yours === null) return isSaved(row) ? SAVED_PLACE : 'On MusicBrainz'
  return yours ? 'In your library' : 'In the collection'
}

/** Whether a row is from what's saved (2.0.0-player.56). */
export const isSaved = (row: Row) => 'saved' in row && row.saved === true

/** What marks a row from what's saved: a section row's place words, and a Top results tile's third line. */
export const SAVED_MARK = 'saved'
export const SAVED_PLACE = 'Saved from MusicBrainz'

/** What's saved's place on a row, unless the row already says where it is (held: "in your library"). */
const savedPlace = (row: Row, place: string) => (place || !isSaved(row) ? place : SAVED_MARK)

/** A MusicBrainz group's kind word in a section, said only when it isn't a plain album ("EP", "Live album"), as Apple
 *  adds " - EP". */
function groupWord(group: ReleaseGroup): string {
  const kind = groupKind(group)
  return kind === 'Album' ? '' : kind
}

const yearOfDate = (date: string) => (/^\d{4}/.test(date) ? date.slice(0, 4) : '')

/** What a line needs beyond the row: whose, the library's answer, the frame's place. */
export interface LineContext {
  marks: Marks
  evidence?: SongEvidence
}

/**
 * A row's second line, as its parts: the facts (which take the ellipsis) and the place words (their own
 * non-shrinking span, so "in your library" is never cut at 320). `top`: as Top results say it - the kind word first
 * ("Song · Portishead · Dummy"); in a section the heading says the kind and it is left out.
 */
export function rowLine(row: Row, context: LineContext, top = false): { line: string; place: string } {
  const { marks, evidence = {} } = context
  const join = (...parts: (string | null | undefined)[]) => parts.filter(Boolean).join(' · ')
  switch (row.type) {
    case 'artist': {
      const yours = marks.personal ? marks.yourArtists?.get(row.artist.id) ?? 0 : 0
      //? your own count when you have albums of theirs; the store's (true either way) otherwise
      const count = yours > 0 ? `${yours} ${yours === 1 ? 'album' : 'albums'} ${IN_YOUR_LIBRARY}` : artistLine(row.artist.albumCount, marks.personal)
      return { line: top ? 'Artist' : '', place: count }
    }
    case 'mb-artist': {
      const said = matchLine(row.match)
      return { line: top ? join('Artist', said) : said, place: savedPlace(row, '') }
    }
    case 'album': {
      const year = row.album.year && row.album.year > 0 ? String(row.album.year) : ''
      return { line: join(top ? 'Album' : '', row.album.artist, year), place: libraryPlace(marks.personal, albumYours(row.album, marks)) }
    }
    case 'group': {
      const held = groupHeld(marks.index, row.group.id)
      const word = top ? groupKind(row.group) : groupWord(row.group)
      return {
        line: join(word, creditName(row.group['artist-credit']), groupYear(row.group)),
        place: savedPlace(row, held ? groupPlace(marks.index, row.group.id, marks.personal) : ''),
      }
    }
    case 'song':
      return { line: join(top ? 'Song' : '', row.song.artist, row.song.album), place: libraryPlace(marks.personal, songYours(row.song, marks)) }
    case 'mb-song': {
      const { album, held } = namedAlbum(row.song, marks.index, evidence)
      const length = album.length === null ? '' : clock(Math.round(album.length / 1000))
      return {
        line: top ? join('Song', row.song.credit, album.title) : join(row.song.credit, length, album.title),
        place: savedPlace(row, heldWords(held, marks.personal)),
      }
    }
    case 'song-album': {
      const word = row.album.kind && row.album.kind !== 'Album' ? row.album.kind : 'Album'
      return {
        line: join(top ? word : '', row.album.credit, yearOfDate(row.album.date)),
        place: savedPlace(row, songAlbumWords(songAlbumHolding(marks.index, row.album, row.song, evidence), marks.personal)),
      }
    }
  }
}

const clock = (seconds: number) => `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`

const plural = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`
const KIND_WORDS: Record<Kind, [string, string]> = { artists: ['artist', 'artists'], albums: ['album', 'albums'], songs: ['song', 'songs'] }

/** What the list's one live region says of what a part brought: "1 artist, 2 albums, 11 songs" - '' for nothing. */
export function countWords(counts: Partial<Record<Kind, number>>): string {
  return KINDS.filter((kind) => (counts[kind] ?? 0) > 0).map((kind) => plural(counts[kind]!, ...KIND_WORDS[kind])).join(', ')
}

/** The region's words for the library: "In your library: 1 artist, 2 albums, 11 songs." ("In the store: …" with a
 *  library of your own) - '' when it found nothing. */
export function libraryWords(counts: Partial<Record<Kind, number>>, personal: boolean): string {
  const said = countWords(counts)
  return said ? `${personal ? 'In the collection' : 'In your library'}: ${said}.` : ''
}

/** ...and for MusicBrainz, once every kind asked has settled: "From MusicBrainz: 2 artists, 3 albums, 3 songs." - or
 *  that it isn't answering, when no kind did. `saved` (2.0.0-player.56): what's saved is drawn above - what
 *  MusicBrainz adds is more, and when it isn't answering, what is drawn is what's saved. */
export function musicBrainzWords(counts: Partial<Record<Kind, number>>, answered: boolean, saved = false): string {
  if (!answered) return saved ? SAVED_AWAY_SAID : "MusicBrainz isn't answering."
  const said = countWords(counts)
  if (saved) return said ? `More from MusicBrainz: ${said}.` : 'Nothing more from MusicBrainz.'
  return said ? `From MusicBrainz: ${said}.` : 'Nothing from MusicBrainz.'
}

/** The region's words for what's saved, as the sections that hold it are drawn: "Saved from MusicBrainz: 1 song." */
export function savedWords(counts: Partial<Record<Kind, number>>): string {
  const said = countWords(counts)
  return said ? `Saved from MusicBrainz: ${said}.` : ''
}

const SAVED_AWAY_SAID = "MusicBrainz isn't answering - these are what deadwax has saved."

/** A MusicBrainz failure's words where what's saved is drawn above it (2.0.0-player.56): MusicBrainz isn't answering
 *  (or is busy), and these are what deadwax has saved - one line; a refusal is the words', as ever. */
export function savedAwayWords(failure: { refused: boolean; busy: boolean; message: string; unavailable: boolean }, short = false): string {
  if (failure.refused) return failure.message
  //? `short`: a kind's slot, one fixed-height row beside Try again - the point first, so it fits a 320-wide phone
  //? (the review measured "MusicBrainz isn't answering - these are saved." cut to "…these are sa…" at 375 and 320)
  if (failure.busy) return short ? 'Saved - MusicBrainz is busy.' : 'MusicBrainz is busy just now - these are what deadwax has saved from it.'
  if (failure.unavailable) return short ? 'Saved - MusicBrainz is away.' : "MusicBrainz isn't answering just now - these are what deadwax has saved from it."
  return failure.message
}

/** What a late kind's slot says when MusicBrainz's answer brought nothing that isn't drawn above it already. */
export function nothingMoreWords(kind: Kind, text: string): string {
  return `No more ${KIND_WORDS[kind][1]} on MusicBrainz for “${text}”.`
}

/** A late kind folded into its slot: the button's words, and what the region says of it. */
export function foldWords(kind: Kind, count: number): { button: string; said: string } {
  const what = plural(count, ...KIND_WORDS[kind])
  return { button: `Show ${what} from MusicBrainz`, said: `${what} from MusicBrainz - Show them to see them.` }
}

/** What a late kind's slot says when its answer brought no row to draw (`text`: the words searched). */
export function emptyWords(kind: Kind, text: string): string {
  return `No ${KIND_WORDS[kind][1]} on MusicBrainz for “${text}”.`
}

/** The library's place kept at the list's top, its answer landing after the list was drawn without it: how many it
 *  found, with Show them - or that it found nothing. */
export function libraryLateWords(counts: Partial<Record<Kind, number>>, personal: boolean, text: string): { button: string | null; line: string } {
  const total = KINDS.reduce((sum, kind) => sum + (counts[kind] ?? 0), 0)
  const where = personal ? IN_THE_STORE : IN_YOUR_LIBRARY
  if (!total) return { button: null, line: `Nothing ${where} for “${text}”.` }
  return { button: `${total} ${where} - Show them`, line: '' }
}

/** The library's place kept at the list's top when Navidrome turned out not to be reachable: it wasn't searched, so it
 *  says so - never that it found nothing (review). */
export function librarySkippedWords(personal: boolean): string {
  return personal ? "The collection can't be searched just now." : "Your library can't be searched just now."
}

/** The words of a kind's MusicBrainz failure: refused (a 422 with words - the words, no Try again), busy, or away. */
export function failureWords(failure: { refused: boolean; busy: boolean; message: string; unavailable: boolean }, short = false): string {
  if (failure.refused) return failure.message
  if (failure.busy) return 'MusicBrainz is busy just now - try again in a moment.'
  if (failure.unavailable) return short ? "MusicBrainz isn't answering." : "MusicBrainz isn't answering just now - it often goes away for a few minutes."
  return failure.message
}

/** "Showing albums." / "Showing everything." - said as a chip is pressed. */
export function viewWords(view: View): string {
  return view === 'all' ? 'Showing everything.' : `Showing ${view}.`
}

/** A kind view's "No albums for “…”." when nothing at all was found. */
export function nothingWords(view: View, text: string): string {
  return view === 'all' ? `No results for “${text}”` : `No ${view} for “${text}”.`
}

/** Where MusicBrainz's rows would go when it won't be asked yet. */
export const TYPE_MORE = 'Type a little more, or press Search, to ask MusicBrainz too.'
/** ...in the Songs view, for an artist's name alone: MusicBrainz is asked for no songs. */
export const SONGS_NEED_A_TITLE = 'Type a song\'s title with the artist (“roads portishead”) to find their songs on MusicBrainz.'
