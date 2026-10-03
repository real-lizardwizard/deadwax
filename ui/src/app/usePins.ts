import { useEffect, useState } from 'preact/hooks'

import { getPins, putPins, togglePin } from '../api/me'
import { applyPinOp, orderBody, targetName, toggleBody, type Pin, type PinOp, type PinsAnswer, type PinTarget } from '../lib/pins'

/**
 * What the user pinned to Home (2.0.0-player.18), as the server keeps them (GET/PUT /deadwax/me/pins,
 * POST .../toggle - src/routes/pins.py). One store for the app - a module, as useGetSettings is - so
 * Home's Pinned, the album page's and the artist page's pin, and Now Playing's ••• menu read one
 * answer, and a pin made on one shows on the others at once.
 *
 *  - ASKED afresh each time Home comes into view (`usePins('fresh')`): the server checks each album's
 *    Navidrome id as it answers, so an album re-filed since - or pinned on another device - is right
 *    when you look. A page that only needs to know whether its album or artist is pinned asks only
 *    when nothing is in hand or what is in hand is older than PINS_KEPT_MS (`usePins(true)`). Never as
 *    the app starts.
 *  - A CHANGE shows at once and is sent behind it: what shows is the server's last word with each
 *    change still on its way laid over it, in the order made (lib/pins.ts applyPinOp), so a pin's
 *    card is on Home from the tap; a change deadwax won't keep goes back to the server's word, and
 *    says so WHERE IT WAS MADE: a pin or an unpin (an album or artist page, Now Playing's ••• menu)
 *    in the app's one notice (PinNotice, naming what wasn't pinned and why); a move or a removal in
 *    Home's Edit as "Not saved: …" under the list (`problem`), until the next change or a read.
 *  - ONE AT A TIME: every read and every change goes in turn, each sent once the one before has
 *    answered - so they reach deadwax, and come back, in the order asked, and the newest answer is
 *    always the last to land (what latestOnly() does for a fetch that draws). A move or a removal is
 *    made into the PUT's whole list from the server's word as it stands when it goes, with that
 *    word's own list beside it (`known`), so a pin made on another device since this page last asked
 *    keeps its place - deadwax never unpins what the page was never shown.
 */

/** How long an answer in hand stands for a page that only asks whether its album or artist is
 *  pinned, before it is asked again. Home always asks afresh. */
export const PINS_KEPT_MS = 30_000

/** The server's last word, and when it came. */
let confirmed: PinsAnswer | null = null
let confirmedAt = 0
/** The changes still on their way, oldest first - laid over `confirmed` to make what shows. */
const pending: PinOp[] = []
let asking: Promise<void> | null = null
/** The first read failed, with nothing in hand. */
let readProblem: string | null = null
/** The last of Edit's changes deadwax wouldn't keep, until the next change or a read. */
let saveProblem: string | null = null
/** What the app's notice says (PinNotice) - each new one a new `id`, so the same words say again. */
let notice: { text: string; id: number } | null = null
let notices = 0
/** Every read and change, one after another. */
let line: Promise<unknown> = Promise.resolve()
/** Pins made on this page, for their keys until the server names them. */
let made = 0
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

/** What shows: the server's last word with each change still on its way laid over it. */
function shown(): Pin[] | null {
  if (!confirmed && !pending.length) return null
  return pending.reduce<Pin[]>((now, op) => applyPinOp(now, op), confirmed?.pins ?? [])
}

/** The pins as they show now - null until the server has answered (and nothing was changed here). */
export function pinsNow(): Pin[] | null {
  return shown()
}

/**
 * Ask the server - once at a time (a second ask while one is out shares it), in turn with the
 * changes. `fresh` false: only when nothing is in hand, or it is older than PINS_KEPT_MS. An answer
 * in hand stands until this one lands. Never rejects.
 */
export function askPins(fresh = true): Promise<void> {
  if (asking) return asking
  if (!fresh && confirmed && Date.now() - confirmedAt < PINS_KEPT_MS) return Promise.resolve()
  asking = inTurn(async () => {
    try {
      confirmed = await getPins()
      confirmedAt = Date.now()
      readProblem = null
      //? the server's word, read afresh, is what shows now: an old "Not saved" no longer describes it
      saveProblem = null
    } catch (reason) {
      //? an answer in hand stands, said nothing against; with none, Home says why there is none
      if (!confirmed) readProblem = `Couldn't get your pins: ${message(reason)}`
    }
  }).finally(() => {
    asking = null
    changed()
  })
  return asking
}

/** Say something in the app's notice (PinNotice). */
export function sayPins(text: string): void {
  notices += 1
  notice = { text, id: notices }
  changed()
}

/**
 * One change: shown at once, sent in turn, and the server's answer - every pin - taken as its word.
 * A refusal: `refused(reason)` says so where the change was made.
 */
async function send(op: PinOp, request: () => Promise<PinsAnswer>, refused: (reason: string) => void, kept?: () => void): Promise<void> {
  pending.push(op)
  saveProblem = null
  changed()
  try {
    confirmed = await inTurn(request)
    confirmedAt = Date.now()
    readProblem = null
    kept?.()
  } catch (reason) {
    refused(message(reason))
  } finally {
    pending.splice(pending.indexOf(op), 1)
    changed()
  }
}

/**
 * Pin it (on) or unpin it (off) - an album or an artist, by what it is. Called from the tap. A
 * refusal is said in the app's notice, naming it; `say` (the ••• menu, which closes as it is tapped)
 * says the outcome either way.
 */
export function setPinned(target: PinTarget, on: boolean, say = false): Promise<void> {
  const name = targetName(target)
  const refused = (reason: string) => sayPins(`Couldn't ${on ? 'pin' : 'unpin'} ${name}: ${reason}`)
  const kept = say ? () => sayPins(on ? `Pinned ${name} to Home` : `Unpinned ${name} from Home`) : undefined
  if (on) {
    made += 1
    return send({ type: 'pin', target, ref: `pending:${made}` }, () => togglePin(toggleBody(target, true)), refused, kept)
  }
  return send({ type: 'unpin', target }, () => togglePin(toggleBody(target, false)), refused, kept)
}

/** Edit's PUT: the list as `op` leaves the server's word now, made from that word (`known`). */
function editRequest(op: PinOp): () => Promise<PinsAnswer> {
  return () => {
    const word = confirmed?.pins ?? []
    return putPins(orderBody(applyPinOp(word, op), word))
  }
}

const editRefused = (reason: string) => {
  saveProblem = `Not saved: ${reason}`
}

/** Home's Edit: the pin with this key to place `to` - in the list as it shows. */
export function movePin(key: string, to: number): Promise<void> {
  const op: PinOp = { type: 'move', key, to }
  return send(op, editRequest(op), editRefused)
}

/** Home's Edit: the pin with this key unpinned. */
export function removePin(key: string): Promise<void> {
  const op: PinOp = { type: 'remove', key }
  return send(op, editRequest(op), editRefused)
}

/** For the sims: forget everything, as a fresh page would. */
export function forgetPins(): void {
  confirmed = null
  confirmedAt = 0
  pending.length = 0
  asking = null
  readProblem = null
  saveProblem = null
  notice = null
  line = Promise.resolve()
  made = 0
}

/** What the app's notice says now - null for nothing. */
export function pinNotice(): { text: string; id: number } | null {
  return notice
}

/** The notice said: cleared, unless a newer one has replaced it. */
export function clearPinNotice(id: number): void {
  if (notice?.id !== id) return
  notice = null
  changed()
}

/** A component kept in step with the store: drawn again on every change to it. */
function useStore(): void {
  const [, setTick] = useState(0)
  useEffect(() => {
    const listener = () => setTick((n) => n + 1)
    listeners.add(listener)
    return () => {
      listeners.delete(listener)
    }
  }, [])
}

/**
 * The pins for a component, asked each time `ask` turns on - 'fresh' asks the server whatever is in
 * hand (Home coming into view), true only when nothing recent is. `pins` is null until the server has
 * answered; `known` whether it has (or failed to - with nothing in hand, the pin is still usable,
 * and says so then rather than holding a tap for ever); `canSave` false when its database won't keep
 * them; `problem` what went wrong last - one of Edit's changes not kept, or the first read unanswered.
 */
export function usePins(ask: boolean | 'fresh'): {
  pins: Pin[] | null
  known: boolean
  canSave: boolean
  problem: string | null
} {
  useStore()
  useEffect(() => {
    if (ask) void askPins(ask === 'fresh')
  }, [ask])
  const pins = shown()
  const problem = saveProblem ?? readProblem
  return { pins, known: pins !== null || problem !== null, canSave: confirmed?.can_save !== false, problem }
}

/** The app's notice, for PinNotice alone. */
export function usePinNotice(): { text: string; id: number } | null {
  useStore()
  return notice
}
