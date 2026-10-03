/**
 * Pins (2.0.0-player.18), in the app: which pin is the album or artist on screen, what a card on
 * Home says, and Home's Edit - pure, pinned by ui/test/pins.sim.cjs.
 *
 * The server holds them (src/routes/pins.py, the rules in src/pins.py) - deadwax's OWN, never
 * Navidrome's stars. An album pin keys on the store index's row (`store:<store_album.id>`, which
 * follows the album through a re-file or a merge; `release:<mbid>` until the index holds it), an
 * artist pin on their MusicBrainz id (`mb:<mbid>`) or their folded name (`name:...`). Every answer is
 * the whole list as it is now: each album pin with its state, Navidrome's id to open it with (checked
 * by the server), and its release; each artist pin with their MusicBrainz id, when it keys on one.
 *
 * What changes them (app/usePins.ts) is laid over the server's last word as an operation (PinOp) -
 * shown at once, and sent in turn: a pin and an unpin by WHAT it is (the server matches as isPinOf
 * does), a move and a removal by key, the PUT's whole list made from the server's word as it stands
 * when it goes - with that word's own list beside it (`known`), so a pin made on another device since
 * keeps its place rather than being unpinned unseen.
 */

export type PinKind = 'album' | 'artist'

/** An album pin: present; missing - its folder not there just now; gone - deadwax deleted it. An
 *  artist pin is always present. */
export type PinState = 'present' | 'missing' | 'gone'

export interface Pin {
  kind: PinKind
  ref: string
  /** the album's title, or the artist's name */
  label: string
  /** an album's artist ('' for an artist) */
  sub: string
  state: PinState
  /** Navidrome's album or artist id to open it by - null for an album that can't be opened now */
  navidrome_id: string | null
  /** Navidrome's cover id for its picture */
  cover: string | null
  /** an album pin's release, as the store holds it now */
  release_mbid?: string | null
  /** an artist pin's MusicBrainz id, when it keys on one */
  mbid?: string | null
  /** made on this page and not answered yet: drawn at once, not yet editable */
  pending?: boolean
}

export interface PinsAnswer {
  pins: Pin[]
  /** false when deadwax's database can't keep them */
  can_save: boolean
}

/** An album, as the page showing it knows it: its release (the id bridge's), Navidrome's id. */
export interface AlbumPinTarget {
  kind: 'album'
  release_mbid: string | null
  navidrome_id: string | null
  label: string
  sub: string
  cover: string | null
}

/** An artist, as their page knows them: their MusicBrainz id, Navidrome's id, their name. */
export interface ArtistPinTarget {
  kind: 'artist'
  mbid: string | null
  navidrome_id: string | null
  name: string
  cover: string | null
}

export type PinTarget = AlbumPinTarget | ArtistPinTarget

/** What a card says under its name, where it doesn't say the album's artist - short enough to read
 *  whole in two lines of a phone's card (a closed card gives them two; see app.css's pins). */
export const PIN_WORDS = {
  artist: 'Artist',
  gone: 'Removed from the store',
  missing: 'Not on disk just now',
  unfound: 'Not in Navidrome yet',
} as const

/** The longest name, sub-line or name a toggle may send - src/pins.py's LABEL_MAX. */
export const LABEL_MAX = 256

export function pinKey(pin: Pick<Pin, 'kind' | 'ref'>): string {
  return `${pin.kind}:${pin.ref}`
}

/** How src/artists.py's `_fold` spells the typography nobody means as a difference. */
const TYPOGRAPHY: Record<string, string> = {
  '\u2010': '-', '\u2011': '-', '\u2012': '-', '\u2013': '-', '\u2014': '-', '\u2015': '-', '\u2212': '-',
  '\u2018': "'", '\u2019': "'", '\u02bc': "'", '\u00b4': "'", '\u0060': "'", '\u201c': '"', '\u201d': '"', '\u00a0': ' ',
}
const TYPOGRAPHY_CHARS = new RegExp(`[${Object.keys(TYPOGRAPHY).join('')}]`, 'g')

/**
 * An artist's name as a `name:` pin keys on it - src/artists.py's `_fold`, which the server's
 * artist_ref folds with: accents and how a dash or a quote was typed fold away, case folds (ß as ss,
 * a final sigma as any other), runs of space are one. tests/fixtures/name_folds.json is what both
 * answer - test_pins.py holds the server to it and pins.sim.cjs this.
 */
export function foldArtistName(name: string | null | undefined): string {
  return String(name ?? '')
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .replace(TYPOGRAPHY_CHARS, (char) => TYPOGRAPHY[char] ?? char)
    .toLowerCase()
    .replace(/\u00df/g, 'ss')
    .replace(/\u03c2/g, '\u03c3')
    .split(/\s+/)
    .filter(Boolean)
    .join(' ')
}

/**
 * Whether a pin is of this album or artist - as the server's toggle matches them (`same` in
 * src/routes/pins.py), so what the page shows pinned is what an unpin removes. An album by its
 * release; where either side has none to say, by Navidrome's id. An artist by MusicBrainz id where
 * both have one; with none on the page's side, by the pin's `name:` ref - the name folded as the
 * server folds it, so "Björk" and "Bjork" are one pin, as the table's key makes them - and otherwise
 * by Navidrome's id (a pin made by name always has one).
 */
export function isPinOf(pin: Pin, target: PinTarget): boolean {
  if (pin.kind !== target.kind) return false
  if (target.kind === 'album') {
    const release = pin.release_mbid ?? null
    if (release && target.release_mbid) return release === target.release_mbid
    return !!target.navidrome_id && pin.navidrome_id === target.navidrome_id
  }
  const mbid = pin.mbid ?? null
  if (mbid && target.mbid) return mbid === target.mbid
  if (!target.mbid) {
    const folded = foldArtistName(target.name.trim().slice(0, LABEL_MAX))
    if (folded && pin.ref === `name:${folded}`) return true
  }
  return !!target.navidrome_id && pin.navidrome_id === target.navidrome_id
}

/** What a toggle's notice calls the thing: the album's title, or the artist's name. */
export function targetName(target: PinTarget): string {
  return (target.kind === 'album' ? target.label : target.name).trim() || (target.kind === 'album' ? 'the album' : 'the artist')
}

/** The pin of this album or artist, if it is pinned. */
export function pinOf(pins: readonly Pin[] | null | undefined, target: PinTarget | null): Pin | null {
  if (!pins || !target) return null
  return pins.find((pin) => isPinOf(pin, target)) ?? null
}

/** Whether a card opens anything: an album present with Navidrome's id, an artist known either way. */
export function pinOpens(pin: Pin): boolean {
  if (pin.kind === 'artist') return !!(pin.navidrome_id || pin.mbid)
  return pin.state === 'present' && !!pin.navidrome_id
}

/** The line under a card's name: "Artist", the album's artist - or why the album won't open. */
export function pinLine(pin: Pin): string {
  if (pin.kind === 'artist') return PIN_WORDS.artist
  if (pin.state === 'gone') return PIN_WORDS.gone
  if (pin.state === 'missing') return PIN_WORDS.missing
  if (!pin.navidrome_id) return PIN_WORDS.unfound
  return pin.sub
}

/** A pin made on this page, drawn until the server answers for it. */
export function pendingPin(target: PinTarget, ref: string): Pin {
  return target.kind === 'album'
    ? { kind: 'album', ref, label: target.label, sub: target.sub, state: 'present', navidrome_id: target.navidrome_id,
        cover: target.cover, release_mbid: target.release_mbid, pending: true }
    : { kind: 'artist', ref, label: target.name, sub: '', state: 'present', navidrome_id: target.navidrome_id,
        cover: target.cover, mbid: target.mbid, pending: true }
}

/** What changes the pins, laid over the server's word until it answers (app/usePins.ts). */
export type PinOp =
  | { type: 'pin'; target: PinTarget; ref: string }
  | { type: 'unpin'; target: PinTarget }
  | { type: 'move'; key: string; to: number }
  | { type: 'remove'; key: string }

/** `list` with the item at `from` moved to `to` (each clamped into the list). */
export function moveTo<T>(list: readonly T[], from: number, to: number): T[] {
  const moved = list.slice()
  if (from < 0 || from >= moved.length) return moved
  const [item] = moved.splice(from, 1)
  moved.splice(Math.max(0, Math.min(to, moved.length)), 0, item as T)
  return moved
}

/** The pins with one change laid over them. A new pin goes FIRST, as the server puts it. */
export function applyPinOp(pins: readonly Pin[], op: PinOp): Pin[] {
  switch (op.type) {
    case 'pin':
      return pinOf(pins, op.target) ? pins.slice() : [pendingPin(op.target, op.ref), ...pins]
    case 'unpin':
      return pins.filter((pin) => !isPinOf(pin, op.target))
    case 'move':
      return moveTo(pins, pins.findIndex((pin) => pinKey(pin) === op.key), op.to)
    case 'remove':
      return pins.filter((pin) => pinKey(pin) !== op.key)
  }
}

/** Where a row dragged `dy` px from place `start` lands, rows `pitch` px apart, in a list of `count`. */
export function dropIndex(start: number, dy: number, pitch: number, count: number): number {
  if (!(pitch > 0) || count < 1) return start
  return Math.max(0, Math.min(count - 1, start + Math.round(dy / pitch)))
}

/**
 * How far the row at `index` is drawn from its place while the row from `start` is dragged `dy` px
 * and would land at `landing`: the dragged row follows the finger, and the rows it has passed make
 * way - up a row when it goes down past them, down a row when it goes up past them. The list's own
 * order doesn't change until the drag ends.
 */
export function dragOffset(index: number, start: number, landing: number, dy: number, pitch: number): number {
  if (index === start) return dy
  if (start < landing && index > start && index <= landing) return -pitch
  if (landing < start && index >= landing && index < start) return pitch
  return 0
}

type PinRefBody = { kind: PinKind; ref: string }
const refsOf = (pins: readonly Pin[]): PinRefBody[] =>
  pins.filter((pin) => !pin.pending).map((pin) => ({ kind: pin.kind, ref: pin.ref }))

/**
 * A PUT's body: the whole ordered list, by kind and ref - never a pin the server hasn't made yet -
 * and, given the server's word it was made from, `known`: every pin that word held. The server
 * leaves a pin it holds and the page was never told of (pinned on another device since) where it is.
 */
export function orderBody(pins: readonly Pin[], made?: readonly Pin[]): { pins: PinRefBody[]; known?: PinRefBody[] } {
  return made ? { pins: refsOf(pins), known: refsOf(made) } : { pins: refsOf(pins) }
}

/** What a toggle sends: what the thing is, whether it should end up pinned, and - to pin - its card. */
export type PinToggleBody = { kind: PinKind; pinned: boolean } & Record<string, string | boolean>

export function toggleBody(target: PinTarget, pinned: boolean): PinToggleBody {
  const body: PinToggleBody = { kind: target.kind, pinned }
  const put = (name: string, value: string | null | undefined) => {
    const trimmed = (value ?? '').trim().slice(0, LABEL_MAX)
    if (trimmed) body[name] = trimmed
  }
  put('navidrome_id', target.navidrome_id)
  if (target.kind === 'album') {
    put('release_mbid', target.release_mbid)
    if (pinned) {
      put('label', target.label)
      put('sub', target.sub)
      put('cover', target.cover)
    }
  } else {
    put('mbid', target.mbid)
    put('name', target.name)
    if (pinned) put('cover', target.cover)
  }
  return body
}
