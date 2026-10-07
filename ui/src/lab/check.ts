/**
 * "Check this device" (2.0.0-player.36): what one run of it found, the status line, and the file it gives -
 * pure, so lab.sim.cjs holds them. The file is the way numbers come off James's iPhone over plain http, so
 * a check that stops part way - stopped, or failing a run - still gives one, of every run it finished,
 * saying it is incomplete and why (review of 2.0.0-player.36: a stop or a failure left nothing to save).
 */

import type { Numbers } from './compare'
import type { DeckHealth } from '../lib/deckVoice'

/** One run of "Check this device". */
export interface CheckRun {
  signal: string
  motion: string
  voice: string
  clockStepMs: number | null
  blocks: { late: number; of: number } | null
  /** frames drawn while the motion held the record: how many came late (the page held up), of how many,
   *  and the longest gap - what a stall that the replay can't follow looks like from the page */
  frames: { slow: number; of: number; worstMs: number | null } | null
  /** whether the replay followed the voice (compare.ts replayHeld): when not, the run wants recording again */
  replayHeld: boolean
  numbers: Numbers
  /** the run's recording, as the deck saves it */
  file: string
}

/**
 * A run's counts, from the deck's health as it began and as it ended: the main-thread voice's blocks - the
 * worklet has none to count (only the main-thread voice counts them, deck.ts: a worklet's run read "0 of 0",
 * review of 2.0.0-player.36) - and the page's frames while the record was held. Each the difference, and
 * nothing where the deck's counts went back (it counts from the turntable showing).
 */
export function runCounts(voice: string, before: DeckHealth | null | undefined, after: DeckHealth | null | undefined): Pick<CheckRun, 'blocks' | 'frames'> {
  const both = !!before && !!after
  return {
    blocks: voice === 'script' && both && after!.blocks >= before!.blocks ? { late: after!.lateBlocks - before!.lateBlocks, of: after!.blocks - before!.blocks } : null,
    //? and its longest gap is known only where it was the longest yet
    frames: both && after!.frames >= before!.frames ? {
      slow: after!.slowFrames - before!.slowFrames, of: after!.frames - before!.frames,
      worstMs: after!.worstFrameMs > before!.worstFrameMs ? after!.worstFrameMs : null,
    } : null,
  }
}

/** What a run's "Blocks late" says: none for the worklet, which plays on its own thread and counts none;
 *  the count on the main thread, or "Not known" where the deck's counts went back. */
export function blocksLine(run: Pick<CheckRun, 'voice' | 'blocks'>): string {
  if (run.voice !== 'script') return 'None (an AudioWorklet)'
  return run.blocks ? `${run.blocks.late} of ${run.blocks.of}` : 'Not known'
}

/** What a run's "Frames late" says. */
export function framesLine(run: Pick<CheckRun, 'frames'>): string {
  const frames = run.frames
  if (!frames) return 'Not known'
  return `${frames.slow} of ${frames.of}${frames.slow && frames.worstMs !== null ? `, the longest gap ${Math.round(frames.worstMs)} ms` : ''}`
}

/** How many runs a whole check makes. */
export function checkRuns(signals: number, motions: number): number {
  return signals * motions
}

/** The check as it stands. */
export interface CheckState {
  running: boolean
  /** what it is doing - or, done, 'Done'; stopped, 'Stopped' */
  step: string
  runs: CheckRun[]
  /** why it stopped, when a run failed - null when it finished, or you stopped it */
  error: string | null
  /** you stopped it */
  stoppedByYou: boolean
  /** waiting for a tap to carry on (the page was hidden) */
  waiting: boolean
  /** the file to save, once it has stopped with anything to save */
  href: string | null
  /** how many runs a whole check makes */
  of: number
}

/** The check's status line: what it is doing, or what it did - a stop of yours is just "Stopped". */
export function checkLine(check: CheckState): string {
  if (check.running) return check.step
  const done = check.runs.length
  if (check.error === null && !check.stoppedByYou) return check.step
  const kept = done ? ` Save results has the ${done === 1 ? 'one run' : `${done} runs`} done.` : ''
  if (check.stoppedByYou) return `Stopped after ${done} of ${check.of} runs.${kept}`
  return `Stopped - ${check.error}.${kept}`
}

/** What the saved file holds besides the runs. */
export interface CheckDevice {
  deadwax: string | null
  when: string
  userAgent: string
  secure: boolean | null
  voice: string | null
  contextRate: number | null
}

/** The file "Save results" gives: the device, every run's numbers and recording - and, for a check that
 *  stopped part way, that it is incomplete and why. */
export function checkFile(runs: CheckRun[], device: CheckDevice, stop: { complete: boolean; why: string | null }): Record<string, unknown> {
  return {
    bench: 'deadwax turntable test bench', version: 1, ...device,
    complete: stop.complete, ...(stop.complete ? {} : { stoppedBecause: stop.why }),
    runs: runs.map(({ file, ...rest }) => ({ ...rest, recording: JSON.parse(file) as unknown })),
  }
}
