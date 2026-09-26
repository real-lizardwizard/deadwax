import type { Candidate } from '../api/types'
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

  return true
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

/** " 320kbps", " 256-320kbps", or '' - appended to the formats. */
export function bitrateText(bitrates: readonly number[] | undefined): string {
  if (!bitrates?.length) return ''
  const low = Math.min(...bitrates)
  const high = Math.max(...bitrates)
  return ` ${low === high ? low : `${low}-${high}`}kbps`
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
