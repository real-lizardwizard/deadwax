import type { LyricLine, SongLyrics } from '../api/types'
import { lyricTime } from './lyrics'
import { LANDED_WITHIN_S } from './scrub'

/**
 * Lyrics on Now Playing (2.1.6, notes/app-lyrics.md sections 2 and 3) - James: "I want to make sure you can view
 * lyrics as well", like Apple Music. PURE: the listener's words, and every rule the view (player/Lyrics.tsx) and
 * its answers (app/useLyrics.ts) follow - which line is lit, the dots in a break, when the view follows the song and
 * when the listener's own scroll holds it, the Lyrics button's names. The phone app's Core has the same rules as
 * Lyrics.swift, held to these by an exporter, so each is one exported function or constant.
 *
 * Not in lib/lyrics.ts: that module is the Edit panel's, whose words say "LRCLIB" to whoever runs deadwax. These
 * are a listener's (ui/test/vocabulary.sim.cjs holds this file to them: never "Navidrome", "LRCLIB", "offset",
 * ".lrc" or "sidecar"); lyricTime() alone is shared - how a line's time is said.
 *
 * Pinned by ui/test/lyrics.sim.cjs.
 */

// ----------------------------------------------------------------------------- the words (2.1, verbatim)

/** the Lyrics button's name, off and on ("on" is aria-pressed's, or aria-expanded's on the desktop's bar), and the
 *  desktop panel's title */
export const LYRICS = 'Lyrics'
/** ...when the song playing has none: dimmed while lyrics are off, pressed while they're on */
export const LYRICS_NONE = 'Lyrics - none for this song'
/** ...the phone app only, offline, with none kept for the song - here so both apps' words are one table */
export const LYRICS_NOT_KEPT = 'Lyrics - not on this phone'
/** the spinner's name, while asking */
export const LOADING_LYRICS = 'Loading lyrics'
/** none, where a place must say something - the desktop's panel (a phone's face shows the cover instead) */
export const NO_LYRICS = 'No lyrics for this song.'
/** the desktop's panel with nothing playing - the player bar's own words */
export const NOTHING_PLAYING = 'Nothing playing'
/** plain lyrics, above the first line */
export const NOT_SYNCED = "These lyrics aren't synced to the song."
/** a failure: errorNote's `failed`, said in place of an unreachable's or an other's sentence */
export const LYRICS_FAILED = "Couldn't load the lyrics."
/** a 404: the song isn't the music server's any more (a queue older than a rescan), or isn't theirs - errorNote's
 *  `gone`, in ALBUM_GONE's words (player/AlbumPage.tsx) - and no Try again, which can't find it */
export const SONG_GONE = "This song isn't here any more - it may have been moved or deleted."
/** a line's hint, to VoiceOver (the phone app) */
export const LINE_HINT = 'Plays from here.'
/** the lyrics' VoiceOver action (the phone app) */
export const GO_TO_LIT = 'Go to the line being sung'

// ----------------------------------------------------------------------------- the numbers

/** where the line being sung is held: this share of the lyrics' height from their top (2.5) */
export const LYRICS_ANCHOR = 0.3
/** how long after the listener's scroll stops - its last movement, a fling's coast included - or focus leaving the
 *  lyrics, following comes back, while the song plays (2.5) */
export const FOLLOW_AGAIN_MS = 4000
/** the shortest gap between a break and the next line sung that draws the three dots - an intro too (2.4) */
export const GAP_DOTS_S = 4
/** the next song's lyrics are asked for once the song playing has this long left, while the lyrics show (2.6) */
export const NEXT_LYRICS_S = 20
/** how many songs' answers are kept in memory, the least recently used going first (2.6) */
export const LYRICS_KEPT = 50

// ----------------------------------------------------------------------------- the button (2.7)

/** What is known of the song playing's lyrics: not yet (not asked, being asked, or the ask failed), some (synced or
 *  plain), none - and, the phone app's alone, none kept for it offline. */
export type LyricsHave = 'unknown' | 'some' | 'none' | 'not-kept'

/** What an answer says of the song: none is an answer with no lines. */
export function lyricsHave(lyrics: SongLyrics | null | undefined): LyricsHave {
  if (!lyrics) return 'unknown'
  return lyrics.lines.length ? 'some' : 'none'
}

/** The Lyrics button's name - the same off and on, its state said by aria-pressed (or aria-expanded). */
export function lyricsLabel(have: LyricsHave): string {
  if (have === 'none') return LYRICS_NONE
  if (have === 'not-kept') return LYRICS_NOT_KEPT
  return LYRICS
}

/** Dimmed (aria-disabled, its tap nothing) only while off, and only when it is known it would open nothing: a button
 *  that is on can always be turned off, and while an answer is on its way it is enabled - most songs deadwax filed
 *  have lyrics, so the button starts as it usually ends. */
export function lyricsDimmed(have: LyricsHave, on: boolean): boolean {
  return !on && (have === 'none' || have === 'not-kept')
}

// ----------------------------------------------------------------------------- the clock (2.2)

/** Where the song is, for the lit line: the element's own time (`raw`, player.position()) - unless the last reported
 *  position (usePosition's, which shows a seek's target until it lands) is further from it than a seek lands within:
 *  then a seek is on its way, and its target. So a tap on a line lights it at once, and nothing flickers back while
 *  the seek lands; and at 2x speed the reported position's half second behind is still the element's own. */
export function lyricsClock(raw: number, reported: number): number {
  return Math.abs(raw - reported) > LANDED_WITHIN_S ? reported : raw
}

/** Whether the view's clock runs - once a frame - or stands, redrawing only on a reported position (a seek): only
 *  while the lyrics show, the song plays, nothing is over them and the page is in view. */
export function clockRuns({ shows, playing, covered, visible }: { shows: boolean; playing: boolean; covered: boolean; visible: boolean }): boolean {
  return shows && playing && !covered && visible
}

// ----------------------------------------------------------------------------- the lit line (2.3) and the dots (2.4)

/** The lines lit: inclusive indices, one line, or several written at one time (a duet written once per voice). */
export interface LitRange {
  first: number
  last: number
}

/** The lines whose time is the greatest not after `t`. None before the first timed line (an intro), and none at all
 *  in plain lyrics. The lines are sorted (the server's rule); a binary search. */
export function litRange(lines: readonly LyricLine[], t: number): LitRange | null {
  if (!lines.length || lines[0]!.time === null) return null
  let low = 0
  let high = lines.length - 1
  let found = -1
  while (low <= high) {
    const middle = (low + high) >> 1
    const time = lines[middle]!.time
    if (time !== null && time <= t) {
      found = middle
      low = middle + 1
    } else {
      high = middle - 1
    }
  }
  if (found < 0) return null
  const at = lines[found]!.time
  let first = found
  while (first > 0 && lines[first - 1]!.time === at) first -= 1
  return { first, last: found }
}

/** A line with words - every other line of synced lyrics is a break between verses. */
export function sung(line: LyricLine | undefined): boolean {
  return !!line && line.text !== ''
}

/** The lines as the view draws them: an intro of GAP_DOTS_S or more before the first line sung gets a break at 0, so it
 *  draws the dots as a break does - never a second one when the lyrics already start with a break. */
export function withIntro(lines: readonly LyricLine[]): readonly LyricLine[] {
  const first = lines[0]
  if (!first || first.time === null || !sung(first) || first.time < GAP_DOTS_S) return lines
  return [{ time: 0, text: '' }, ...lines]
}

/** The three dots of break `i` at `t`, 0 to 3: how many are lit - 0 when none are drawn. Only a break drawing them: the
 *  lit one, with the next line sung at least GAP_DOTS_S after it (a break with no line sung after it, an outro, draws
 *  none). The first lights at the break's start, the second a third of the way to the next line, the third two thirds.
 *  Driven by the clock, not an animation: it steps, and reduced motion changes nothing. */
export function gapDots(lines: readonly LyricLine[], i: number, t: number): number {
  const line = lines[i]
  if (!line || sung(line) || line.time === null) return 0
  let next: LyricLine | undefined
  for (let j = i + 1; j < lines.length; j += 1) {
    if (sung(lines[j]) && lines[j]!.time !== null) {
      next = lines[j]
      break
    }
  }
  if (!next || next.time === null) return 0
  const gap = next.time - line.time
  const into = t - line.time
  if (gap < GAP_DOTS_S || into < 0 || t >= next.time) return 0
  if (into >= (gap * 2) / 3) return 3
  if (into >= gap / 3) return 2
  return 1
}

/** What the view draws as the clock moves: the lines lit and the lit break's dots. */
export interface Lit {
  range: LitRange | null
  dots: number
}

/** The view's lit lines at `t` (over withIntro's lines). */
export function litAt(lines: readonly LyricLine[], t: number): Lit {
  const range = litRange(lines, t)
  return { range, dots: range ? gapDots(lines, range.first, t) : 0 }
}

/** Whether two moments draw the same - the view redraws only when they don't. */
export function sameLit(a: Lit, b: Lit): boolean {
  return a.dots === b.dots && a.range?.first === b.range?.first && a.range?.last === b.range?.last
}

// ----------------------------------------------------------------------------- following (2.5)

/** Where the lyrics scroll to put a line whose top is `lineTop` (in the scroller's content) at the anchor of a view
 *  `height` tall. The room after the last line, (1 - LYRICS_ANCHOR) of the height, lets the last line reach it too. */
export function followTop(lineTop: number, height: number): number {
  return Math.max(0, lineTop - height * LYRICS_ANCHOR)
}

/** The room after the last line, so it can be followed to the anchor. */
export function endRoom(height: number): number {
  return Math.max(0, Math.round(height * (1 - LYRICS_ANCHOR)))
}

/** Whether the view follows the song: not while `focused` - the keyboard's or VoiceOver's focus in the lyrics, or a
 *  finger that has scrolled them still on them (the phone's LyricsHold passes its `scrolling` here too); else always,
 *  until the listener's own scroll holds it (`heldAt`, ms) - and then again FOLLOW_AGAIN_MS after that scroll stops,
 *  while the song plays. Paused, it stays where the listener put it: nothing is moving to follow, and someone reading
 *  ahead with the song paused is reading - a play brings it back at once, the wait long past. */
export function follows(now: number, heldAt: number | null, playing: boolean, focused = false): boolean {
  if (focused) return false
  if (heldAt === null) return true
  return playing && now - heldAt >= FOLLOW_AGAIN_MS
}

/** Whether a scroll of the lyrics - the browser's `scroll` event, a movement whatever moved them - moves the hold on to
 *  `now` (2.1.11): it is the listener's scroll still moving - a fling's coast, a wheel's or a trackpad's momentum, a
 *  scroll key's smooth scroll - so the wait counts from where it stops, as the phone's counts from its scroll phase
 *  going idle. Only while their scroll holds following (`heldAt`) and it hasn't come back: following scrolls only
 *  while it follows, so its own scrolls never hold it. */
export function scrollHolds(now: number, heldAt: number | null, playing: boolean): boolean {
  return heldAt !== null && !follows(now, heldAt, playing)
}

// ----------------------------------------------------------------------------- the keyboard (3.6)

/** The lyrics' one tab stop (a roving tabIndex): the line focus is on, else the first sung line lit, else the first
 *  sung line; null with none. */
export function tabStop(lines: readonly LyricLine[], range: LitRange | null, focused: number | null): number | null {
  if (focused !== null && sung(lines[focused])) return focused
  if (range) {
    for (let i = range.first; i <= range.last; i += 1) if (sung(lines[i])) return i
  }
  const first = lines.findIndex((line) => sung(line))
  return first < 0 ? null : first
}

/** Where a key moves focus from line `from`: Up and Down the line sung before or after it, Home and End the first and
 *  the last - null for any other key, or with nowhere to go. */
export function lineAfterKey(lines: readonly LyricLine[], from: number, key: string): number | null {
  const step = (start: number, by: number): number | null => {
    for (let i = start; i >= 0 && i < lines.length; i += by) if (sung(lines[i])) return i
    return null
  }
  if (key === 'ArrowUp') return step(from - 1, -1)
  if (key === 'ArrowDown') return step(from + 1, 1)
  if (key === 'Home') return step(0, 1)
  if (key === 'End') return step(lines.length - 1, -1)
  return null
}

/** The keys that scroll the lyrics - pressed in them, they hold following as a wheel does. (Space isn't one: on a
 *  line it plays from there, a button's own.) */
export const SCROLL_KEYS: readonly string[] = ['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End']

/** A line's time as a screen reader says it - "1:23", and the lit one "1:23, now" (the phone app's value). */
export function lineValue(time: number, lit: boolean): string {
  return lit ? `${lyricTime(time)}, now` : lyricTime(time)
}

// ----------------------------------------------------------------------------- asking (2.6)

/** Whether the next song's lyrics are due: the song playing has NEXT_LYRICS_S or less left (and a known length). */
export function asksAhead(position: number, duration: number): boolean {
  return duration > 0 && duration - position <= NEXT_LYRICS_S
}

/** A kept answer, made the most recently used. */
export function keptLyrics(kept: Map<string, SongLyrics>, id: string): SongLyrics | null {
  const lyrics = kept.get(id)
  if (!lyrics) return null
  kept.delete(id)
  kept.set(id, lyrics)
  return lyrics
}

/** An answer kept, the least recently used going first past LYRICS_KEPT. */
export function keepLyrics(kept: Map<string, SongLyrics>, id: string, lyrics: SongLyrics, most = LYRICS_KEPT): void {
  kept.delete(id)
  kept.set(id, lyrics)
  while (kept.size > most) {
    const oldest = kept.keys().next().value
    if (oldest === undefined) break
    kept.delete(oldest)
  }
}
