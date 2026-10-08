/**
 * What the test bench says (2.0.0-player.36): the transport's line as the record's sound starts and stops,
 * and what a comparison's numbers say - each with what it means, and in place of them, when the replay
 * couldn't be held to the recording, why and what to do. Pure, so lab.sim.cjs holds the words to the cases
 * (review of 2.0.0-player.36: a recording nothing took was told as a stall of the page, and the line saying
 * the sound had stopped stayed up after Play had brought it back).
 */

import type { DebugRow } from '../lib/debugRows'
import type { DeckReport } from '../lib/deckVoice'
import { replayVerdict, type Numbers } from './compare'

/** What the transport says as the sound starts, once it runs, and when a hidden page stopped it. */
export const STARTING = 'Starting the sound - turn the record, or have it turned for you, once it says Ready'
export const READY = 'Ready - turn the record, or have it turned for you'
export const SOUND_STOPPED = 'The sound stopped while the page was hidden - press Start the sound, or Play'
/** ...and as a song from the library takes the place of the bench's own (or the other way): the app's path
 *  is a turntable of its own - no window source - so its deck is made afresh, and only a tap starts its
 *  sound (2.0.0-player.37). */
export const SOUND_AGAIN = "The record's sound starts again for this song - press Play, or Start the sound"

/**
 * The transport's line as the record's sound changes, from `was` to `now`: Ready once it runs, after it
 * was starting or a hidden page had stopped it (a tap - Play, Start the sound, the record's own - brings it
 * back); said to have stopped when a hidden page stopped it; anything else left as it is.
 */
export function transportLine(line: string, was: DeckReport['context'] | null, now: DeckReport['context'] | null, hidden: boolean): string {
  if (now === 'running' && was !== 'running') return line === STARTING || line === SOUND_STOPPED || line === SOUND_AGAIN ? READY : line
  if (was === 'running' && now !== 'running' && hidden) return SOUND_STOPPED
  return line
}

/** What a run whose replay didn't follow says in place of reading A against B: a stall of the page. */
export const NOT_HELD = 'The replay didn\'t follow this recording: something held the page up while it played, so the record\'s sound slowed where the movement didn\'t, and B isn\'t deadwax\'s path. Record it again before reading A against B.'
/** ...when nothing took the record while it recorded. */
export const NOT_TAKEN = 'Nothing took the record while it recorded, so there is nothing to set beside an ideal turntable. Press Record, then turn the record (or have it turned for you) - a turn already under way when Record was pressed doesn\'t count: let go, and take it again.'
/** ...when the record's sound said nothing of where it was after it was taken. */
export const NOT_REPORTED = 'The record\'s sound said nothing of where it was after the record was taken - the recording ended too soon after - so there is nothing to hold the replay to. Record again, and keep turning while it records.'

/** Why a recording wants recording again, or null when its replay held. */
export function againLine(numbers: Pick<Numbers, 'fitMs' | 'taken'>): string | null {
  const verdict = replayVerdict(numbers)
  return verdict === 'held' ? null : verdict === 'stalled' ? NOT_HELD : verdict === 'untaken' ? NOT_TAKEN : NOT_REPORTED
}

export const dbText = (db: number) => `${db.toFixed(1)} dB`
export const percent = (value: number | null) => (value === null ? 'not measured' : `${value.toFixed(2)}%`)

/** The replay's own row: how closely it reproduces what was recorded. */
export function replayRow(numbers: Numbers): DebugRow {
  return {
    label: 'The replay',
    value: numbers.replayDb === null ? 'Nothing to hold it to' : `${dbText(numbers.replayDb)} from what was recorded`,
    note: `How closely playing the recording's messages through the voice again here reproduces what it played (lower is closer) - what B and C are built on. Lined up at ${numbers.alignScore.toFixed(4)}${numbers.fitMs === null ? '' : `; the replayed read head within ${numbers.fitMs.toFixed(3)} ms of where the voice said it was`}. The replay can't know exactly when each of the deck's messages reached the voice - least of all on the main thread - so where the speed changes it may be up to a tenth of a millisecond off: too little to hear, or to move the numbers above.`,
  }
}

/**
 * What music has in place of "what isn't the signal" (2.0.0-player.37): on a tone, the sound in A away from
 * the ideal reading's own frequencies is what deadwax added; music has something at nearly every frequency,
 * so there is nowhere for it to show - and a number there would mislead.
 */
export const NOT_ON_MUSIC: DebugRow = {
  label: "What isn't the signal",
  value: 'Not measured on music',
  note: "On a tone, the sound in A away from the ideal reading's own frequencies is what deadwax added. Music has something at nearly every frequency, so there is nowhere for that to show: listen to A against C, and read the speed's wobble and the read head's distance from the smooth path.",
}

/** The numbers, each with what it says - none of them, where the replay couldn't be held to the
 *  recording: they would be a stall's, or of nothing. `music` (a library song or a picked file) says why
 *  there is no "what isn't the signal". */
export function numberRows(numbers: Numbers, music = false): DebugRow[] {
  const again = againLine(numbers)
  if (again) return [{ label: 'Record it again', value: again }, replayRow(numbers)]
  const rows: DebugRow[] = []
  rows.push({
    label: 'Read head off the smooth path',
    value: numbers.strayed ? `${numbers.strayed.maxMs.toFixed(2)} ms at most, ${numbers.strayed.typicalMs.toFixed(2)} ms typically` : 'Not measured',
    note: 'How far deadwax\'s read head strayed from the smooth path through the same movement, in ms of the song.',
  })
  rows.push({
    label: 'Speed wobble above 20 Hz',
    value: `deadwax's path ${percent(numbers.wobble.deadwax)}, the smooth path's ${percent(numbers.wobble.smooth)}`,
    note: 'The speed\'s quick wobble as a share of the speed. Heard as a flutter or a buzz on a tone; a hand moving smoothly has next to none.',
  })
  if (numbers.stray) {
    rows.push({
      label: "What isn't the signal (A against B)",
      value: `${dbText(numbers.stray.db)}${numbers.stray.loudest ? `, the loudest at ${Math.round(numbers.stray.loudest.hz)} Hz, ${dbText(numbers.stray.loudest.db)}` : ''}`,
      note: 'The sound in A away from what the ideal reading has, against the sound at it - by frame, so a slow timing drift counts for nothing. Lower is cleaner: under -60 dB is hard to hear on a tone.',
    })
  } else if (music) rows.push(NOT_ON_MUSIC)
  if (numbers.silenceDb !== null) {
    rows.push({ label: 'Silence, as played', value: `${dbText(numbers.silenceDb)} RMS`, note: 'Anything here is the voice\'s own.' })
  }
  rows.push(replayRow(numbers))
  return rows
}

/** One line of what it means - or why it wants recording again. */
export function meaning(numbers: Numbers): string {
  const again = againLine(numbers)
  if (again) return again
  const parts: string[] = []
  if (numbers.stray) parts.push(`the voice's reading leaves ${dbText(numbers.stray.db)} that isn't the signal`)
  if (numbers.wobble.deadwax !== null && numbers.wobble.smooth !== null) parts.push(`its path wobbles ${percent(numbers.wobble.deadwax)} against the smooth path's ${percent(numbers.wobble.smooth)}`)
  return `If A and C sound alike to you, what you hear is what turning a record at those speeds sounds like. If C is clean and A isn't, deadwax adds it - and the numbers say which part: A against B is how the voice reads the song, B against C the path.${parts.length ? ` Here, ${parts.join('; ')}.` : ''}`
}
