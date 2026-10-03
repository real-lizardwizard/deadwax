import { useEffect, useState } from 'preact/hooks'

import { getPreferences, putPreferences } from '../api/me'
import {
  GET_SETTINGS_DEFAULT, readGetSettings, seedFromPreferences, type GetSettings, type GetSettingsAnswer,
} from '../lib/getSettings'
import { readPreferences } from '../state/persisted'

/**
 * You > Getting albums, as the server keeps them (2.0.0-player.15): "When I tap Get" and the
 * quality floor, per user (GET/PUT /deadwax/me/preferences). One store for the app - a module, as
 * useOwned is - so You, which changes them, and the Sources sheet, which acts on them, read one
 * answer.
 *
 *  - ASKED when You or Search first shows, each time You's tab is opened, on You's "Check again", and
 *    every time a Get opens the Sources sheet - never as the app starts. They are kept per user so
 *    they follow a person between devices, and a home-screen app stays open for days: an answer in
 *    hand is asked again rather than trusted for the page's life (review), and stands meanwhile.
 *    Until the first answer is in, the settings are the defaults, and a Get shows the sources: the
 *    safe way round, since picking for you is the one that acts without asking.
 *  - SEEDED ONCE: a user nothing was ever saved for (`seeded` false), on a database that can keep
 *    it, gets what this browser's main page already says carried over (deadwax-preferences' quality
 *    floors - lib/getSettings.ts seedFromPreferences) - only what differs from the defaults, and
 *    saved even when that is nothing, since the save is what marks them seeded. From then on the
 *    server's are the settings, and the main page keeps its own copies.
 *  - A CHOICE shows at once and is saved behind it. What shows is the server's last word with every
 *    choice still being saved laid over it, in the order made - so an answer arriving for an older
 *    choice can't put a newer one back, and a choice deadwax won't keep goes back (saying so) to what
 *    the server holds, keeping any later choice still on its way.
 *  - ONE AT A TIME: every save and every read goes in turn, each sent once the one before has
 *    answered, so they reach deadwax - and come back - in the order they were asked. A read's answer
 *    is therefore never older than a save before it, and the server commits the choices in the
 *    order they were made.
 */

/** The server's last word: its answer to the latest read or save, in the order they were sent. */
let confirmed: GetSettingsAnswer | null = null
/** The choices still being saved, oldest first - laid over `confirmed` to make what shows. */
const pending: { values: Partial<GetSettings> }[] = []
let asking: Promise<void> | null = null
/** The first read failed, with nothing in hand: what You says under Getting albums. */
let readProblem: string | null = null
/** The last choice deadwax wouldn't keep, until the next choice. */
let saveProblem: string | null = null
/** This page has carried the main page's floor over (or tried): never twice in one page. */
let seededHere = false
/** Every read and save, one after another. */
let line: Promise<unknown> = Promise.resolve()
const listeners = new Set<() => void>()

const message = (error: unknown) => (error instanceof Error ? error.message : String(error))

function changed(): void {
  for (const listener of [...listeners]) listener()
}

/** Run `work` once everything asked before it has answered, failed or not. */
function inTurn<T>(work: () => Promise<T>): Promise<T> {
  const turn = line.then(work, work)
  line = turn.catch(() => {})
  return turn
}

/** What shows: the server's last word with each choice still being saved laid over it. */
function shown(): GetSettingsAnswer | null {
  if (!confirmed && !pending.length) return null
  return pending.reduce<GetSettingsAnswer>(
    (now, choice) => ({ ...now, ...choice.values }),
    confirmed ?? { ...GET_SETTINGS_DEFAULT, stored: [], seeded: false, can_save: true },
  )
}

/** The settings as the server has them (and as chosen since), or the defaults until it has answered. */
export function getSettingsNow(): GetSettings {
  const now = shown()
  return now ? { get_mode: now.get_mode, quality_floor: now.quality_floor } : GET_SETTINGS_DEFAULT
}

/**
 * Ask the server - once at a time (a second ask while one is out shares it), in turn with the saves.
 * An answer already in hand stands until this one lands. Never rejects.
 */
export function askGetSettings(): Promise<void> {
  if (asking) return asking
  asking = inTurn(async () => {
    try {
      let read = readGetSettings(await getPreferences())
      //? nothing ever saved for this user: carry this browser's main-page floor over, once
      if (read.can_save && !read.seeded && !seededHere) {
        seededHere = true
        try {
          read = readGetSettings(await putPreferences(seedFromPreferences(readPreferences())))
        } catch {
          //? not kept - the defaults stand, and the next page's first read seeds again
        }
      }
      confirmed = read
      readProblem = null
    } catch (reason) {
      //? an answer in hand stands, said nothing against; with none, You says deadwax didn't answer
      if (!confirmed) readProblem = `deadwax didn't answer: ${message(reason)}`
    }
  }).finally(() => {
    asking = null
    changed()
  })
  return asking
}

/**
 * Change one or both: shown at once, saved behind it in turn, and put back if deadwax won't keep
 * it - to what the server holds, with any later choice still being saved kept over it.
 */
export async function chooseGetSettings(values: Partial<GetSettings>): Promise<void> {
  const choice = { values }
  pending.push(choice)
  saveProblem = null
  changed()
  try {
    //? the server's answer to a save is all of the settings, as they stand after it
    confirmed = readGetSettings(await inTurn(() => putPreferences(values)))
  } catch (reason) {
    saveProblem = `Not saved: ${message(reason)}`
  } finally {
    pending.splice(pending.indexOf(choice), 1)
    changed()
  }
}

/** For the sims: forget everything, as a fresh page would. */
export function forgetGetSettings(): void {
  confirmed = null
  pending.length = 0
  asking = null
  readProblem = null
  saveProblem = null
  seededHere = false
  line = Promise.resolve()
}

/**
 * The settings for a component, asked each time `ask` turns true. `settings` is null until the
 * server has answered; `canSave` false when its database won't keep them; `problem` what went wrong
 * last - a choice not kept, or the first read unanswered.
 */
export function useGetSettings(ask: boolean): {
  settings: GetSettings | null
  canSave: boolean
  problem: string | null
} {
  const [, setTick] = useState(0)
  useEffect(() => {
    const listener = () => setTick((n) => n + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
  useEffect(() => {
    if (ask) void askGetSettings()
  }, [ask])
  const now = shown()
  return {
    settings: now ? { get_mode: now.get_mode, quality_floor: now.quality_floor } : null,
    canSave: now?.can_save !== false,
    problem: saveProblem ?? readProblem,
  }
}
