import type { ReleaseGroup } from '../api/types'
import type { OwnedIndex } from '../lib/owned'
import { coverAddresses } from '../lib/pressings'
import { failureWords, foldWords, placeLabel, rowLine, type Kind, type LineContext, type Row } from '../lib/searchList'
import { groupHeld, songIndex } from '../lib/searchResults'
import {
  foldLabel, namedAlbum, songAlbumBands, songAlbumHeld, songAlbumLine, type Song as FoundSong, type SongAlbum, type SongEvidence,
} from '../lib/songs'
import type { Album, AlbumWithSongs, Artist, Song } from '../player/api'
import { dropPrefetch, prefetchAlbum } from '../player/api'
import { Cover } from '../player/Cover'
import { ChevronDownIcon, MoreIcon, PlayIcon } from '../player/icons'
import { ArchiveCover } from './ArchiveCover'

/**
 * Search's rows (2.0.0-player.55, "search like Apple Music") - stateless, called as FUNCTIONS by app/Search.tsx
 * (topRow, sectionRow, slot, head), never mounted as components, so search.sim's stand-in for Preact sees every
 * one of them. They never touch the player: a library song's tap calls `onPlay` - Search's playSong - in the
 * click, synchronously, and Search alone (the allowlist's one Search entry) calls playTracks from it (the gesture
 * rule; app-rules.sim.cjs pins that this file imports no player action).
 *
 *  - TOP RESULTS: on a phone today's `.app-result` rows, the kind word first on line 2 ("Song · Portishead ·
 *    Dummy") and the place in its own span; on a desktop (the frame the list was drawn in) Apple's tinted
 *    lockups, three lines - the title, the kind line, the place ("In your library", "In the store", "On
 *    MusicBrainz") - each one fixed height. The trailing control: ▶ on a song that plays, Get on what you can
 *    get, nothing on an artist or an album you have.
 *  - THE SECTIONS' ROWS: the facts without the kind word (the heading says it), then the place words in a span
 *    that never shrinks, so "in your library" is never cut at 320. MusicBrainz's song rows keep step 7's
 *    disclosure onto the albums they are on.
 *  - A SLOT: one fixed height for a late kind's answer - the sweep while it asks, then "Show 3 albums from
 *    MusicBrainz", why there are none, or its failure with Try again.
 *  - WHAT'S SAVED (2.0.0-player.56): a row from MusicBrainz's saved answers is MusicBrainz's row - drawn, tapped and
 *    got the same - its place saying "saved" (a tile's third line "Saved from MusicBrainz") unless it is held.
 *  - (2.0.0-player.57, Up Next) a library song's row ends with a ••• - `onSongMenu`, App's song menu (Play Next, Play
 *    Last) - in Top results (as rows, never on a desktop's lockup tile, which hasn't the room) and in Songs; it names no
 *    player action either.
 */

/** What every row needs: the marks, the live state of a Get or a look, and what a tap calls. */
export interface RowContext extends LineContext {
  index: OwnedIndex | null
  personal: boolean
  evidence: SongEvidence
  /** the albums of the songs found, once in hand: what lets a song's tap play */
  ready: ReadonlyMap<string, AlbumWithSongs>
  /** a Get's lookup out: a group's id, or a song's key and its album's id */
  resolving: string | null
  /** a row looking for the album you have: a group's id, or a song's key and its album's id */
  opening: string | null
  openSongs: ReadonlySet<string>
  openFolds: ReadonlySet<string>
  /** Search's playSong - called in the tap, nothing awaited */
  onPlay: (song: Song) => void
  /** (2.0.0-player.57) a library song's •••: App's song menu, Play Next and Play Last */
  onSongMenu: (song: Song, event: MouseEvent) => void
  onOpenAlbum: (album: Album) => void
  onOpenArtist: (artist: Artist) => void
  onOpenMusicBrainzArtist: (artist: { mbid: string; name: string }) => void
  /** a MusicBrainz album: the album you have when held (the id bridge), else the album you don't have */
  onOpenGroup: (group: ReleaseGroup) => void
  /** an album a song is on: the album you have the song on, else the album you don't have with the song marked */
  onOpenSongAlbum: (song: FoundSong, album: SongAlbum) => void
  /** (2.0.0-player.61) this person has Get albums: without it no row has Get (Search says why, once) */
  gets: boolean
  onGetGroup: (group: ReleaseGroup, event: MouseEvent) => void
  onGetSong: (song: FoundSong, album: SongAlbum, event: MouseEvent) => void
  onToggleSong: (key: string) => void
  onToggleFold: (key: string) => void
}

const SECTION_TITLES: Record<Kind, string> = { artists: 'Artists', albums: 'Albums', songs: 'Songs' }

/** A section's heading id - what its section is labelled by. */
export const sectionId = (kind: Kind) => `app-search-${kind}`

/** A row's cover: an artist's round (MusicBrainz's artists have no picture route - the round empty cover), a
 *  library album's or song's Navidrome cover, a MusicBrainz album's the Cover Art Archive's. */
function cover(row: Row, context: RowContext, size: number) {
  switch (row.type) {
    case 'artist':
      return <Cover id={row.artist.coverArt} size={size} class="app-result-cover is-round is-small" />
    case 'mb-artist':
      return <Cover id={null} size={size} class="app-result-cover is-round is-small" />
    case 'album':
      return <Cover id={row.album.coverArt} size={size} class="app-result-cover" />
    case 'song':
      return <Cover id={row.song.coverArt} size={size} class="app-result-cover" />
    case 'group':
      return <ArchiveCover addresses={coverAddresses(null, row.group.id, 250)} class="app-result-cover" />
    case 'mb-song':
      return <ArchiveCover addresses={coverAddresses(null, namedAlbum(row.song, context.index, context.evidence).album.id, 250)} class="app-result-cover" />
    case 'song-album':
      return <ArchiveCover addresses={coverAddresses(null, row.album.id, 250)} class="app-result-cover" />
  }
}

/** A row's title. */
function title(row: Row): string {
  switch (row.type) {
    case 'artist':
      return row.artist.name
    case 'mb-artist':
      return row.match.name
    case 'album':
      return row.album.name
    case 'group':
      return row.group.title ?? ''
    case 'song':
    case 'mb-song':
      return row.song.title
    case 'song-album':
      return row.album.title
  }
}

/** Whether a library song plays from its tap: its album's songs in hand, with it among them. */
const plays = (song: Song, context: RowContext) => !!song.albumId && songIndex(context.ready.get(song.albumId)?.song, song.id) >= 0

/** The album a MusicBrainz song's Get gets: the album its row names. Held with the song: no Get. */
function songGetAlbum(song: FoundSong, context: RowContext): SongAlbum | null {
  const { album, held } = namedAlbum(song, context.index, context.evidence)
  return held.length ? null : album
}

/** What a row's tap does - the gesture rule's one way to play is `onPlay`, called here synchronously. */
function tap(row: Row, context: RowContext, top: boolean): () => void {
  switch (row.type) {
    case 'artist':
      return () => context.onOpenArtist(row.artist)
    case 'mb-artist':
      return () => context.onOpenMusicBrainzArtist({ mbid: row.match.mbid, name: row.match.name })
    case 'album':
      return () => context.onOpenAlbum(row.album)
    case 'group':
      return () => context.onOpenGroup(row.group)
    case 'song':
      return () => context.onPlay(row.song)
    case 'mb-song':
      //? Top results go to the best guess - its named album, the song marked; Songs looks closer (the disclosure)
      return top ? () => context.onOpenSongAlbum(row.song, namedAlbum(row.song, context.index, context.evidence).album) : () => context.onToggleSong(row.song.key)
    case 'song-album':
      return () => context.onOpenSongAlbum(row.song, row.album)
  }
}

/** The key a row's busy look goes by (`opening`). */
function lookKey(row: Row, context: RowContext): string | null {
  if (row.type === 'group') return row.group.id
  if (row.type === 'song-album') return `${row.song.key}\n${row.album.id}`
  if (row.type === 'mb-song') return `${row.song.key}\n${namedAlbum(row.song, context.index, context.evidence).album.id}`
  return null
}

/** The trailing Get on a row MusicBrainz offers - none on anything held, nor for someone without Get albums. */
function getChip(row: Row, context: RowContext) {
  if (!context.gets) return null
  if (row.type === 'group') {
    if (groupHeld(context.index, row.group.id)) return null
    const asking = context.resolving === row.group.id
    return (
      <button
        type="button"
        class={`app-result-get${asking ? ' is-busy' : ''}`}
        aria-label={`Get ${row.group.title ?? 'this album'}`}
        aria-busy={asking}
        aria-disabled={asking}
        onClick={(event) => context.onGetGroup(row.group, event)}
      >
        {asking ? 'Getting…' : 'Get'}
      </button>
    )
  }
  const pair = row.type === 'mb-song' ? (() => { const album = songGetAlbum(row.song, context); return album ? { song: row.song, album } : null })()
    : row.type === 'song-album' ? (songAlbumHeld(context.index, row.album, row.song, context.evidence).length ? null : { song: row.song, album: row.album })
      : null
  if (!pair) return null
  const key = `${pair.song.key}\n${pair.album.id}`
  const asking = context.resolving === key
  return (
    <button
      type="button"
      class={`app-result-get${asking ? ' is-busy' : ''}`}
      aria-label={`Get ${pair.album.title || 'this album'}, with ${pair.song.title}`}
      aria-busy={asking}
      aria-disabled={asking}
      onClick={(event) => context.onGetSong(pair.song, pair.album, event)}
    >
      {asking ? 'Getting…' : 'Get'}
    </button>
  )
}

/** A library album's press asks for its songs as the finger lands, as a tile does - and a scroll lets go. */
const press = (row: Row) => (row.type === 'album'
  ? { onPointerDown: () => void prefetchAlbum(row.album.id), onPointerCancel: () => dropPrefetch(row.album.id) }
  : {})

/** (2.0.0-player.57) A library song's •••: the song menu - Play Next, Play Last. Nothing else has one. */
function songMore(row: Row, context: RowContext) {
  if (row.type !== 'song') return null
  const { song } = row
  return (
    <button
      type="button"
      class="app-row-more"
      aria-label={`More for ${song.title}`}
      aria-haspopup="dialog"
      onClick={(event) => context.onSongMenu(song, event as unknown as MouseEvent)}
    >
      <MoreIcon class="app-row-more-icon" />
    </button>
  )
}

/** ▶ on a library song that will play, and the words saying which it will do. */
function playMark(row: Row, context: RowContext) {
  if (row.type !== 'song') return null
  const will = plays(row.song, context)
  return (
    <>
      {will ? <PlayIcon class="app-result-play" /> : null}
      <span class="app-visually-hidden">{will ? ', plays it from its album' : ', opens its album'}</span>
    </>
  )
}

/**
 * A Top result: on a phone a row - the title, then the kind word and the facts, the place in its own span; on a
 * desktop (`tile`) a lockup of three lines - the title, the kind line, the place - one fixed height.
 */
export function topRow(row: Row, context: RowContext, tile: boolean) {
  const { line, place } = rowLine(row, context, true)
  const busy = lookKey(row, context)
  const looking = !!busy && context.opening === busy
  const get = getChip(row, context)
  const button = (
    <button
      type="button"
      class={`app-result${tile ? ' app-top-lockup' : ''}${looking ? ' is-busy' : ''}`}
      data-row={`top:${row.key}`}
      aria-busy={looking}
      onClick={tap(row, context, true)}
      {...press(row)}
    >
      {cover(row, context, tile ? 112 : 96)}
      <span class="app-result-text">
        <span class="app-result-title" dir="auto">{title(row)}</span>
        {tile ? (
          <>
            <span class="app-result-line">{line}</span>
            {/* (2.0.6, review) beside a Get a tile's text has ~60px: "Not in your library" was cut to "Not in y…".
                The Get already says it isn't here, so a tile with one leaves its third line empty (its height kept);
                the section row below, and the album's page, say "maybe" where a folder may hold it */}
            <span class="app-result-line app-top-place">{get ? '' : placeLabel(row, context.marks, context.evidence)}</span>
          </>
        ) : (
          <span class="app-result-line app-result-split">
            <span class="app-result-facts">{line}</span>
            {place ? <span class="app-result-place">{`${line ? ' · ' : ''}${place}`}</span> : null}
          </span>
        )}
      </span>
      {playMark(row, context)}
    </button>
  )
  //? not on a desktop's lockup tile: its text would have ~40 px left beside the cover and the ▶ - the same song's row
  //? in Songs below carries the •••
  const more = tile ? null : songMore(row, context)
  return (
    <li key={`top:${row.key}`} class={[get || more ? 'app-result-row' : '', tile ? 'app-top-tile' : ''].filter(Boolean).join(' ') || undefined}>
      {button}
      {get}
      {more}
    </li>
  )
}

/** Top results' place for what is still to come: one row (a tile on a desktop) high, the sweep and no words -
 *  hidden from a screen reader, not focusable. */
export function topPlace(tile: boolean) {
  return (
    <li key="top-place" class={`app-search-top-place${tile ? ' app-top-tile' : ''}`} aria-hidden="true">
      <span class="app-sweep" />
    </li>
  )
}

/** A MusicBrainz song in the Songs section: its row a disclosure onto the albums it is on (step 7) - Albums, EPs and
 *  Singles listed, the rest under one fold that opens - and Get for the album it names. */
function songDisclosure(row: Extract<Row, { type: 'mb-song' }>, context: RowContext, index: number) {
  const song = row.song
  const open = context.openSongs.has(song.key)
  const { listed, folded } = songAlbumBands(song)
  const foldOpen = !listed.length || context.openFolds.has(song.key)
  const id = `app-song-albums-${index}`
  const { line, place } = rowLine(row, context)
  const get = getChip(row, context)
  const albumRow = (album: SongAlbum) => {
    const key = `${song.key}\n${album.id}`
    return (
      <li key={album.id}>
        <button type="button" class={`app-result app-song-album${context.opening === key ? ' is-busy' : ''}`} aria-busy={context.opening === key}
          onClick={() => context.onOpenSongAlbum(song, album)}>
          <ArchiveCover addresses={coverAddresses(null, album.id, 250)} class="app-result-cover" />
          <span class="app-result-text">
            <span class="app-result-title" dir="auto">{album.title}</span>
            <span class="app-result-line">{songAlbumLine(album, song, context.index, context.personal, context.evidence)}</span>
          </span>
        </button>
      </li>
    )
  }
  return (
    <li key={row.key} class="app-song">
      <div class={get ? 'app-result-row' : undefined}>
        <button type="button" class="app-result app-song-row" data-row={row.key} aria-expanded={open} aria-controls={id} onClick={() => context.onToggleSong(song.key)}>
          {cover(row, context, 96)}
          <span class="app-result-text">
            <span class="app-result-title" dir="auto">{song.title}</span>
            <span class="app-result-line app-result-split">
              <span class="app-result-facts">{line}</span>
              {place ? <span class="app-result-place">{`${line ? ' · ' : ''}${place}`}</span> : null}
            </span>
          </span>
          <ChevronDownIcon class="app-song-chevron" />
        </button>
        {get}
      </div>
      <div id={id} class="app-song-albums" hidden={!open}>
        {open && (
          <>
            {listed.length > 0 && <ul class="app-song-list">{listed.map(albumRow)}</ul>}
            {folded.length > 0 && (listed.length > 0 ? (
              <button type="button" class="app-text-button app-song-fold" aria-expanded={foldOpen} aria-controls={`${id}-fold`} onClick={() => context.onToggleFold(song.key)}>
                {foldLabel(folded)}
              </button>
            ) : (
              //? nothing else to list: the fold's words as its caption, its albums listed at once
              <p class="app-song-caption">{foldLabel(folded)}</p>
            ))}
            {folded.length > 0 && (
              <ul id={`${id}-fold`} class="app-song-list" hidden={!foldOpen}>
                {foldOpen && folded.map(albumRow)}
              </ul>
            )}
          </>
        )}
      </div>
    </li>
  )
}

/** A section's row: the facts without the kind word, the place in its own span; Get on what MusicBrainz offers. */
export function sectionRow(row: Row, context: RowContext, index: number) {
  if (row.type === 'mb-song') return songDisclosure(row, context, index)
  const { line, place } = rowLine(row, context)
  const busy = lookKey(row, context)
  const looking = !!busy && context.opening === busy
  const get = getChip(row, context)
  const more = songMore(row, context)
  return (
    <li key={row.key} class={get || more ? 'app-result-row' : undefined}>
      <button
        type="button"
        class={`app-result${looking ? ' is-busy' : ''}`}
        data-row={row.key}
        aria-busy={looking}
        onClick={tap(row, context, false)}
        {...press(row)}
      >
        {cover(row, context, 96)}
        <span class="app-result-text">
          <span class="app-result-title" dir="auto">{title(row)}</span>
          {line || place ? (
            <span class="app-result-line app-result-split">
              <span class="app-result-facts">{line}</span>
              {place ? <span class="app-result-place">{`${line ? ' · ' : ''}${place}`}</span> : null}
            </span>
          ) : null}
        </span>
        {playMark(row, context)}
      </button>
      {get}
      {more}
    </li>
  )
}

/** A section's head: its heading (focusable from code, no ring on words) and See all, always drawn in All. */
export function head(kind: Kind, onSeeAll: ((event: MouseEvent) => void) | null) {
  return (
    <div class="app-search-head">
      <h2 id={sectionId(kind)} class="app-section-title app-search-title" tabIndex={-1}>{SECTION_TITLES[kind]}</h2>
      {onSeeAll && (
        <button type="button" class="app-text-button app-search-see-all" aria-label={`See all ${kind}`} onClick={onSeeAll}>
          See all
        </button>
      )}
    </div>
  )
}

/** A late kind's slot, as it stands: still asking; folded ("Show 3 albums from MusicBrainz"); why there is nothing;
 *  its failure - one line, with Try again unless MusicBrainz refused the words. One fixed height whatever it holds. */
export type SlotState =
  | { state: 'asking'; words?: string }
  | { state: 'show'; kind: Kind; count: number; onShow: (event: MouseEvent) => void; words?: string }
  | { state: 'said'; words: string }
  //? `words`: said instead of the failure's own (2.0.0-player.56: under what's saved, that these are saved)
  | { state: 'failed'; failure: { refused: boolean; busy: boolean; message: string; unavailable: boolean }; onRetry: (event: MouseEvent) => void; words?: string }
  | { state: 'button'; words: string; onPress: (event: MouseEvent) => void }

export function slot(state: SlotState, key: string) {
  switch (state.state) {
    case 'asking':
      return (
        <div key={key} class="app-search-slot">
          <div class="app-asking">
            <span class="app-sweep" aria-hidden="true" />
            <span class="app-asking-text">{state.words ?? 'Searching…'}</span>
          </div>
        </div>
      )
    case 'show':
      return (
        <div key={key} class="app-search-slot">
          <button type="button" class="app-button app-search-show" onClick={state.onShow}>{state.words ?? foldWords(state.kind, state.count).button}</button>
        </div>
      )
    case 'button':
      return (
        <div key={key} class="app-search-slot">
          <button type="button" class="app-button app-search-show" onClick={state.onPress}>{state.words}</button>
        </div>
      )
    case 'said':
      return (
        <div key={key} class="app-search-slot">
          <p class="app-search-empty">{state.words}</p>
        </div>
      )
    case 'failed':
      return (
        <div key={key} class="app-search-slot is-row">
          <p class="app-search-empty">{state.words ?? failureWords(state.failure, true)}</p>
          {!state.failure.refused && (
            <button type="button" class="app-text-button" onClick={state.onRetry}>
              Try again
            </button>
          )}
        </div>
      )
  }
}

