import type { Candidate, DownloadInFlight, FindCandidatesResponse, HeldPressing } from '../api/types'
import { formatSpeed } from './format'

/**
 * The candidates panel's logic, with no DOM - ported from interface/scripts/main.js in v0.9.10
 * so ui/test/candidates.sim.cjs can hold it. The panel itself is components/CandidatesPanel.tsx.
 */

export const SIGNAL_LABELS: Readonly<Record<string, string>> = {
  title_match: 'titles',
  track_count: 'count',
  duration_match: 'lengths',
  edition: 'edition',
  format: 'format',
  peer: 'peer',
}

export interface CandidateFilters {
  freeSlotOnly: boolean
  completeOnly: boolean
  /** 0-100, against the score as a percentage */
  minScore: number
  /** Empty means every format. Reset with each new result - they are that result's formats. */
  formats: ReadonlySet<string>
  /** Per-signal minimums, 0-100. 0 is off. */
  minSignals: Readonly<Record<string, number>>
  /** What the files must be at least, and how big the folder may be. See QualityFilters. */
  quality: QualityFilters
}

/**
 * Quality filters (v0.9.11, asked for: "filter and search by bitrate and depth, maybe by file
 * size"). Every field 0 = off. Each is judged against the folder's WORST file - a 320 album
 * with one 128 track is not a 320 album.
 *
 * UNKNOWN cannot satisfy a minimum, as with the signal sliders: many clients report no bit depth
 * or sample rate, and a folder that might be 16/44 must not pass "24-bit". One exception, and
 * only for bitrate: a lossless folder with no reported bitrate passes a bitrate minimum, because
 * any lossless file is above any lossy bitrate you could ask for, and hiding every unreported
 * FLAC behind "at least 320" would be absurd.
 */
export interface QualityFilters {
  /** kbps */
  minBitrate: number
  /** bits */
  minBitDepth: number
  /** Hz */
  minSampleRate: number
  /** MB, the folder's total */
  minSizeMb: number
  maxSizeMb: number
}

export const NO_QUALITY_FILTERS: QualityFilters = {
  minBitrate: 0, minBitDepth: 0, minSampleRate: 0, minSizeMb: 0, maxSizeMb: 0,
}

export const LOSSLESS_FORMATS: ReadonlySet<string> = new Set(['flac', 'alac', 'ape', 'wav', 'aiff', 'aif', 'wv'])

function allLossless(candidate: Candidate): boolean {
  return candidate.formats.length > 0 && candidate.formats.every((f) => LOSSLESS_FORMATS.has(f))
}

const MB = 1024 * 1024

export function passesQuality(candidate: Candidate, quality: QualityFilters): boolean {
  if (quality.minBitrate) {
    const bitrates = candidate.bitrates ?? []
    if (bitrates.length) {
      if (Math.min(...bitrates) < quality.minBitrate) return false
    } else if (!allLossless(candidate)) {
      return false
    }
  }
  if (quality.minBitDepth) {
    const depths = candidate.bit_depths ?? []
    if (!depths.length || Math.min(...depths) < quality.minBitDepth) return false
  }
  if (quality.minSampleRate) {
    const rates = candidate.sample_rates ?? []
    if (!rates.length || Math.min(...rates) < quality.minSampleRate) return false
  }
  if (quality.minSizeMb && candidate.total_size < quality.minSizeMb * MB) return false
  if (quality.maxSizeMb && candidate.total_size > quality.maxSizeMb * MB) return false
  return true
}

/** How many quality filters are on - the badge on the Quality button. */
export function activeQualityCount(quality: QualityFilters): number {
  return Object.values(quality).filter(Boolean).length
}

export function noSignalMinimums(): Record<string, number> {
  return Object.fromEntries(Object.keys(SIGNAL_LABELS).map((k) => [k, 0]))
}

export function passesFilters(candidate: Candidate, filters: CandidateFilters): boolean {
  if (filters.freeSlotOnly && !candidate.has_free_slot) return false
  if (Math.round(candidate.score * 100) < filters.minScore) return false

  if (filters.completeOnly && candidate.expected_tracks
      && candidate.matched_tracks < candidate.expected_tracks) return false

  if (filters.formats.size && !candidate.formats.some((f) => filters.formats.has(f))) return false

  for (const [signal, minimum] of Object.entries(filters.minSignals)) {
    if (!minimum) continue
    const value = candidate.signals[signal as keyof typeof candidate.signals]
    //? null means the signal couldn't be judged - slskd didn't report track lengths, say. If
    //? you've asked for a minimum there, "unknown" cannot satisfy it.
    if (value === null || value === undefined) return false
    if (Math.round(value * 100) < minimum) return false
  }

  return passesQuality(candidate, filters.quality)
}

export type CandidateSort = 'score' | 'quality' | 'size_desc' | 'size_asc'

export const SORT_LABELS: Readonly<Record<CandidateSort, string>> = {
  score: 'Best match',
  quality: 'Highest quality',
  size_desc: 'Largest first',
  size_asc: 'Smallest first',
}

/**
 * A folder's quality as a sortable tuple: lossless first, then the WORST file's bit depth,
 * sample rate and bitrate. Unknowns count as zero, so a folder that reported nothing sorts
 * below one that reported something modest - it earns no place it can't show.
 */
export function qualityRank(candidate: Candidate): number[] {
  const worst = (values: readonly number[] | undefined) => (values?.length ? Math.min(...values) : 0)
  return [
    allLossless(candidate) ? 1 : 0,
    worst(candidate.bit_depths),
    worst(candidate.sample_rates),
    worst(candidate.bitrates),
  ]
}

/**
 * The list in the chosen order. Always a copy; ties keep the server's order, which is the match
 * score - so "Highest quality" among equals still puts the better match first.
 */
export function sortCandidates(candidates: readonly Candidate[], sort: CandidateSort): Candidate[] {
  const list = [...candidates]
  if (sort === 'score') return list
  if (sort === 'size_desc') return list.sort((a, b) => b.total_size - a.total_size)
  if (sort === 'size_asc') return list.sort((a, b) => a.total_size - b.total_size)
  return list.sort((a, b) => {
    const x = qualityRank(a)
    const y = qualityRank(b)
    for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return y[i]! - x[i]!
    return 0
  })
}

/**
 * " 24-bit 96kHz", " 16-24-bit 44.1-96kHz", or '' - what the client reported, appended after the
 * format like the bitrate. Nothing is guessed: a lossless file that didn't say says nothing.
 */
export function depthRateText(candidate: Candidate): string {
  const range = (values: readonly number[] | undefined, format: (n: number) => string) => {
    if (!values?.length) return ''
    const low = Math.min(...values)
    const high = Math.max(...values)
    return low === high ? format(low) : `${format(low).replace(/[a-zA-Z-]+$/, '')}-${format(high)}`
  }
  const depth = range(candidate.bit_depths, (n) => `${n}-bit`)
  const rate = range(candidate.sample_rates, (n) => `${trimRate(n / 1000)}kHz`)
  return [depth, rate].filter(Boolean).map((part) => ` ${part}`).join('')
}

function trimRate(khz: number): string {
  return Number.isInteger(khz) ? String(khz) : khz.toFixed(1)
}

/** How many per-signal minimums are set - the badge on the Signals button. */
export function activeSignalCount(filters: CandidateFilters): number {
  return Object.values(filters.minSignals).filter(Boolean).length
}

/** The formats a result offers, for its chips. */
export function resultFormats(candidates: readonly Candidate[]): string[] {
  return [...new Set(candidates.flatMap((c) => c.formats))].filter(Boolean).sort()
}

/**
 * Only an EDITED query overrides. The box shows the first of possibly several searches - an
 * artist who has renamed is searched under each name - so re-running what it already says as
 * an override would quietly drop every name but that one.
 */
export function queryOverride(typed: string, lastShown: string): string {
  const trimmed = typed.trim()
  return trimmed && trimmed !== lastShown ? trimmed : ''
}

export function scoreClass(percent: number): 'good' | 'mid' | 'bad' {
  return percent >= 75 ? 'good' : percent >= 40 ? 'mid' : 'bad'
}

/** "10/10 tracks" against a tracklist, "12 files" without one. */
export function trackSummary(candidate: Candidate): string {
  return candidate.expected_tracks
    ? `${candidate.matched_tracks}/${candidate.expected_tracks} tracks`
    : `${candidate.audio_file_count} files`
}

/** " 320kbps", " 256-320kbps", " VBR 245kbps", or '' - appended to the formats. */
export function bitrateText(bitrates: readonly number[] | undefined, variable = false): string {
  if (!bitrates?.length) return ''
  const low = Math.min(...bitrates)
  const high = Math.max(...bitrates)
  return ` ${variable ? 'VBR ' : ''}${low === high ? low : `${low}-${high}`}kbps`
}

/*
 * How a peer's advertised speed is labelled - a correctness question, not a cosmetic one. It
 * used to read "▼ 1.2 MB/s", and a download arrow is a promise about YOUR transfer that this
 * number cannot keep: it is the peer's average upload speed across their whole history, to
 * everyone. See the note in CLAUDE.md; do not "simplify" it back to a bare rate.
 */
export const PEER_SPEED_HINT =
  "The peer's average upload speed across all their transfers, as reported by Soulseek. "
  + 'Not a prediction of your download rate: it is shared between everyone they are '
  + 'uploading to and averaged over their whole history. The slot and queue beside it are '
  + 'better guides to what you will actually get.'

export function peerSpeedLabel(bytesPerSecond: number): string {
  //? 'peer avg unknown' reads like a broken string; say the thing that is unknown instead
  return bytesPerSecond ? `peer avg ${formatSpeed(bytesPerSecond)}` : 'peer avg unknown'
}

/**
 * What this peer ACTUALLY gave us, where it has been measured - {text, title}, or null for the
 * ordinary case of a peer never downloaded from, which renders as nothing at all.
 */
export function measuredSpeed(candidate: Candidate): { text: string; title: string } | null {
  if (!candidate.measured_speed) return null

  const samples = candidate.measured_samples || 1
  const when = measuredDate(candidate.measured_at)
  //? One transfer is an anecdote and more than one is closer to a figure, so the tilde
  //? appears only once there is an average to hedge.
  const value = `${samples > 1 ? '~' : ''}${formatSpeed(candidate.measured_speed)}`
  const hint = samples > 1
    ? `Measured by deadwax over ${samples} transfers from this peer${when}. `
    : `Measured by deadwax on one transfer from this peer${when}. `

  return {
    text: `you got ${value}`,
    title: hint
      + 'This is what actually arrived while bytes were moving, with queue time excluded - '
      + "unlike the advertised average beside it, which is the peer's own figure for all "
      + 'their uploads to everyone.',
  }
}

function measuredDate(iso: string | undefined): string {
  if (!iso) return ''
  const at = new Date(iso)
  return Number.isNaN(at.getTime()) ? '' : `, most recently ${at.toLocaleDateString()}`
}

/** A candidate's identity within one result - a peer's folder. */
export function candidateKey(candidate: Candidate): string {
  return `${candidate.username}\n${candidate.directory}`
}

/**
 * Colour class for an edition tag. A copy of EDITION_TAG_COLORS in interface/scripts/main.js,
 * which still colours the releases grid; display only, so a drift is cosmetic - but keep them
 * in step until the grid is ported and that copy goes.
 */
export const EDITION_TAG_COLORS: Readonly<Record<string, string>> = {
  REMASTER: 'yellow',
  'SUPER DELUXE': 'red',
  DELUXE: 'main',
  'BOX SET': 'green',
  ANNIVERSARY: 'white',
  EXPANDED: 'white-secondary',
  LIMITED: 'main-secondary',
  'SPECIAL EDITION': 'white-tertiary',
}

/** The "good" band of the score colours - below it, auto-grab leaves the choice to you. */
export const AUTO_GRAB_MIN_SCORE = 75

/**
 * What auto-grab would queue from a result (v0.9.16): the top of the list as the filters and
 * sort show it, and only when that scores AUTO_GRAB_MIN_SCORE or better - a weak best match is
 * exactly when you want to choose. Returns the pick and the shown list (its runners-up), or null.
 */
export function autoGrabPick(
  candidates: readonly Candidate[], filters: CandidateFilters, sort: CandidateSort,
): { pick: Candidate; list: Candidate[] } | null {
  const list = sortCandidates(candidates.filter((c) => passesFilters(c, filters)), sort)
  const pick = list[0]
  return pick && Math.round(pick.score * 100) >= AUTO_GRAB_MIN_SCORE ? { pick, list } : null
}

/*
 * What Find says about the library and the downloads before - or instead of - searching (step 2
 * of the multi-user plan; src/store_index.py). A pressing already held complete, or already
 * downloading whole, isn't searched for: its status replaces the results. Part of it held, a
 * download of part of it running, or another pressing of the album held, is a note above them.
 * Every line is built here, so ui/test/candidates.sim.cjs holds what the panel says.
 */

/** "FLAC", "FLAC, MP3" - formats as the panel names them. */
export function formatNames(formats: readonly string[] | undefined): string {
  return (formats ?? []).filter(Boolean).map((f) => f.toUpperCase()).join(', ')
}

/** "a", "a and b", "a, b and c". */
function listed(items: readonly string[]): string {
  if (items.length < 2) return items[0] ?? ''
  return `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`
}

/** "10 of 10 tracks", or "9 tracks" when no tracklist was sent to count against. */
export function heldTrackText(held: HeldPressing): string {
  const plural = (n: number) => (n === 1 ? 'track' : 'tracks')
  return held.expected_tracks
    ? `${held.track_count} of ${held.expected_tracks} ${plural(held.expected_tracks)}`
    : `${held.track_count} ${plural(held.track_count)}`
}

/**
 * Past downloading, on its way into the library. There is nothing left to cancel for another
 * peer then, and the server counts `complete` only in the seconds before the poller starts
 * filing it (store.COMPLETE_IN_FLIGHT_SECONDS).
 */
export function beingFiled(download: DownloadInFlight): boolean {
  return download.status === 'organizing' || download.status === 'complete'
}

/** How far a download in flight has got, in a few words. */
export function downloadProgressText(download: DownloadInFlight): string {
  if (beingFiled(download)) return 'being filed into your library now'
  switch (download.status) {
    case 'queued':
      return 'queued'
    case 'downloading':
      return download.done_files === undefined ? 'downloading' : `${download.done_files} of ${download.files} files`
    default:
      return download.status
  }
}

/** A status that stands in for the results: a heading, and lines under it. */
export interface StoreStatus {
  kind: 'held' | 'downloading'
  title: string
  lines: string[]
}

/**
 * The status in place of the results, when there is one - downloading first, since a job in
 * flight is what the server checks first too - or null for an ordinary result.
 */
export function storeStatus(result: FindCandidatesResponse | null | undefined): StoreStatus | null {
  const downloading = result?.downloading
  if (downloading) {
    const line = `From ${downloading.username} · ${downloadProgressText(downloading)}`
    //? being filed: the files are all in, so there's no other peer to cancel it for
    return beingFiled(downloading)
      ? { kind: 'downloading', title: 'Already downloaded', lines: [line] }
      : {
          kind: 'downloading',
          title: 'Already downloading',
          lines: [line, 'Open Downloads to cancel it if you want another peer.'],
        }
  }
  const held = result?.held
  if (held?.complete) {
    return {
      kind: 'held',
      title: 'Already in your library',
      lines: [
        //? every folder, for a set stored one folder per disc
        ...(held.paths?.length ? held.paths : [held.path]),
        [heldTrackText(held), formatNames(held.formats)].filter(Boolean).join(' · '),
      ],
    }
  }
  return null
}

/**
 * What a download would do with a part held - said only as far as it is true. Filing fills in
 * just the one folder it files into (`filed_to`), skipping the tracks already there; a part held
 * anywhere else - Picard's `Artist/Album`, an older template - gets a separate copy beside it.
 * Never "fills in the missing ones": a download brings only what the folder picked holds, which
 * may be missing the very tracks you are.
 */
function whatADownloadDoes(held: HeldPressing): string {
  const folders = held.paths?.length ? held.paths : [held.path]
  const those = folders.length > 1 ? 'those folders' : 'that folder'
  if (held.fills_gaps && held.filed_to) {
    return folders.length > 1
      ? `Downloading it files only the tracks ${held.filed_to} doesn't have yet.`
      : "Downloading it files only the tracks that folder doesn't have yet."
  }
  return held.filed_to
    ? `A download would be filed separately, in ${held.filed_to}, rather than fill in ${those}.`
    : `A download may be filed separately rather than fill in ${those}.`
}

/**
 * The notes above the results: a download of part of this pressing already running, part of it
 * held, and each other pressing held.
 */
export function storeNotes(result: FindCandidatesResponse | null | undefined): string[] {
  const notes: string[] = []
  const part = result?.downloading_part
  if (part) {
    //? a lone disc folder, say - it stops nothing, since it will never bring the rest
    const files = `${part.files} ${part.files === 1 ? 'file' : 'files'}`
    notes.push(
      `A download of part of this pressing is already running: ${files} from ${part.username} · `
      + `${downloadProgressText(part)}.`,
    )
  }
  const held = result?.held
  if (held && !held.complete) {
    notes.push(
      `You have ${held.track_count} of ${held.expected_tracks} tracks of this pressing, in `
      + `${listed(held.paths?.length ? held.paths : [held.path])}. ${whatADownloadDoes(held)}`,
    )
  }
  for (const pressing of result?.other_pressings ?? []) {
    const parts = [pressing.edition || pressing.year, formatNames(pressing.formats), pressing.path].filter(Boolean)
    notes.push(`You also have another pressing: ${parts.join(' · ')}`)
  }
  return notes
}
