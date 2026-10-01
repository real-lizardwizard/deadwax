/**
 * The app's one search box as a MusicBrainz query (2.0.0-player.13). Pure, pinned by
 * ui/test/searchQuery.sim.cjs.
 *
 * James: "One search box: library first, then MusicBrainz". The main page has two boxes, artist
 * and title, and builds a fielded query from them (main.js handleSearch); the app has one, so it
 * has to tell the two apart itself. It does that with what the library already knows - the names
 * of the artists you have - and nothing cleverer:
 *
 *  - The box STARTS or ENDS with an artist you have: the rest is the album's title, and the query
 *    is `releasegroup:"rest" AND (artist:"A" OR artistname:"A")` - the metadata editor's fielded
 *    query (fieldedAlbumQuery in lib/release.ts), which finds the album whether it was credited to
 *    the artist's name then or now. "portishead third" is Third by Portishead; so is "third
 *    portishead". The longest name that fits wins ("Pink Floyd" over a "Pink" you also have).
 *  - The box IS an artist you have: `artist:"A"`.
 *  - Anything else goes as free text, as the main page sends a title typed alone.
 *  - `va` (and "various artists") is Various Artists, as the main page's artist box reads it.
 *
 * A dash, colon or slash between the artist and the title ("portishead - third") is dropped.
 *
 * THE QUERY IS PARENTHESISED BEFORE A TYPE FILTER IS ANDED ON - CLAUDE.md's search type filter
 * decision. Free text is bare words, and without the brackets `AND` binds to the last word alone,
 * quietly turning "dark side of the moon" into something nobody typed. The app draws no filter yet,
 * so it sends none; the rule is here, and pinned, for the screen that adds one.
 *
 * PACING (the plan's 2.4): the library half asks Navidrome LIBRARY_SETTLE_MS after typing stops;
 * MusicBrainz, which allows about one request a second and spends the whole budget on any search
 * sent, is asked on Enter, or MUSICBRAINZ_SETTLE_MS after typing stops with at least
 * MUSICBRAINZ_MIN_CHARS characters. A box cut back below that, to something not already asked,
 * drops what MusicBrainz found for the longer text (musicBrainzOnTyping): nothing would ever
 * replace it, and "U2" over Portishead's albums reads as MusicBrainz's answer to "U2" (review).
 *
 * The box holds at most SEARCH_MAX_CHARS - the bound deadwax's /navidrome/search declares, so a
 * paste can't become a 422 that reads as a URL with a Try again that can never work (review).
 */

import { fieldedAlbumQuery } from './release'
import { foldName } from './owned'

export const LIBRARY_SETTLE_MS = 200
export const MUSICBRAINZ_SETTLE_MS = 700
export const MUSICBRAINZ_MIN_CHARS = 3
/** The most the box holds: `q`'s bound on deadwax's /navidrome/search (src/routes/navidrome.py). */
export const SEARCH_MAX_CHARS = 200

export const VARIOUS_ARTISTS = 'Various Artists'

/** How the box was read, and what is sent for it. */
export interface SearchPlan {
  /** MusicBrainz's `query` */
  query: string
  kind: 'album-by-artist' | 'artist' | 'free'
  /** the artist it was read as, in the library's spelling; null for free text */
  artist: string | null
  /** the album title it was read as; null unless `album-by-artist` */
  title: string | null
}

/** A term in double quotes, its backslashes and quotes escaped - the editor's quoting. */
export function quoteTerm(text: string): string {
  return `"${text.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`
}

/** Secondary types "studio only" leaves out, BY NAME - the main page's list (main.js). */
export const NOISY_SECONDARY_TYPES = ['Live', 'Compilation', 'Interview', 'Demo', 'Remix', 'DJ-mix'] as const

/**
 * The type clauses to AND onto a search, or '' for none - main.js's buildTypeFilter: primary types
 * OR'd together in their own brackets, then each noisy secondary type excluded by name.
 */
export function typeFilter({ primary = [], studioOnly = false }: { primary?: readonly string[]; studioOnly?: boolean }): string {
  const clauses: string[] = []
  if (primary.length) {
    const types = primary.map((type) => `primarytype:${quoteTerm(type)}`)
    clauses.push(types.length > 1 ? `(${types.join(' OR ')})` : types[0]!)
  }
  if (studioOnly) for (const type of NOISY_SECONDARY_TYPES) clauses.push(`-secondarytype:${quoteTerm(type)}`)
  return clauses.join(' AND ')
}

/** A query with a type filter ANDed on - the query always in brackets first. */
export function withTypeFilter(query: string, filter: string): string {
  return filter ? `(${query}) AND ${filter}` : query
}

//? a word that only separates an artist from a title
const SEPARATOR = /^[-–—:/|·•]+$/

/** The artists the box may name, by folded name: the library's own, and Various Artists. */
export function artistNames(artists: readonly (string | null | undefined)[]): Map<string, string> {
  const names = new Map<string, string>()
  for (const artist of artists) {
    const name = (artist ?? '').trim()
    const key = foldName(name)
    if (key && !names.has(key)) names.set(key, name)
  }
  for (const alias of ['va', 'various artists']) if (!names.has(alias)) names.set(alias, VARIOUS_ARTISTS)
  return names
}

const strip = (words: string[]): string[] => {
  let start = 0
  let end = words.length
  while (start < end && SEPARATOR.test(words[start]!)) start++
  while (end > start && SEPARATOR.test(words[end - 1]!)) end--
  return words.slice(start, end)
}

/**
 * The box as MusicBrainz should be asked - null when it holds nothing. `artists` are the library's
 * artist names (what /library/owned and Navidrome have); `filter` a typeFilter() clause, or ''.
 */
export function searchQuery(
  text: string,
  artists: readonly (string | null | undefined)[] | ReadonlyMap<string, string>,
  filter = '',
): SearchPlan | null {
  const words = text.trim().split(/\s+/).filter(Boolean)
  if (!words.length) return null
  const names = artists instanceof Map ? artists : artistNames(artists as readonly (string | null | undefined)[])
  const named = (part: readonly string[]) => names.get(foldName(part.join(' '))) ?? null

  const plan = (query: string, kind: SearchPlan['kind'], artist: string | null, title: string | null): SearchPlan =>
    ({ query: withTypeFilter(query, filter), kind, artist, title })

  const whole = named(words)
  if (whole) return plan(`artist:${quoteTerm(whole)}`, 'artist', whole, null)

  //? the longest name first, at either end; at one length, the start before the end
  for (let length = words.length - 1; length >= 1; length--) {
    const leading = named(words.slice(0, length))
    const leadingRest = strip(words.slice(length))
    if (leading && leadingRest.length) {
      const title = leadingRest.join(' ')
      return plan(fieldedAlbumQuery(title, leading), 'album-by-artist', leading, title)
    }
    const trailing = named(words.slice(words.length - length))
    const trailingRest = strip(words.slice(0, words.length - length))
    if (trailing && trailingRest.length) {
      const title = trailingRest.join(' ')
      return plan(fieldedAlbumQuery(title, trailing), 'album-by-artist', trailing, title)
    }
  }

  return plan(words.join(' '), 'free', null, null)
}

/** Whether the box has waited long enough, and holds enough, to ask MusicBrainz without an Enter. */
export function asksMusicBrainzBySettling(text: string): boolean {
  return text.trim().length >= MUSICBRAINZ_MIN_CHARS
}

/**
 * What the MusicBrainz half does as the box changes, given what it last asked (`asked`, null for
 * nothing):
 *  - 'clear': the box is empty - both halves called off and cleared (Search does the library's);
 *  - 'settle': long enough to ask by itself - asked MUSICBRAINZ_SETTLE_MS after typing stops;
 *  - 'drop': too short to ask by itself, and not what was asked - the longer text's answer, or its
 *    search still out, is dropped and the half goes back to saying how to ask;
 *  - 'keep': the box says exactly what was asked (Search pressed on it) - its answer stands.
 */
export function musicBrainzOnTyping(text: string, asked: string | null): 'clear' | 'settle' | 'drop' | 'keep' {
  const query = text.trim()
  if (!query) return 'clear'
  if (query === asked) return 'keep'
  return asksMusicBrainzBySettling(query) ? 'settle' : 'drop'
}
