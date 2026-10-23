import type { Candidate, DownloadInFlight, DownloadJob, FindCandidatesResponse, JobQuality } from '../api/types'
import { HELD_TITLE, beingFiled, downloadProgressText, passesFilters, qualityText, storeStatus, type StoreStatus } from './candidates'
import { QUALITY_FLOORS, candidateFilters, floorFilters, type QualityFloor } from './getSettings'
import { ADD_NOTE, IN_THE_STORE, heldNotYours } from './myLibrary'

/**
 * Downloads per person (2.0.0-player.49, step 4 of the multi-user plan) - the words, pure, so
 * ui/test/requests.sim.cjs and sources.sim.cjs pin them rather than a phone.
 *
 * With logins on, a download is the person's who asked for it: a user's Requests, Home's Arriving and
 * the badge hold their own (joined ones too), an admin's everyone's - each saying who else asked. A
 * second person's Get of a pressing already downloading whole JOINS that download, and the store line
 * says what they'd get: its peer, its format and quality, and - when that is below their quality floor
 * - that getting a copy of their own isn't offered yet (it would mean deleting the worse copy for
 * everyone, which deadwax refuses to do by itself today: James's to design). Cancel means leave: a
 * user's withdraws their request while somebody else waits for it; the last one's, or an admin's,
 * cancels the download itself - and the question asked first says which, as the store line of a
 * download you share does (another peer is no cancel away then).
 *
 * With logins off the server sends none of the fields these read, and every word is what it was.
 */

/** What a Get sends of the folder it picked (2.0.0-player.49): the download keeps it, to tell someone
 *  else offered to join it what they'd get. */
export function candidateQuality(candidate: Pick<Candidate, 'formats' | 'bitrates' | 'bit_depths' | 'sample_rates' | 'variable_bitrate'>): JobQuality {
  return {
    formats: [...(candidate.formats ?? [])],
    bitrates: [...(candidate.bitrates ?? [])],
    bit_depths: [...(candidate.bit_depths ?? [])],
    sample_rates: [...(candidate.sample_rates ?? [])],
    variable_bitrate: Boolean(candidate.variable_bitrate),
  }
}

/** A download in flight as a candidate, for the quality floor's own rules (passesFilters). */
function asCandidate(download: DownloadInFlight): Candidate {
  return {
    username: download.username, directory: '', directory_name: '', score: 1,
    signals: { title_match: null, track_count: null, duration_match: null, edition: null, format: null, peer: null },
    matched_tracks: download.files, expected_tracks: 0, audio_file_count: download.files, detected_edition_tags: [],
    formats: download.formats ?? [], upload_speed: 0, queue_length: 0, has_free_slot: true, total_size: 0,
    bitrates: download.bitrates ?? [], bit_depths: download.bit_depths ?? [], sample_rates: download.sample_rates ?? [],
    variable_bitrate: download.variable_bitrate ?? false, files: [],
  }
}

/** "FLAC 24/96", "MP3 320k" - the copy, as a source card's Quality says it (qualityText: a lossless
 *  copy by its bit depth and rate, never a bitrate); '' when nothing is known. */
export function copyText(download: DownloadInFlight): string {
  const quality = qualityText(asCandidate(download))
  return quality === 'Unknown' ? '' : quality
}

/** The floor in You's words: 'Lossless', '24-bit', '320 kbps'. */
const floorLabel = (floor: QualityFloor) => QUALITY_FLOORS.find((each) => each.value === floor)?.label ?? floor

/**
 * How the copy in flight stands against your quality floor: null when it meets it (or the floor is
 * Any), 'below' when it doesn't, 'unknown' when its folder doesn't say what the floor asks about (no
 * bit depth against 24-bit, no bitrate for a lossy copy against 320, no format at all). Judged by the
 * floor's own rules - the Sources sheet's chips, through passesFilters.
 */
export function floorVerdict(download: DownloadInFlight, floor: QualityFloor): 'below' | 'unknown' | null {
  if (floor === 'any') return null
  if (passesFilters(asCandidate(download), candidateFilters(floorFilters(floor)))) return null
  const formats = download.formats ?? []
  const unsaid = !formats.length
    || (floor === '24bit' && !(download.bit_depths ?? []).length)
    || (floor === '320' && !(download.bitrates ?? []).length)
  return unsaid ? 'unknown' : 'below'
}

/** The line saying a joinable copy falls short of your floor - or null. */
export function floorNote(download: DownloadInFlight, floor: QualityFloor | null | undefined): string | null {
  const verdict = floor ? floorVerdict(download, floor) : null
  if (!verdict || !floor) return null
  const own = "getting a copy of your own isn't offered yet"
  return verdict === 'below'
    ? `It's below your quality floor (${floorLabel(floor)}), and ${own}.`
    : `Its folder doesn't say whether it meets your quality floor (${floorLabel(floor)}), and ${own}.`
}

/** The last line of a download somebody else asked for: what Join does - in the page's own place for
 *  downloads (the app's Requests, the main page's Downloads), however many already wait for it. */
export const joinNote = (place: 'Downloads' | 'Requests') =>
  `Join it to have it in your ${place} too - one download, everyone who asked waiting for it.`

/**
 * (2.0.0-player.65, the 2.0.0 release review) A store line drawn with no Join under it - for someone without Get
 * albums, whose page gives no `onJoin`: the line saying what Join does goes too, and so does the job Join would
 * join, so it never says "Join it" above no button. Anything else is the line as it was.
 */
export function withoutJoin(status: StoreStatus): StoreStatus {
  if (status.joinJobId === undefined) return status
  const { joinJobId: _join, ...rest } = status
  const notes = new Set([joinNote('Downloads'), joinNote('Requests')])
  return { ...rest, lines: status.lines.filter((line) => !notes.has(line)) }
}

/**
 * Whether a cancel of this download - a row of /jobs, or Find's download in flight - only withdraws
 * your request: somebody else waits for it too (`shared`) and you're no admin (an admin's rows carry
 * `requested_by`; an admin's cancel is for everyone). Never with logins off (no `shared` at all).
 */
export function leavesOnCancel(job: { shared?: boolean; requested_by?: string[] }): boolean {
  return Boolean(job.shared) && job.requested_by === undefined
}

/** The store line's last line for a download of yours somebody else waits for too - instead of
 *  "cancel it if you want another peer", which a cancel that only leaves can't give. */
export const sharedNote = (place: 'Downloads' | 'Requests') =>
  `Someone else asked for it too, so cancelling it in ${place} only takes it off your list - another peer isn't offered for a download you share.`

/**
 * The store's status for a pressing (lib/candidates.ts storeStatus) - every page's, the main page's
 * included - with these cases of its own:
 *
 *  - a download somebody ELSE asked for (`yours` false - logins on) is theirs to join. Its title says
 *    so, its first line says what you'd get - the peer, the copy and how far it has got - then the
 *    quality floor's word when it falls short, and what joining does; `joinJobId` is the download
 *    Join joins.
 *  - your own that somebody else waits for too, as a user: a cancel would only take it off your list,
 *    so the line says that instead of "cancel it if you want another peer" (sharedNote).
 *  - one failed and moving to its next peer by itself (its retry pending - AUTO_RETRY_PEER, logins on
 *    or off): it is already going to another peer, so nothing says to cancel it for one, and how far
 *    it has got says it is moving (downloadProgressText).
 *  - (2.0.0-player.51, personal libraries) a pressing the store holds whole that isn't in YOUR library
 *    (`held.yours` false - logins on): "In the store, not in your library", what it is, and that adding it
 *    downloads nothing - `add`, for Add to my library under it.
 *
 * Anything else is storeStatus's, word for word.
 */
export function storeStatusFor(
  result: Pick<FindCandidatesResponse, 'held' | 'downloading'> | null | undefined,
  cancelIn: 'Downloads' | 'Requests' = 'Downloads',
  floor: QualityFloor | null = null,
): StoreStatus | null {
  const download = result?.downloading
  if (download && download.yours === false) {
    const note = floorNote(download, floor)
    return {
      kind: 'downloading',
      title: beingFiled(download) ? 'Already downloaded for someone else' : 'Already downloading for someone else',
      lines: [
        [`From ${download.username}`, copyText(download), downloadProgressText(download)].filter(Boolean).join(' · '),
        ...(note ? [note] : []),
        joinNote(cancelIn),
      ],
      joinJobId: download.job_id,
    }
  }
  const status = storeStatus(result, cancelIn)
  //? (2.0.0-player.51) held whole by the store, but not in your library: Add to my library, not a download
  const held = result?.held
  if (!download && status && held?.complete && heldNotYours(held)) {
    return { ...status, title: IN_THE_STORE, lines: [...status.lines, ADD_NOTE], add: true }
  }
  if (!download || !status || beingFiled(download)) return status
  //? storeStatus's lines here: the peer and how far, then where to cancel it for another peer
  if (download.status === 'failed') return { ...status, lines: status.lines.slice(0, 1) }
  if (leavesOnCancel(download)) return { ...status, lines: [...status.lines.slice(0, 1), sharedNote(cancelIn)] }
  return status
}

/**
 * The store line once Add to my library has added the pressing from it, while the page that drew it
 * doesn't ask the store again (the Sources panel): "Already in your library", the add note gone - so the
 * box never says "not in your library" above "Added" (review). `add` is kept, so the button's own words
 * ("Added - it's in your library…") stay where it was. A status without Add is as it was.
 */
export function addedStatus(status: StoreStatus): StoreStatus {
  if (!status.add) return status
  return { ...status, title: HELD_TITLE, lines: status.lines.filter((line) => line !== ADD_NOTE) }
}

/** "a", "a and b", "a, b and c". */
function listed(items: readonly string[]): string {
  if (items.length < 2) return items[0] ?? ''
  return `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`
}

/** What a user's row says of a download somebody else waits for too - nobody named: who else asked is
 *  an admin's to see. */
export const SHARED_TEXT = 'Someone else asked for it too'

/**
 * Who asked, on an admin's row: "Asked by ethan", "Asked by you and ethan", "Asked by you, ethan and
 * sam" (in the order they asked) - null for a row only you are waiting for, NOBODY_TEXT for one nobody is. A user's row (the server
 * tells who else asked to an admin alone) says SHARED_TEXT when somebody else waits for it too - so a
 * Get that joined somebody's download, and a cancel that will only leave, aren't a surprise - and
 * nothing otherwise; any row with logins off, nothing.
 */
export function askedByText(job: Pick<DownloadJob, 'mine' | 'shared' | 'requested_by'>): string | null {
  const others = job.requested_by
  if (others === undefined) return job.shared ? SHARED_TEXT : null
  //? (2.0.0-player.61) nobody's: the one who asked was removed in People, or cleared it - it carries on, filed for nobody
  if (!others.length) return job.mine ? null : NOBODY_TEXT
  return `Asked by ${listed(job.mine ? ['you', ...others] : others)}`
}

/** (2.0.0-player.61) What a row seeing everyone's says of a download nobody waits for any more. */
export const NOBODY_TEXT = 'Nobody is waiting for this any more'

/** What the ✕'s question says, and its answer's button - and whether the cancel only LEAVES (the ✕'s
 *  name, the overlay's "leaving…" and what a screen reader hears follow it). */
export interface CancelWords {
  question: string
  action: string
  leaves: boolean
}

export const CANCEL_WORDS: CancelWords = {
  question: "Cancel this download? You'll lose your place in this peer's queue.",
  action: 'Cancel download',
  leaves: false,
}

/**
 * The ✕'s question for a row: a user's on a download somebody else waits for too LEAVES it ("it
 * carries on for them"); an admin's on one somebody else waits for cancels it FOR EVERYONE, naming
 * them; anything else - logins off included - the question it always was.
 */
export function cancelWords(job: Pick<DownloadJob, 'mine' | 'shared' | 'requested_by'>): CancelWords {
  if (!job.shared) return CANCEL_WORDS
  if (leavesOnCancel(job)) {
    return { question: 'Leave this download? Someone else asked for it too, so it carries on for them.', action: 'Leave it', leaves: true }
  }
  return {
    question: `Cancel this download for everyone? ${listed(job.requested_by ?? []) || 'Someone else'} asked for it${job.mine ? ' too' : ''}.`,
    action: 'Cancel for everyone',
    leaves: false,
  }
}
