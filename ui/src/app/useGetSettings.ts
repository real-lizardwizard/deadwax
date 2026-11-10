import { useEffect, useState } from 'preact/hooks'

import { getPreferences, putPreferences } from '../api/me'
import type { FormatPreference } from '../api/types'
import {
  GET_SETTINGS_DEFAULT, readGetSettings, seedFromPreferences, type GetSettings, type GetSettingsAnswer,
} from '../lib/getSettings'
import { readDownloadDefaults, readPreferences } from '../state/persisted'
import { sayError } from './sayError'

/**
 * You > Getting albums, as the server keeps them (2.0.0-player.15): "When I tap Get", the quality
 * floor and (2.0.0-player.41) Format, per user (GET/PUT /deadwax/me/preferences). One store for the app - a module, as
 * useOwned is - so You, which changes them, and the Sources sheet, which acts on them, read one
 * answer.
 *
 *  - ASKED when You or Search first shows, each time You's tab is opened, on You's "Check again", every
 *    time a Get opens the Sources sheet, before every search the sheet starts (a Get or a pressing
 *    reaching a desktop panel already open, Try again, a Re-search - review), and each time an album
 *    page shows (2.0.0-player.49: its store line judges a download somebody else asked for against the
 *    quality floor - asked beside the store, so the floor's word is in hand as the line draws, and the
 *    page's own Get has them) - never as the app starts, from a tab mounted hidden. They are kept per user so
 *    they follow a person between devices, and a home-screen app stays open for days: an answer in
 *    hand is asked again rather than trusted for the page's life (review), and stands meanwhile.
 *    Until the first answer is in, the settings are the defaults, and a Get shows the sources: the
 *    safe way round, since picking for you is the one that acts without asking.
 *  - SEEDED ONCE: a user nothing was ever saved for (`seeded` false), on a database that can keep
 *    it, gets what this browser's main page left carried over (deadwax-preferences' quality
 *    floors, and deadwax-download-defaults' Format - lib/getSettings.ts seedFromPreferences) - only
 *    what differs from the defaults, and saved even when that is nothing, since the save is what
 *    marks them seeded. From then on the server's are the settings (the main page kept its own copies
 *    until it retired in 2.0.0-player.66). A setting added in a later version is seeded once in the same way, alone (the server's
 *    `unseeded`): Format, for a user seeded at 2.0.0-player.15 - never the floor again over a choice
 *    made in the app since.
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
    confirmed ?? { ...GET_SETTINGS_DEFAULT, stored: [], seeded: false, unseeded: [], can_save: true },
  )
}

/** The settings as the server has them (and as chosen since), or the defaults until it has answered. */
export function getSettingsNow(): GetSettings {
  const now = shown()
  return now ? { get_mode: now.get_mode, quality_floor: now.quality_floor, format_preference: now.format_preference } : GET_SETTINGS_DEFAULT
}

/**
 * The Format a search is to be scored by (2.0.0-player.41): a promise of it once a read already out
 * has answered - the sheet asks deadwax again just before each search it starts, and that read is
 * what carries a Format changed on another device into a page left open for days (review: the answer
 * in hand went out with the search, and the fresh one landed a moment later, changing nothing).
 * With no read out: at once when the server has answered (or a choice is being saved), as a plain
 * value; otherwise a promise of it once deadwax has been asked - the default if it doesn't answer. A
 * Get reached without You or Search having shown (an album you have, opened from the Library, to its
 * other pressings) would otherwise search by the default, never by the Format chosen. Never rejects
 * (a read never does): a read that fails leaves the answer in hand, and a choice still being saved
 * stays laid over whichever it is.
 */
export function formatPreferenceNow(): FormatPreference | Promise<FormatPreference> {
  if (asking) return asking.then(() => getSettingsNow().format_preference)
  if (shown()) return getSettingsNow().format_preference
  return askGetSettings().then(() => getSettingsNow().format_preference)
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
      //? nothing ever saved for this user - or a setting new since it was - carry this browser's
      //? main-page settings over, once: what is left to carry over (`unseeded`), only what differs
      //? from the defaults
      if (read.can_save && read.unseeded.length && !seededHere) {
        seededHere = true
        try {
          const main = { ...readPreferences(), formatPreference: readDownloadDefaults().formatPreference }
          read = readGetSettings(await putPreferences(seedFromPreferences(main, read.unseeded)))
        } catch {
          //? not kept - the defaults stand, and the next page's first read seeds again
        }
      }
      confirmed = read
      readProblem = null
    } catch (reason) {
      //? an answer in hand stands, said nothing against; with none, You says deadwax didn't answer
      //? (2.0.4) in a listener's words (sayError) - the error's own in brackets for whoever runs deadwax
      if (!confirmed) readProblem = sayError(reason, "Couldn't get these from deadwax.")
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
    saveProblem = sayError(reason, 'Not saved.')
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
    settings: now ? { get_mode: now.get_mode, quality_floor: now.quality_floor, format_preference: now.format_preference } : null,
    canSave: now?.can_save !== false,
    problem: saveProblem ?? readProblem,
  }
}
