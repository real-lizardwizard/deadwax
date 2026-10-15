import { useEffect, useState } from 'preact/hooks'

import { onAddedToLibrary, onRemovedFromLibrary } from '../lib/libraryEvents'
import { sortYourAlbums, YOURS_MAX, YOURS_PAGE } from '../lib/yourLibrary'
import { albumPage, type Album, type AlbumOrder } from '../player/api'

/**
 * Your albums (2.0.0-player.52, step 6 of the multi-user plan) - your starred albums in Navidrome, asked AS
 * YOU (getAlbumList2 `starred` through deadwax, which asks with your own login), for the Library's own views:
 * Your albums, Recently added (yours) and Your artists. A module, as useOwned and useMyLibrary are: every view
 * reading it shares one answer and one ask.
 *
 * Navidrome lists starred albums in one order of its own, so the whole list is asked for once - a page of
 * YOURS_PAGE at a time - and put in the order each view wants by lib/yourLibrary.ts; the grid then draws it a
 * page at a time from memory (yourAlbumsPage), as it draws the store's from Navidrome.
 *
 * Asked again - a new `generation`, which the views key their lists on - when it can have changed: an album
 * added to your library or removed from it here (lib/libraryEvents.ts), and when your library's count moves
 * (useMyLibrary's answer, which the Library tab asks as it shows - the starring worker and the read-back of
 * what you starred in Amperfy land there). NOT when an album is filed (second review): a filed album is starred
 * only later, by the worker once Navidrome has scanned it - the count moving then - so a filing changed nothing
 * here, yet every one (anybody's download an admin watches, each Edit panel write, Rescan, a Library care run)
 * emptied the grid, asked every page again and lost its place - even hidden under an album page, where Back
 * then found 60 tiles to scroll back into. A failed ask isn't kept: the next look asks again.
 * Nothing here is asked with logins off: the Library is the store's then, as it always was.
 */

let generation = 0
let held: { generation: number; albums: Promise<Album[]> } | null = null
const sorted = new Map<AlbumOrder, { generation: number; albums: Album[] }>()
let hearing = false
const listeners = new Set<() => void>()

function tell(): void {
  for (const listener of [...listeners]) listener()
}

/** Your albums are asked for afresh at the next look - every view keyed on the generation asks again. */
export function forgetYourAlbums(): void {
  generation += 1
  held = null
  sorted.clear()
  tell()
}

function hear(): void {
  if (hearing) return
  hearing = true
  onAddedToLibrary(forgetYourAlbums)
  onRemovedFromLibrary(forgetYourAlbums)
}

async function everyPage(): Promise<Album[]> {
  const albums: Album[] = []
  for (let offset = 0; offset < YOURS_MAX; offset += YOURS_PAGE) {
    const page = await albumPage('starred', offset, undefined, YOURS_PAGE)
    albums.push(...page)
    if (page.length < YOURS_PAGE) break
  }
  return albums
}

/** Every album in your library, in Navidrome's order - one ask shared by every view, until it can have changed. */
export function yourAlbums(): Promise<Album[]> {
  hear()
  if (!held || held.generation !== generation) {
    const asked = { generation, albums: everyPage() }
    asked.albums.catch(() => {
      if (held === asked) held = null
    })
    held = asked
  }
  return held.albums
}

/** One page of your albums in `order`, for usePaged - from the one list, sorted once per order. */
export async function yourAlbumsPage(order: AlbumOrder, offset: number, size: number): Promise<Album[]> {
  const asked = generation
  const albums = await yourAlbums()
  let kept = sorted.get(order)
  if (!kept || kept.generation !== asked) {
    kept = { generation: asked, albums: sortYourAlbums(albums, order) }
    sorted.set(order, kept)
  }
  return kept.albums.slice(offset, offset + size)
}

/** The generation your albums are on - what a view keys its list on - re-rendering the caller as it moves. */
export function useYourAlbumsGeneration(): number {
  const [, setSeen] = useState(0)
  useEffect(() => {
    hear()
    const listener = () => setSeen((count) => count + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
  return generation
}
