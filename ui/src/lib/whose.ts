/**
 * "In your library" meaning YOURS (2.0.0-player.52, step 6 of the multi-user plan) - pure, pinned by
 * ui/test/whose.sim.cjs.
 *
 * With logins on, and for somebody with a library of their own (signed in through Navidrome - not the
 * break-glass admin): your library is your starred albums, and the store is everything deadwax holds. So an
 * album the store has that isn't yours reads as "in the store", never "in your library" - anywhere the app
 * says it: an album page's line and pressing picker, Search's rows, the artist page, "You also have another
 * pressing", Info. What says whose an album is:
 *
 *  - deadwax's own record of your library (/library/owned's and the id bridge's `yours`, the store line's):
 *    the albums your ledger holds, waiting to be starred or starred;
 *  - and, for an album as Navidrome answers it (asked AS YOU), its `starred` - starred by you, in deadwax or
 *    Amperfy, before deadwax has read it back.
 *
 * `personal` false - logins off, or the break-glass admin - is how deadwax always was: the store IS your
 * library, and every word here is what it always said. A `yours` the server left out (it couldn't read your
 * library) reads the same way: never "not yours" on a guess.
 */

import { ownedForRelease, type OwnedAlbum, type OwnedIndex } from './owned'

export const IN_YOUR_LIBRARY = 'in your library'
//? (2.0.5, UX batch 2) the shared music on the server is "the collection" in a sentence - "All music" as a heading
//? (James's word) - never "the store", which read as a shop beside Get
export const IN_THE_STORE = 'in the collection'

/** Whether an album the store holds is yours - `yours` as the server said it; anything but false is. */
export function isYours(album: { yours?: boolean | null } | null | undefined): boolean {
  return album?.yours !== false
}

/** Whether any of these folders - one album's, or one pressing's - is yours. */
export function anyYours(albums: readonly { yours?: boolean | null }[]): boolean {
  return albums.some(isYours)
}

/** What an album the store holds is to you, in a line's words: "in your library", or with a library of your
 *  own and it not yours, "in the store". */
export function heldPhrase(personal: boolean, yours: boolean | null | undefined): string {
  return personal && yours === false ? IN_THE_STORE : IN_YOUR_LIBRARY
}

/** The same, as a label's words: "In your library" / "In the collection". */
export function heldLabel(personal: boolean, yours: boolean | null | undefined): string {
  const phrase = heldPhrase(personal, yours)
  return phrase.charAt(0).toUpperCase() + phrase.slice(1)
}

/** The album you don't have's meta line, with a library of your own, when the pressing on screen is held by
 *  the store but isn't yours while another pressing of the album is (review): the line speaks of the album, the
 *  store line under Get of the pressing - and a bare "in your library" over "In the store, not in your library"
 *  read as a contradiction. */
export const ANOTHER_PRESSING_YOURS = 'another pressing in your library'

/** A pressing of an album is held, and nothing says whether it is one the line is about (2.0.0-player.53: a
 *  song's album under the song in Search, when what the store holds of it is a pressing neither the recording
 *  search, the library's own search nor the album's pressings say has the song - the bonus-track case, or the
 *  song kept as another recording there): "a pressing in your library", or with a library of your own and none
 *  of them yours, "a pressing in the store" - never "another", which read as a pressing WITHOUT the song
 *  (second review). */
export function pressingHeldPhrase(personal: boolean, yours: boolean | null | undefined): string {
  return `a pressing ${heldPhrase(personal, yours)}`
}

const releaseOf = (album: { release_mbid?: string | null }) => (album.release_mbid ?? '').trim().toLowerCase()

/**
 * Where the album you don't have is, for its meta line (2.0.0-player.52): the folders the store holds of the
 * album (`holding` - by the group's id or any pressing's) and the pressing on screen. With logins off "in your
 * library", as ever; with a library of your own "in the store" when none of them is yours - and when one is,
 * "in your library", unless the pressing on screen is held and isn't yours: "another pressing in your
 * library" then, so the line never says "in your library" over a store line saying "In the store, not in your
 * library" (review - a pressing of each, one yours, the store's chosen).
 */
export function groupPagePlace(
  personal: boolean,
  holding: readonly { release_mbid?: string | null; yours?: boolean | null }[],
  chosenId: string | null | undefined,
): string {
  if (!personal || !anyYours(holding)) return heldPhrase(personal, anyYours(holding))
  const id = (chosenId ?? '').trim().toLowerCase()
  const chosen = id ? holding.filter((album) => releaseOf(album) === id) : []
  return chosen.length && !anyYours(chosen) ? ANOTHER_PRESSING_YOURS : IN_YOUR_LIBRARY
}

/** Where a count of an artist's albums Navidrome made lives: with a library of your own it counted the
 *  store's (Navidrome lists the store, whoever asks), so "in the store"; with logins off, "in your library". */
export function storeCountPlace(personal: boolean): string {
  return personal ? IN_THE_STORE : IN_YOUR_LIBRARY
}

/**
 * The folders the store holds of an album, with whose each is as the line under Get last said it (second
 * review). That line is asked afresh every time the album you don't have shows, while /library/owned's answer
 * is kept for the app's life - and whose an album is moves outside the tab (an unstar in Amperfy read back, a
 * Remove on another device), so the meta line read the kept answer's "in your library" over the fresh line's
 * "In the store, not in your library". The folders of the pressing the line is about (`held` - yours when any
 * of them is, the line's own rule) and of each other pressing it names take its word; the rest, and every
 * folder it says nothing of (logins off, the ledger unread: no `yours`), keep the library's.
 */
export function withStoreLine<T extends { path: string; yours?: boolean | null }>(
  holding: readonly T[],
  said: {
    held?: { paths?: readonly string[] | null; yours?: boolean } | null
    other_pressings?: readonly { path: string; yours?: boolean }[] | null
  } | null | undefined,
): T[] {
  const word = new Map<string, boolean>()
  for (const pressing of said?.other_pressings ?? []) if (typeof pressing.yours === 'boolean') word.set(pressing.path, pressing.yours)
  const held = said?.held
  if (held && typeof held.yours === 'boolean') for (const path of held.paths ?? []) word.set(path, held.yours)
  return holding.map((album) => {
    const yours = word.get(album.path)
    return yours === undefined || yours === album.yours ? album : { ...album, yours }
  })
}

/**
 * Whether an album as Navidrome answers it (asked as you) is yours: starred by you - or your library holds
 * its release (`index`, /library/owned with `yours`). null while that can't be told - nothing starred and the
 * library not answered yet - so nothing is said rather than "in the store" of an album about to be yours.
 */
export function navidromeYours(
  album: { starred?: string | null; musicBrainzId?: string | null },
  index: OwnedIndex | null | undefined,
): boolean | null {
  if (album.starred) return true
  if (!index) return null
  const release = (album.musicBrainzId ?? '').trim().toLowerCase()
  const held: OwnedAlbum[] = release ? ownedForRelease(index, release) : []
  return held.some((folder) => folder.yours === true || folder.yours === undefined)
}

/** A store album's place in a row's line: "in your library" or "in the store" - '' while that can't be told,
 *  and always '' with logins off, where every album Navidrome has is in your library and no row ever said so.
 *  (2.0.0-player.52's rule for Search's library rows. Since 2.0.0-player.55 Search says libraryPlace instead, and
 *  nothing in the app calls this one - only whose.sim, which still pins its rule.) */
export function navidromePlace(personal: boolean, yours: boolean | null): string {
  if (!personal || yours === null) return ''
  return yours ? IN_YOUR_LIBRARY : IN_THE_STORE
}

/**
 * A library row's place in Search (2.0.0-player.55, "search like Apple Music"): the list has no half titles any
 * more ("In your library" over the library's rows is gone), so a row says where it is in both modes - "in your
 * library" with logins off (where navidromePlace, the rule it replaces for Search, was silent), and with a library
 * of your own "in your library" or "in the store", '' while that can't be told.
 */
export function libraryPlace(personal: boolean, yours: boolean | null): string {
  if (!personal) return IN_YOUR_LIBRARY
  if (yours === null) return ''
  return yours ? IN_YOUR_LIBRARY : IN_THE_STORE
}

/** What the album page says under Play when the album is in the store but not yours. */
//? (2.0.5) said as what the listener sees - no starring, no Navidrome (UX batch 2)
export const ADD_FROM_PAGE = "It's already here - add it to your library to keep it with your music."
/** ...once Add has it - as the store line says it (lib/myLibrary.ts ADDED_WORDS). */
export const ADDED_FROM_PAGE = 'Added to your library.'
/** ...once Remove has taken it out - the server's own words (routes/my_library.py REMOVED). */
export const REMOVED_FROM_PAGE = "Removed from your library - it's still in the collection, and nothing was deleted."
/** ...once Remove has taken out an album Add can't put back (review): how to have it back. */
export const REMOVED_STAR_TO_RETURN = `${REMOVED_FROM_PAGE} To add it back, make it a favourite in another music app.`
/** ...for an album deadwax can't keep in your library: no MusicBrainz release id to know it by. */
export const NO_RELEASE_TO_ADD = "This album can't be added from here - make it a favourite in another music app, and it joins your library."
/** ...for one with a release id whose folder deadwax hasn't found in the store (not scanned yet, or outside
 *  the folder deadwax looks after) - review: the page said nothing, or blamed the tags. */
export const NOT_FOUND_TO_ADD = "This album can't be added from here yet - make it a favourite in another music app, and it joins your library."

export interface AlbumMine {
  /** whether it is yours - null while that can't be told */
  yours: boolean | null
  /** the badge under the title: "In your library", or "In the store" - always true of an album Navidrome has */
  badge: string
  /** what the page offers: Add to my library, Remove from my library, or neither */
  action: 'add' | 'remove' | null
  /** the line beside it */
  note: string | null
  /** what it says is still to come (the album's own answer, or the id bridge's): the page holds the place of
   *  the line and Add that are most likely to land, so the songs drawn below don't move under a finger */
  pending: boolean
}

/**
 * The album page's "In your library" (2.0.0-player.52), for an album Navidrome has - so in the store, always:
 *
 *  - logins off (or the break-glass admin): "In your library", nothing offered - as it always was;
 *  - held by your library (the id bridge's `yours`) or starred by you - Navidrome's word, asked as you, in the
 *    album's OWN answer (`starred`; null until it has come - review: a list's tile, kept from before a
 *    Remove, offered Remove again): "In your library", with Remove from my library;
 *  - the bridge saying it isn't yours: "In the store", with Add to my library - when the store has its folder
 *    by a release id, which is how deadwax keeps it - else a line saying why it can't be added, and how to have
 *    it all the same (star it in Amperfy): no release id at all, or a folder deadwax hasn't found;
 *  - nothing known yet, or the bridge unable to say (it failed - review: never "no release id" for a check
 *    that couldn't be made; it answered without `yours` for a folder it has - deadwax couldn't read your
 *    library; it answered no release where Navidrome names one): "In the store", true either way, and nothing.
 *
 * `changed`: what this page just did - an Add or a Remove deadwax has taken, said at once over what the page
 * was told before it (the album's `starred` is as it was when the page asked). A Remove of an album Add can't
 * put back says how to have it back (review).
 */
export function albumMine({
  personal, starred, storeDone, bridgeFailed = false, bridgeYours, present, release, releaseSaid = null, changed,
}: {
  personal: boolean
  /** the album's own answer's `starred` - null until that answer has come */
  starred: boolean | null
  storeDone: boolean
  /** the id bridge couldn't be asked */
  bridgeFailed?: boolean
  bridgeYours: boolean | undefined
  present: number
  /** the release, as the bridge has it */
  release: string | null
  /** the release as Navidrome's album answer names it - '' for none, null until that answer has come */
  releaseSaid?: string | null
  changed: 'added' | 'removed' | null
}): AlbumMine {
  const label = (yours: boolean | null) => heldLabel(true, yours === true)
  const said = (yours: boolean | null, action: AlbumMine['action'], note: string | null, pending = false): AlbumMine =>
    ({ yours, badge: label(yours), action, note, pending })
  if (!personal) return { yours: true, badge: heldLabel(false, true), action: null, note: null, pending: false }
  const addable = !!release && present > 0
  if (changed === 'added') return said(true, 'remove', ADDED_FROM_PAGE)
  if (changed === 'removed') return said(false, addable ? 'add' : null, addable ? REMOVED_FROM_PAGE : REMOVED_STAR_TO_RETURN)
  if (bridgeYours === true || starred === true) return said(true, 'remove', null)
  if (starred === null || !storeDone) return said(null, null, null, true)
  //? the bridge couldn't say - failed, or no release where Navidrome names one: nothing is said
  if (bridgeFailed || (!release && releaseSaid)) return said(null, null, null)
  const why = release ? NOT_FOUND_TO_ADD : NO_RELEASE_TO_ADD
  if (bridgeYours === false) return addable ? said(false, 'add', ADD_FROM_PAGE) : said(false, null, why)
  //? the bridge said nothing of whose it is: deadwax couldn't read your library (a folder it has) - or it has
  //? no folder of this album by a release id, so it can't be added, and the line says why
  if (present > 0) return said(null, null, null)
  return said(false, null, why)
}
