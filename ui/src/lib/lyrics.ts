/**
 * Lyrics, in words and on a clock. Pure, so the album button, the bulk run and the track view
 * all say the same thing about the same result.
 */

import type { LyricsSummary } from '../api/types'

/** Tracks that have lyrics on disk after a fetch - the ones it wrote and the ones already there. */
export function lyricsOnDisk(summary: LyricsSummary): number {
  return summary.written + summary.replaced + summary.kept
}

/**
 * One sentence for what a fetch did, in the order you want to read it: what was saved, then
 * what LRCLIB simply doesn't have, then what went wrong and is worth another go.
 *
 * "Not on LRCLIB" and "failed" are never merged. The first is a fact about the track, the
 * second is a passing outage - counting them together would tell you neither whether to try
 * again nor whether there is any point.
 */
export function describeLyrics(summary: LyricsSummary): string {
  const saved = summary.written + summary.replaced
  const parts: string[] = []

  parts.push(saved
    ? `saved lyrics for ${saved} track${saved === 1 ? '' : 's'}`
      + (summary.synced ? ` (${summary.synced === saved ? 'all' : summary.synced} synced)` : '')
    : 'no new lyrics')

  if (summary.kept) parts.push(`${summary.kept} already had them`)
  if (summary.missing) parts.push(`${summary.missing} not on LRCLIB`)
  if (summary.instrumental) parts.push(`${summary.instrumental} instrumental`)
  if (summary.untagged) parts.push(`${summary.untagged} need a title and artist tag first`)
  if (summary.failed) parts.push(`${summary.failed} failed - try again`)

  return parts.join(', ')
}

/** What a re-time run did, across however many albums it covered. */
export interface RetimeTotals {
  retimed: number
  unchanged: number
  custom: number
  failed: number
}

/**
 * One sentence for a re-time run. "Left alone" is spelled out, because it is the part that
 * might surprise: those files are not LRCLIB's timings any more - corrected by hand, from
 * somewhere else, or LRCLIB's copy has changed since - and re-timing them would undo that.
 */
export function describeRetime(totals: RetimeTotals): string {
  const parts = [`re-timed ${totals.retimed} track${totals.retimed === 1 ? '' : 's'}`]
  if (totals.unchanged) parts.push(`${totals.unchanged} already at this lead`)
  if (totals.custom) {
    parts.push(`${totals.custom} left alone - not LRCLIB's timings any more, so edited by hand or `
      + 'from somewhere else')
  }
  if (totals.failed) parts.push(`${totals.failed} failed - try again`)
  return parts.join(', ')
}

/** `83.4` -> `1:23`. How a synced line's time is shown beside it. */
export function lyricTime(seconds: number): string {
  const whole = Math.max(0, Math.floor(seconds))
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, '0')}`
}
