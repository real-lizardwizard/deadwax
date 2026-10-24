/**
 * Song search (2.0.0-player.53, step 7 of the multi-user plan) - pure, pinned by ui/test/songs.sim.cjs
 * against real MusicBrainz answers (tests/fixtures/songs/, recorded 2026-10-15).
 *
 * People often know a SONG, not the album it is on. MusicBrainz's recording search (deadwax's
 * /search_musicbrainz/songs) answers with recordings, each carrying every release it is on - with the
 * release's group (title, primary and secondary types), status, date and country, and the track itself -
 * so the albums a song is on come in the one answer, nothing asked per album.
 *
 * WHAT REAL ANSWERS LOOK LIKE, and why the rows read as they do. A recording is one performance: the
 * studio take, every live tape and every re-recording are recordings of their own, and MusicBrainz's
 * relevance gives them all the same score - so they come back in no useful order:
 *  - "Roads" by Portishead, fielded: 45 recordings, every one Portishead's "Roads" at score 100 - the
 *    studio take (Dummy) fourth, ten live tapes around it;
 *  - "Bohemian Rhapsody" by Queen: 227 recordings; the studio take, third, is on 353 releases in 133
 *    release groups, the rest are live tapes and compilation takes;
 *  - "Hey Jude" by The Beatles: 219 recordings, and the studio take not among the first dozen (a boost
 *    for Official releases, tried once, moved official takes up but still not that one - scores tie);
 *  - "Miss Misery" by Elliott Smith: 33 recordings, on no album or EP at all - a soundtrack, compilations
 *    and live tapes;
 *  - and the words alone, with no artist the library knows to read them by ("hey jude", "roads
 *    portishead"), match TITLES: covers, tributes and mash-ups - "hey jude" has no Beatles in any of the 300
 *    answers looked at (the first 200, and 400-499), "roads portishead" no Portishead in its first page.
 * One row per recording would be a dozen rows of "Roads · Portishead" told apart by a length, with the
 * one on Dummy wherever it happened to land. So the rows are SONGS: the recordings of one title by one
 * credit are one row (`songKey`), their albums unioned - and ordered (`sortAlbums`) so the studio album
 * leads: Albums and EPs first, then Singles, then compilations, live albums, soundtracks and the rest
 * folded under one "On N compilations…" (`foldLabel`) that opens; Official before Promotion before
 * Bootleg within each; the earliest first. A live take is told apart in its album's row ("Live album ·
 * Bootleg · 2008"), and by its length where that is another version's.
 *
 * Opening one of those albums opens the album you don't have on a pressing that HAS the song
 * (`songPressing`): the album's usual pressing when it has it, else the most usual of those that do - the
 * bonus-track case - with the song marked in its tracklist (`songMatcher`), by its recordings, or by its
 * title (MusicBrainz often has the same song as another recording on another pressing of one album).
 */

import type { Recording, RecordingRelease } from '../api/types'
import { heldInOrder } from './idBridge'
import { foldName, ownedForGroup, type OwnedAlbum, type OwnedIndex } from './owned'
import { creditName } from './release'
import { groupKind } from './searchResults'
import { formatSeconds, isOtherVersion, representativeRelease, type PressingRelease } from './tracklistDiff'
import { anyYours, heldPhrase, pressingHeldPhrase } from './whose'

/** How many recordings one page of a song search asks for - the route's own (SONG_SEARCH_LIMIT in
 *  src/routes/search_musicbrainz.py; tests/test_musicbrainz_routes.py holds the two to one number). A
 *  song's takes merge into one row, so a bigger page is more of one song's albums in one request. */
export const SONG_SEARCH_LIMIT = 25

/** How many songs the section shows before More: a few, so an album's words still show the albums. */
export const SONG_ROWS_SHOWN = 3

/** How many of a song's recordings an album's address carries, at most. */
export const SONG_IDS_KEPT = 8

export type SongBand = 'album' | 'single' | 'other'

/** One album a song is on: a release group, as the song's releases in it tell it. */
export interface SongAlbum {
  /** the release group's MusicBrainz id */
  id: string
  title: string
  primaryType: string | null
  secondaryTypes: string[]
  /** "Album", "EP", "Single", "Compilation", "Live album", "Soundtrack"... (groupKind's words) */
  kind: string
  /** Albums and EPs, Singles, or the rest - folded */
  band: SongBand
  /** the best status of its releases that have the song: "Official", "Promotion", "Bootleg", or '' */
  status: string
  /** the earliest date any of them came out, '' when none says */
  date: string
  /** who the album is credited to - "Various Artists" for most compilations */
  credit: string
  /** its releases that have the song, by id (lowercase): what the library's release ids are checked against */
  releases: string[]
  /** the song's recordings on it, by id (lowercase) */
  recordings: string[]
  /** the song's length on it in milliseconds, or null */
  length: number | null
}

/** A song: every recording of one title by one credit that a search found, and the albums they are on. */
export interface Song {
  key: string
  title: string
  credit: string
  /** (2.0.0-player.55) the artists its credit names, by MusicBrainz id - what Search's Top results pull in for
   *  a song (its sole credited artist, lib/searchList.ts); empty when the credit names none */
  artists: { id: string; name: string }[]
  /** its recordings, by id (lowercase), in the order found */
  recordings: string[]
  /** the albums it is on, sorted (sortAlbums) - never empty */
  albums: SongAlbum[]
}

/** A bracketed aside naming the same song in another take or mastering - "(live)", "(Live UK 1998)",
 *  "(Remastered 2015)", "(2011 remaster)", "(mono)" - which real answers put in titles beside the plain one. */
const SAME_SONG_ASIDE = /\s*[([]\s*(?:live\b[^)\]]*|[^)\]]*\bremaster(?:ed)?\b[^)\]]*|mono|stereo)\s*[)\]]/giu

/** Whether a title carries such an aside - the row then says the song by a plain title when it has one. */
const hasAside = (title: string) => new RegExp(SAME_SONG_ASIDE.source, 'iu').test(title)

/** Text as songs are told apart: accents, case and punctuation folded, and an aside naming another take or a
 *  remaster ("(live)", "(Remastered 2015)") dropped - but no other words in brackets, so "Roads (Max Cooper
 *  remix)" and "Sour Times (Airbus Reconstruction)" stay songs of their own. */
export function titleKey(title: string | null | undefined): string {
  return String(title ?? '')
    .replace(SAME_SONG_ASIDE, ' ')
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .toLowerCase()
    .replace(/[’‘`´]/g, "'")
    .replace(/&/g, ' and ')
    .replace(/[^\p{L}\p{N}()[\]']+/gu, ' ')
    .trim()
}

/** Which song a recording is: its title and who it is credited to - by the artists' ids where it names
 *  them (two bands of one name stay two), else by the credit's words. */
export function songKey(recording: Pick<Recording, 'title' | 'artist-credit'>): string {
  const credit = recording['artist-credit'] ?? []
  const ids = credit.map((entry) => (entry.artist?.id ?? '').toLowerCase()).filter(Boolean).sort()
  const who = ids.length ? ids.join('+') : titleKey(creditName(credit))
  return `${who}\n${titleKey(recording.title)}`
}

const STATUS_RANK: Record<string, number> = { official: 0, promotion: 1, bootleg: 2 }
const statusRank = (status: string | null | undefined) => STATUS_RANK[(status ?? '').toLowerCase()] ?? 3

/** Which band an album sits in: Albums and EPs; Singles; or - anything with a secondary type (a
 *  compilation, a live album, a soundtrack, a remix...) and anything else - the fold. */
export function songBand(primaryType: string | null | undefined, secondaryTypes: readonly string[] | null | undefined): SongBand {
  if ((secondaryTypes ?? []).length) return 'other'
  const primary = (primaryType ?? '').toLowerCase()
  if (primary === 'album' || primary === 'ep') return 'album'
  return primary === 'single' ? 'single' : 'other'
}

const BAND_RANK: Record<SongBand, number> = { album: 0, single: 1, other: 2 }
//? '~' after every digit and '-': a full date before its bare year, and undated last (tracklistDiff's trick)
const dateKey = (date: string) => `${date}~`

/** A song's albums in the order they are listed: Albums and EPs, then Singles, then the rest; Official
 *  before Promotion before Bootleg within each (anything else after); the earliest first; then by title. */
export function sortAlbums(albums: readonly SongAlbum[]): SongAlbum[] {
  return [...albums].sort((a, b) =>
    BAND_RANK[a.band] - BAND_RANK[b.band]
    || statusRank(a.status) - statusRank(b.status)
    || (dateKey(a.date) < dateKey(b.date) ? -1 : dateKey(a.date) > dateKey(b.date) ? 1 : 0)
    || a.title.localeCompare(b.title)
    || a.id.localeCompare(b.id))
}

const lower = (id: string | null | undefined) => (id ?? '').trim().toLowerCase()

/** The song's track on one of its releases, as the recording search carries it. */
function trackLength(release: RecordingRelease): number | null {
  for (const medium of release.media ?? []) {
    for (const track of medium.track ?? []) if (typeof track.length === 'number' && Number.isFinite(track.length)) return track.length
  }
  return null
}

/**
 * The songs a search found (one page, or every page so far): its recordings of one title by one credit
 * made one song (songKey), in the order MusicBrainz first gave each, each with the albums its recordings
 * are on - one per release group, unioned - sorted. A song on no release MusicBrainz lists is left out:
 * there is no album to show it on, or to get.
 */
export function groupSongs(recordings: readonly Recording[]): Song[] {
  const songs = new Map<string, { title: string; credit: string; artists: { id: string; name: string }[]; recordings: string[]; albums: Map<string, SongAlbum> }>()
  for (const recording of recordings) {
    const key = songKey(recording)
    let song = songs.get(key)
    if (!song) {
      song = { title: recording.title ?? '', credit: creditName(recording['artist-credit']), artists: creditArtists(recording['artist-credit']), recordings: [], albums: new Map() }
      songs.set(key, song)
    }
    //? the row says the song by a plain title - "Roads", not "Roads (live)" - when any take has one
    if (hasAside(song.title) && recording.title && !hasAside(recording.title)) song.title = recording.title
    const id = lower(recording.id)
    if (id && !song.recordings.includes(id)) song.recordings.push(id)
    for (const release of recording.releases ?? []) {
      const group = release['release-group']
      const groupId = lower(group?.id)
      if (!groupId) continue
      const length = trackLength(release) ?? (typeof recording.length === 'number' ? recording.length : null)
      const date = (release.date ?? '').trim()
      const was = song.albums.get(groupId)
      if (!was) {
        const primaryType = group?.['primary-type'] ?? null
        const secondaryTypes = [...(group?.['secondary-types'] ?? [])]
        song.albums.set(groupId, {
          id: groupId, title: group?.title ?? release.title ?? '', primaryType, secondaryTypes,
          kind: groupKind({ ...(primaryType ? { 'primary-type': primaryType } : {}), 'secondary-types': secondaryTypes }),
          band: songBand(primaryType, secondaryTypes), status: release.status ?? '', date,
          credit: creditName(release['artist-credit']) || creditName(recording['artist-credit']),
          releases: release.id ? [lower(release.id)] : [], recordings: id ? [id] : [], length,
        })
        continue
      }
      if (statusRank(release.status) < statusRank(was.status)) was.status = release.status ?? ''
      if (date && (!was.date || dateKey(date) < dateKey(was.date))) was.date = date
      if (release.id && !was.releases.includes(lower(release.id))) was.releases.push(lower(release.id))
      if (id && !was.recordings.includes(id)) was.recordings.push(id)
      if (was.length === null) was.length = length
    }
  }
  return [...songs.entries()]
    .filter(([, song]) => song.albums.size)
    .map(([key, song]) => ({ key, title: song.title, credit: song.credit, artists: song.artists, recordings: song.recordings, albums: sortAlbums([...song.albums.values()]) }))
}

/** The artists a credit names, each once, by id (lowercase) and the name the credit gives them - those with an id. */
function creditArtists(credit: Recording['artist-credit']): { id: string; name: string }[] {
  const artists: { id: string; name: string }[] = []
  for (const entry of credit ?? []) {
    const id = lower(entry.artist?.id)
    const name = (entry.name || entry.artist?.name || '').trim()
    if (id && !artists.some((artist) => artist.id === id)) artists.push({ id, name })
  }
  return artists
}

/**
 * One more page of the song search, merged into what is there: every page's recordings regrouped, the
 * songs already drawn (`drawn`, in the order they are drawn - groupSongs' own for the first page) kept in
 * their places, a later page's take of one of them adding its albums in place, and every other song after
 * them, in the order MusicBrainz gave it - a song whose earlier takes were on no release, so never drawn,
 * among them (review: it came back in its first take's place, above rows already drawn) - `added` how many
 * new songs, `grown` how many albums the songs already drawn gained.
 */
export function appendSongs(recordings: readonly Recording[], page: readonly Recording[], drawn: readonly Song[] = groupSongs(recordings)): {
  recordings: Recording[]; songs: Song[]; added: number; grown: number
} {
  const all = [...recordings, ...page]
  const regrouped = groupSongs(all)
  const byKey = new Map(regrouped.map((song) => [song.key, song]))
  const kept: Song[] = []
  let grown = 0
  for (const was of drawn) {
    //? a song drawn is still a song - its recordings are all still here, its albums only grow
    const now = byKey.get(was.key)
    if (!now) continue
    kept.push(now)
    grown += now.albums.length - was.albums.length
  }
  const keys = new Set(kept.map((song) => song.key))
  const fresh = regrouped.filter((song) => !keys.has(song.key))
  return { recordings: all, songs: [...kept, ...fresh], added: fresh.length, grown }
}

/** A song's albums split for drawing: Albums, EPs and Singles listed; the rest behind the fold. */
export function songAlbumBands(song: Pick<Song, 'albums'>): { listed: SongAlbum[]; folded: SongAlbum[] } {
  return { listed: song.albums.filter((album) => album.band !== 'other'), folded: song.albums.filter((album) => album.band === 'other') }
}

/** What a folded album is, for the fold's words - named as its own row names it (groupKind): a live record
 *  is a "live album" only when it is an album ("Live album"; a live broadcast, EP or single isn't - review),
 *  a broadcast is a broadcast, live or not. */
function family(album: SongAlbum): 'compilation' | 'live' | 'soundtrack' | 'broadcast' | 'other' {
  const types = album.secondaryTypes.map((type) => type.toLowerCase())
  const primary = (album.primaryType ?? '').toLowerCase()
  if (types.includes('compilation')) return 'compilation'
  if (types.includes('live') && (!primary || primary === 'album')) return 'live'
  if (types.includes('soundtrack')) return 'soundtrack'
  if (primary === 'broadcast') return 'broadcast'
  return 'other'
}

const FAMILY_WORDS: Record<ReturnType<typeof family>, [string, string]> = {
  compilation: ['compilation', 'compilations'],
  live: ['live album', 'live albums'],
  soundtrack: ['soundtrack', 'soundtracks'],
  broadcast: ['broadcast', 'broadcasts'],
  other: ['other record', 'other records'],
}

/** The fold's words: "On 1 compilation", "On 11 compilations, live albums and soundtracks" - what is in
 *  it, in that order, "broadcasts" for radio and TV, "other records" for the rest. */
export function foldLabel(folded: readonly SongAlbum[]): string {
  const present = (['compilation', 'live', 'soundtrack', 'broadcast', 'other'] as const).filter((each) => folded.some((album) => family(album) === each))
  const words = present.map((each) => FAMILY_WORDS[each][folded.length === 1 ? 0 : 1])
  const listed = words.length > 1 ? `${words.slice(0, -1).join(', ')} and ${words[words.length - 1]}` : words[0] ?? 'other records'
  return `On ${folded.length} ${listed}`
}

/** A song the library's own search found (Navidrome's search3 - Search's library half, player/api's `Song`):
 *  what can say that a pressing you hold has the song when the recording search didn't name that pressing. */
export interface HeardSong {
  title?: string
  artist?: string
  album?: string
  albumId?: string
}

/**
 * What else says a pressing you hold has the song, beyond the releases the recording search found it on
 * (second review: MusicBrainz keeps one song as several recordings across one album's pressings - Dummy's 1994
 * CD, 76df3287, has Roads as recording 8a49dba0, which only the second page of "roads portishead" brings - so
 * holding that CD read as "another pressing", a pressing WITHOUT the song by the docs' words, right under the
 * library half playing Roads from it, and its tap opened the album you don't have):
 *  - `heard`: the library half's songs - one titled as the song (titleKey), by its credit, on an album named as
 *    the folder's own album tag (foldName; Navidrome's album name and the folder's are read from the same
 *    files' tags). A song with no artist or no album id says nothing;
 *  - `pressings`: the album's pressings with their tracklists when the session already has them
 *    (app/pressingLists.ts's `kept`) - a held pressing with a track of the song (songMatcher: by its
 *    recordings or its title) has it.
 */
export interface SongEvidence {
  heard?: readonly HeardSong[] | null
  pressings?: ((groupId: string) => readonly PressingRelease[] | null | undefined) | null
}

/** What the library holds of a song's album (songAlbumHolding). */
export interface SongHolding {
  /** the folders of a pressing that has the song - by its release, or its tracklist - or with no release id */
  song: OwnedAlbum[]
  /** the folders of another pressing the library's own search shows the song on */
  heard: OwnedAlbum[]
  /** the folders of a pressing nothing here says has the song, or hasn't: "a pressing in your library" */
  other: OwnedAlbum[]
  /** Navidrome's albums the library's search found the song on, for `heard`: the album you have, to open */
  albums: string[]
}

//? an album's kept pressings are one object for the session, and every line of a song's albums asks after them
//? (namedAlbum for each row) - a big album's tracklists folded once per list and song, not once per row and render
const pressedFor = new WeakMap<readonly PressingRelease[], Map<string, Set<string> | null>>()

/** The releases of an album's pressings (as kept) that have the song - null when nothing can be told. */
function pressingsWith(releases: readonly PressingRelease[] | null | undefined, ids: readonly string[]): Set<string> | null {
  if (!releases?.length) return null
  const key = ids.map(lower).join(',')
  let known = pressedFor.get(releases)
  if (!known) pressedFor.set(releases, (known = new Map()))
  if (known.has(key)) return known.get(key)!
  const matches = songMatcher(releases, ids)
  const has = matches
    ? new Set(releases.filter((release) => release.id && tracksOf(release).some(matches)).map((release) => lower(release.id)))
    : null
  known.set(key, has)
  return has
}

/** The library half's songs that are this song on this folder's album: their Navidrome album ids. */
function heardOn(heard: readonly HeardSong[] | null | undefined, song: Pick<Song, 'title' | 'credit'>, folder: OwnedAlbum): string[] {
  const title = titleKey(song.title)
  const credit = foldName(song.credit)
  const name = foldName(folder.album)
  if (!heard?.length || !title || !credit || !name) return []
  return heard
    .filter((each) => each.albumId && titleKey(each.title) === title && foldName(each.artist) === credit && foldName(each.album) === name)
    .map((each) => each.albumId!)
}

/**
 * What the library holds of a song's album, split by whether it has the SONG (review: holding The Slow Rush's
 * usual CD read as holding Patience, a bonus track on its Japanese CD alone - "in your library", and a tap
 * opening an album without it):
 *  - `song`: the folders of a pressing the song is on - a release of the album the search found the song on
 *    (`album.releases`; an .m4a deadwax filed carries a release id and no group id), or one whose tracklist has
 *    it (`evidence.pressings`) - or of the album with no release id at all, which can't be told apart (by the
 *    group's id alone, as every screen holds it);
 *  - `heard`: another pressing the library's own search shows the song on (`evidence.heard`), with `albums`
 *    its Navidrome albums;
 *  - `other`: another pressing nothing here says has the song or hasn't. Often one without it (the bonus-track
 *    case), but just as often one with it as a recording this page of the search didn't bring (second review:
 *    Dummy's 1994 CD) - so it is said as a pressing you hold, never as the song nor as its absence, and its
 *    tap looks at the album's pressings before it opens anything (app/Search.tsx).
 * All empty without the library's answer.
 */
export function songAlbumHolding(
  index: OwnedIndex | null | undefined,
  album: Pick<SongAlbum, 'id' | 'releases' | 'recordings'>,
  song: Pick<Song, 'title' | 'credit'> | null = null,
  evidence: SongEvidence = {},
): SongHolding {
  const releases = new Set(album.releases.map(lower))
  const holding: SongHolding = { song: [], heard: [], other: [], albums: [] }
  let pressed: Set<string> | null | undefined
  for (const folder of ownedForGroup(index, { groupId: album.id, releaseIds: album.releases }).held) {
    const release = lower(folder.release_mbid)
    if (!release || releases.has(release)) {
      holding.song.push(folder)
      continue
    }
    if (pressed === undefined) pressed = pressingsWith(evidence.pressings?.(album.id), album.recordings)
    if (pressed?.has(release)) {
      holding.song.push(folder)
      continue
    }
    const albums = song ? heardOn(evidence.heard, song, folder) : []
    if (albums.length) {
      holding.heard.push(folder)
      for (const id of albums) if (!holding.albums.includes(id)) holding.albums.push(id)
      continue
    }
    holding.other.push(folder)
  }
  return holding
}

/** The folders the library holds of a song's album that have the song (songAlbumHolding's `song` and `heard`). */
export function songAlbumHeld(
  index: OwnedIndex | null | undefined,
  album: Pick<SongAlbum, 'id' | 'releases' | 'recordings'>,
  song: Pick<Song, 'title' | 'credit'> | null = null,
  evidence: SongEvidence = {},
): OwnedAlbum[] {
  const holding = songAlbumHolding(index, album, song, evidence)
  return [...holding.song, ...holding.heard]
}

/** The releases of a song's album the library holds WITH the song by its release or its tracklist (`song`), in
 *  the order every screen opens one (heldInOrder) - what the id bridge is asked about, to open the album you
 *  have. None for a pressing only the library's search vouches for (its Navidrome album opens - `albums`), nor
 *  for one nothing vouches for (the album's pressings are looked at first - app/Search.tsx). */
export function songAlbumHeldReleases(
  index: OwnedIndex | null | undefined,
  album: Pick<SongAlbum, 'id' | 'releases' | 'recordings'>,
  song: Pick<Song, 'title' | 'credit'> | null = null,
  evidence: SongEvidence = {},
): string[] {
  const ids = heldInOrder(songAlbumHolding(index, album, song, evidence).song).map((folder) => lower(folder.release_mbid))
  return [...new Set(ids.filter(Boolean))]
}

/** Where a held album is, in a line's words: "in your library", or - logins on, a library of your own,
 *  none of its folders yours - "in the store" (lib/whose.ts). '' when nothing is held. */
export function heldWords(held: readonly OwnedAlbum[], personal: boolean): string {
  return held.length ? heldPhrase(personal, anyYours(held)) : ''
}

/** Where a song's album is held, for its row under the song: heldWords for a pressing with the song; for only a
 *  pressing nothing says has it, "a pressing in your library" ("...in the store" - lib/whose.ts); '' for none. */
export function songAlbumWords(holding: Pick<SongHolding, 'song' | 'heard' | 'other'>, personal: boolean): string {
  const held = [...holding.song, ...holding.heard]
  if (held.length) return heldWords(held, personal)
  return holding.other.length ? pressingHeldPhrase(personal, anyYours(holding.other)) : ''
}

/** The album a song's row names: the first album you have the song on (one of yours before one only the
 *  store has - a pressing of an album nothing says has the song isn't having it), else the first it is on. */
export function namedAlbum(song: Pick<Song, 'albums' | 'title' | 'credit'>, index: OwnedIndex | null | undefined, evidence: SongEvidence = {}): { album: SongAlbum; held: OwnedAlbum[] } {
  let store: { album: SongAlbum; held: OwnedAlbum[] } | null = null
  for (const album of song.albums) {
    const held = songAlbumHeld(index, album, song, evidence)
    if (!held.length) continue
    if (anyYours(held)) return { album, held }
    store ??= { album, held }
  }
  return store ?? { album: song.albums[0]!, held: [] }
}

const length = (ms: number | null) => (ms === null ? '' : formatSeconds(Math.round(ms / 1000)))

/** A song row's second line: "Portishead · 4:56 · Dummy" - the album it names (namedAlbum) and its length
 *  there, then "in your library" ("in the store") when that album is held. */
export function songLine(song: Song, index: OwnedIndex | null | undefined, personal = false, evidence: SongEvidence = {}): string {
  const { album, held } = namedAlbum(song, index, evidence)
  return [song.credit, length(album.length), album.title, heldWords(held, personal)].filter(Boolean).join(' · ')
}

const yearOf = (date: string) => (/^\d{4}/.test(date) ? date.slice(0, 4) : '')

/**
 * An album row's line under a song: "Album · 1994", "Live album · Bootleg · 2008 · 6:06", "Compilation ·
 * Various Artists · 2015 · in your library" - its kind; its status unless Official; who it is credited to
 * when that isn't the song's credit; its year; the song's length on it when that is another version's
 * against the row's (lib/tracklistDiff.ts's rule); and where it is held - "a pressing in your library" when
 * nothing says whether what you hold of it has the song (songAlbumWords).
 */
export function songAlbumLine(album: SongAlbum, song: Song, index: OwnedIndex | null | undefined, personal = false, evidence: SongEvidence = {}): string {
  const rowLength = namedAlbum(song, index, evidence).album.length
  const other = album.length !== null && rowLength !== null
    && isOtherVersion(Math.round(album.length / 1000) - Math.round(rowLength / 1000), Math.round(rowLength / 1000))
  const status = album.status && album.status.toLowerCase() !== 'official' ? album.status : ''
  const credit = album.credit && album.credit !== song.credit ? album.credit : ''
  return [album.kind, status, credit, yearOf(album.date), other ? length(album.length) : '', songAlbumWords(songAlbumHolding(index, album, song, evidence), personal)]
    .filter(Boolean).join(' · ')
}

/**
 * What a More page of songs brought, in words (as morePageWords does for albums): new songs are said only
 * to VoiceOver (they are on the screen); a page that only added albums to the songs above says so; one
 * that brought nothing new says that.
 */
export function moreSongsWords(added: number, grown: number): { note: string | null; said: string } {
  if (added) return { note: null, said: `${added} more ${added === 1 ? 'song' : 'songs'} found` }
  if (grown) {
    const albums = `${grown} more ${grown === 1 ? 'album' : 'albums'}`
    return { note: `No new songs - ${albums} for the songs above.`, said: `No new songs - ${albums} for the songs above` }
  }
  return { note: 'No more results.', said: 'No more results' }
}

/* ===== the album opened from a song: its pressing, and the song in its tracklist ===== */

const MBID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/** A song's recordings as an album's address carries them (`?song=`): lowercase MusicBrainz ids, each
 *  once, at most SONG_IDS_KEPT - anything else in it dropped. */
export function songIds(value: string | readonly string[] | null | undefined): string[] {
  const parts = typeof value === 'string' ? value.split(',') : [...(value ?? [])]
  const ids: string[] = []
  for (const part of parts) {
    const id = lower(part)
    if (MBID.test(id) && !ids.includes(id)) ids.push(id)
    if (ids.length >= SONG_IDS_KEPT) break
  }
  return ids
}

/** A track as /search_musicbrainz/release_group's pressings carry it - with its recording's id. */
interface PressedSongTrack {
  title?: string
  recording?: { id?: string; title?: string }
}

const tracksOf = (release: PressingRelease): PressedSongTrack[] =>
  (release.media ?? []).flatMap((medium) => (medium.tracks ?? []) as PressedSongTrack[])

const isRecording = (track: PressedSongTrack, ids: ReadonlySet<string>) => ids.has(lower(track.recording?.id))

/**
 * Which tracks of an album are the song: a track of one of its recordings - or, since MusicBrainz often has
 * the same song as another recording on another pressing of the same album, one titled as a track of those
 * recordings is (the track's title or its recording's, folded by titleKey). Null when no pressing has one
 * of its recordings: nothing to know the song by.
 */
export function songMatcher(releases: readonly PressingRelease[], ids: readonly string[]): ((track: PressedSongTrack) => boolean) | null {
  const wanted = new Set(ids.map(lower))
  if (!wanted.size) return null
  const titles = new Set<string>()
  for (const release of releases) {
    for (const track of tracksOf(release)) {
      if (!isRecording(track, wanted)) continue
      for (const title of [track.title, track.recording?.title]) if (titleKey(title)) titles.add(titleKey(title))
    }
  }
  if (!titles.size) return null
  return (track) => isRecording(track, wanted) || titles.has(titleKey(track.title)) || titles.has(titleKey(track.recording?.title))
}

/**
 * The pressing an album opened from a song shows (null: the album's usual one, as the page would open
 * anyway): the usual pressing when it has the song; else the most usual of the pressings with one of the
 * song's recordings - the bonus-track case - else of those with a track of its title; the usual one when
 * none has it at all. representativeRelease picks, as it picks the album's default.
 */
export function songPressing<R extends PressingRelease & { id: string }>(releases: readonly R[], ids: readonly string[]): string | null {
  const matches = songMatcher(releases, ids)
  if (!matches) return null
  const usual = representativeRelease(releases) ?? releases[0] ?? null
  const has = (release: R) => tracksOf(release).some(matches)
  if (!usual || has(usual)) return null
  const wanted = new Set(ids.map(lower))
  const byRecording = releases.filter((release) => tracksOf(release).some((track) => isRecording(track, wanted)))
  const pool = byRecording.length ? byRecording : releases.filter(has)
  return pool.length ? (representativeRelease(pool) ?? pool[0]!).id : null
}
