import type { DeletionSummary, DownloadJob, HeldPressing, LibraryEntry, MyLibrary } from '../api/types'

/**
 * Personal libraries (2.0.0-player.51, step 5 of the multi-user plan) - the words, pure, so
 * ui/test/mylibrary.sim.cjs pins them rather than a phone.
 *
 * With logins on, YOUR library is your starred albums in Navidrome - two-way with Amperfy - and deadwax
 * keeps a ledger of it, starring each album as you once Navidrome has it (src/stars.py). What a download
 * gave you is said on its row; a pressing the store holds that isn't yours offers Add to my library on
 * the store line; You says how far the starring has got, and why anything still waits - Navidrome no
 * longer taking the login you signed in with above all; Home has what is new in it; the delete dialog
 * names who holds an album. With logins off the server sends none of the fields these read, and every
 * word is what it was.
 */

/** The store line's last line for a pressing the store holds that isn't in your library. */
//? (2.0.5, UX batch 2) as what the listener sees - the album page says the same (lib/whose.ts ADD_FROM_PAGE)
export const ADD_NOTE = "It's already here - add it to your library to keep it with your music."

/** ...and once added. */
export const ADDED_WORDS = 'Added to your library.'

/** The title of the store line for a pressing held whole that isn't yours. */
export const IN_THE_STORE = 'In the collection, not in your library'

/** Whether a held pressing is somebody else's to you - logins on, and not in your library. */
export function heldNotYours(held: Pick<HeldPressing, 'yours'> | null | undefined): boolean {
  return held?.yours === false
}

const plural = (n: number, one: string, many: string) => (n === 1 ? one : many)

/** "a", "a and b", "a, b and c". */
function listed(items: readonly string[]): string {
  if (items.length < 2) return items[0] ?? ''
  return `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`
}

/** (2.0.6) A partly filed download's files that didn't make it: "2 files couldn't be added" from the job's
 *  "2 file(s) failed to organize" (poller.py FAILED_TO_ORGANIZE), "some files couldn't be added" without a count. */
export function partlyWords(error: string | null | undefined): string {
  const count = /^(\d+) file\(s\) failed to organize/.exec((error ?? '').trim())
  if (!count) return "some files couldn't be added"
  const n = Number(count[1])
  return `${n} ${n === 1 ? "file couldn't" : "files couldn't"} be added`
}

/**
 * How a finished download's row says what its filing gave (the server's `library`, logins on) - or null
 * for the words it always had. `mine` false: an admin's row of somebody else's download.
 */
export function grantWords(
  job: Pick<DownloadJob, 'outcome' | 'error' | 'library' | 'mine'>,
): { text: string; tone: 'plain' | 'warning'; detail?: string | null } | null {
  const whose = job.mine === false ? 'their' : 'your'
  if (job.outcome === 'filed' && job.library === 'added') {
    return { text: job.mine === false ? 'In their library' : 'In your library', tone: 'plain' }
  }
  if (job.outcome === 'already_there') {
    if (job.library === 'added') return { text: `Already in the collection, added to ${whose} library`, tone: 'plain' }
    //? (2.0.6, UX batch 3) the folder it would have filed into holds another pressing or an untagged rip (grant_for):
    //? said as "may be another pressing" - it said "as another copy"
    if (job.library === 'flagged') {
      return { text: "Not added - the collection's copy may be another pressing, so an admin has been asked to check it", tone: 'warning' }
    }
    //? the admin looked and put the flag away (Add for them makes it 'added' - review: the row kept saying
    //? an admin had been asked)
    if (job.library === 'looked') return { text: "Not added - the collection's copy may be another pressing; an admin has checked it", tone: 'warning' }
  }
  //? (2.0.6) in their library, not whole - it said "Partly filed: 2 file(s) failed to organize · in your library, marked
  //? incomplete"; the job's own words for whoever runs deadwax (DoneRow)
  if (job.outcome === 'partly_filed' && job.library === 'incomplete') {
    return { text: `In ${whose} library - ${partlyWords(job.error)}`, tone: 'warning', detail: job.error || null }
  }
  return null
}

/** "12 albums", "12 albums · 2 waiting to be added" - You's line for your library. */
export function libraryLine(answer: MyLibrary): string {
  const count = answer.count ?? 0
  const waiting = answer.waiting ?? 0
  const albums = `${count} ${plural(count, 'album', 'albums')}`
  return waiting ? `${albums} · ${waiting} waiting to be added` : albums
}

/** Why nothing new can be added to your library now - the login the music server no longer takes - or null.
 *  (2.0.5) Said as what the listener sees and does, never the server's own words for why (`login_problem`: auth.py's
 *  LOGIN_GONE, which names Navidrome, or KEY_CHANGED): sign out, sign in again - nothing is lost meanwhile (the ledger
 *  keeps what waits). */
export function loginWords(answer: MyLibrary): string | null {
  if (answer.login !== 'dead') return null
  return "New albums can't be added to your library until you sign in again. Sign out, then sign in - with your new password if you changed it. Nothing is lost meanwhile."
}

/** How many albums a waiting group names before "and N more" - the count is on the Albums row already. */
export const WAITING_NAMED = 3

/** The albums still waiting, grouped by why: [{words, albums: ['Dummy', ...]}], the most first. */
export function waitingGroups(answer: MyLibrary): { words: string; albums: string[] }[] {
  const groups = new Map<string, string[]>()
  for (const entry of answer.waiting_albums ?? []) {
    const words = entry.words || 'Waiting its turn to be added.'
    const albums = groups.get(words) ?? []
    albums.push(entryName(entry))
    groups.set(words, albums)
  }
  return [...groups.entries()].map(([words, albums]) => ({ words, albums })).sort((a, b) => b.albums.length - a.albums.length)
}

/**
 * One waiting group as You says it: the first WAITING_NAMED albums, then "and N more", then why - so a
 * library of sixty untagged albums (each waiting for ever with "no release id") is one short line, not a
 * paragraph of sixty names at the top of You on every visit (review).
 */
export function waitingText(group: { words: string; albums: readonly string[] }): string {
  const named = group.albums.slice(0, WAITING_NAMED)
  const more = group.albums.length - named.length
  const names = more > 0 ? `${named.join(', ')} and ${more} more` : listed(named)
  return `${names}: ${group.words}`
}

/**
 * Where focus goes when a row of a list leaves the page (Put away, Add for them): the row now after it,
 * else the one before it, else null - the section's heading. Never the page, which drops a keyboard's or
 * VoiceOver's place in the list (the app's rule - Pinned's unpin does the same).
 */
export function nextFocus<T>(ids: readonly T[], gone: T): T | null {
  const at = ids.indexOf(gone)
  if (at < 0) return null
  return ids[at + 1] ?? ids[at - 1] ?? null
}

/** "Dummy by Portishead" - an entry as a line names it. */
export function entryName(entry: Pick<LibraryEntry, 'album' | 'artist'>): string {
  const album = entry.album || 'Unknown album'
  return entry.artist ? `${album} by ${entry.artist}` : album
}

/** The removed-by-an-admin line under an album an admin deleted - Get it again beside it. */
export const REMOVED_WORDS = 'Removed by an admin.'

/**
 * What the delete dialog says of who holds the album (logins on: the summary's `holders` - everyone else -
 * and `yours`, the admin asking) - null with logins off. An album nobody holds is said too, so the admin
 * knows it takes nothing from anybody; but only when deadwax could READ who holds it - unread
 * (`holders_unknown`) is said as unread, never as "nobody" (review: the one action with no undo).
 */
export function holdersText(summary: Pick<DeletionSummary, 'holders' | 'yours' | 'holders_unknown'> | null | undefined): string | null {
  if (summary?.holders_unknown) {
    return "deadwax couldn't read who has it in their library - whoever does will find it was removed by an admin."
  }
  const holders = summary?.holders
  if (holders === undefined) return null
  const yours = summary?.yours === true
  if (!holders.length) return yours ? 'In your library: deleting it takes it out.' : 'Nobody has it in their library.'
  const others = listed([...holders])
  if (yours) {
    return `In ${listed(['your library', ...holders.map((holder) => `${holder}'s`)])}: deleting it takes it out, and ${others} will see it was removed by an admin.`
  }
  return `In ${others}'s ${plural(holders.length, 'library', 'libraries')}: deleting it takes it out, and they'll see it was removed by an admin.`
}

/** The Navidrome album ids and release ids of what is new in your library - Home's shelf, the Library's marks. */
export function newMarks(answer: MyLibrary | null): { ids: Set<string>; releases: Set<string> } {
  const ids = new Set<string>()
  const releases = new Set<string>()
  for (const entry of answer?.new ?? []) {
    if (entry.navidrome_id) ids.add(entry.navidrome_id)
    if (entry.release_mbid) releases.add(entry.release_mbid.toLowerCase())
  }
  return { ids, releases }
}

/** Whether an album (Navidrome's) is new in your library - by its id, or by the release it is. */
export function isNew(marks: { ids: Set<string>; releases: Set<string> }, album: { id: string; musicBrainzId?: string }): boolean {
  if (marks.ids.has(album.id)) return true
  const release = (album.musicBrainzId ?? '').trim().toLowerCase()
  return release !== '' && marks.releases.has(release)
}

/** Home's "New in your library" shelf: the new entries Navidrome has (a starred one has its album id), newest first. */
export function newShelf(answer: MyLibrary | null): { id: string; name: string; artist: string; coverArt: string; musicBrainzId?: string }[] {
  return (answer?.new ?? [])
    .filter((entry): entry is LibraryEntry & { navidrome_id: string } => !!entry.navidrome_id)
    .map((entry) => ({
      id: entry.navidrome_id,
      name: entry.album || 'Unknown album',
      artist: entry.artist,
      coverArt: entry.navidrome_id,
      ...(entry.release_mbid ? { musicBrainzId: entry.release_mbid } : {}),
    }))
}

/** "Held by nobody · 3" - Library care's heading for what nobody has in their library. */
export function heldByNobodyLine(count: number): string {
  return count ? `${count} ${plural(count, 'album', 'albums')} nobody has in their library` : "Every album in the collection is in somebody's library."
}

/** A flagged download's line: who asked, and why nobody was given it. */
export function flagWords(flag: { users: string[]; path: string | null }): string {
  const who = flag.users.length ? listed(flag.users) : 'Nobody'
  return `${who} asked for it. Every file was already in ${flag.path || 'its folder'}, which holds another pressing or an untagged copy - so nobody was given it.`
}
