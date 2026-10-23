import { useEffect, useMemo } from 'preact/hooks'

import { ApiError, currentSession } from '../api/http'
import { latestOnly } from '../lib/latest'
import { current } from '../lib/playQueue'
import {
  BEACON_MAX, DEADWAX_CLIENT, RESUME_AT_WAIT_MS, RESUME_FOCUS_GRACE_MS, RESUME_FULL_WAIT_MS, RESUME_RECHECK_MS, changedSince,
  deviceLabel, pickedUpWords, resumed, saveDue, toSave, utf8Length, type QueueAnswer, type SaveBaseline, type SaveClock,
  type SaveTrigger,
} from '../lib/resume'
import type { UpNextQueue } from '../lib/upNext'
import { album, playedAlbum, rememberAdded, resumeQueue, saveQueue, saveQueueAt, type SavedQueue, type Song } from '../player/api'
import type { Player } from '../player/usePlayer'
import { readPlayerDevice, readPlayerNormalization } from '../state/persisted'
import { sayPins } from './usePins'
import { shuffledTrack } from './useShuffleFeed'

/** What of the player this reads - and its one action, restoreQueue. */
export type ResumePlayer = Pick<Player, 'queue' | 'playing' | 'position' | 'onPosition' | 'restoreQueue'>

/** A wait's few ms over its rule, so the wall clock it is judged by has always passed it. */
const MARGIN_MS = 50
/** The triggers held while a request was out, asked again in this order once it is answered: a pause's (or a 409's)
 *  at once, then a wait's, then the 30 s count's - each by its own rule, so a save already made isn't made twice. */
const OWED_ORDER: readonly SaveTrigger[] = ['pause', 'wait', 'position']

/**
 * Resume what was playing (2.0.0-player.64), the page's half: called ONCE, in App, after useShuffleFeed - see
 * lib/resume.ts for the rules it acts on, and notes/app.md "Resume what was playing".
 *
 * PUTTING BACK. Once the app is drawn (with logins on, after the sign-in), with the player's queue empty, it asks
 * deadwax for the person's play queue (GET /deadwax/navidrome/queue) and puts back what resumed() makes of it with
 * player.restoreQueue - paused, at the second it stopped, nothing loaded or fetched: the next play starts it, in its
 * tap. The answer is used only while the queue is still the one it was asked for (a tap meanwhile wins) and nothing
 * plays. Coming back to the front (visible, pageshow, and a window's focus RESUME_FOCUS_GRACE_MS after it, so the click
 * that focused it lands first - at most every RESUME_RECHECK_MS, never while playing) it
 * asks again: an empty queue, or one put back and untouched since, takes what is newer; a queue paused after playing
 * here takes only what another device of deadwax's or another app saved since this page last did, and only with
 * logins on (with them off everyone shares one queue, and a paused player never takes somebody else's); with changes
 * not yet saved it saves them instead, and asks nothing. The notice says where it came from, once ("Picked up from
 * your Mac") - a queue put back and untouched, taken again from the same place with the same songs (the phone playing
 * on), says nothing again; the song's album is asked once and remembered for Info, if that song still shows, and not
 * asked again while it is in hand.
 *
 * SAVING follows this page's own playing - a queue merely put back is the baseline, so opening the app writes nothing:
 * a FULL save (POST /queue - the window's ids, the index, the second, the snapshot) when the songs or Up Next changed,
 * RESUME_FULL_WAIT_MS after the last change; a POSITION save (POST /queue/at, against the full save's ids_rev) at a
 * song change RESUME_AT_WAIT_MS after, at a pause at once, every RESUME_EVERY_S of playing counted by the player's own
 * position updates (not a timer: a locked phone's timers may sleep while 'timeupdate' still comes), and after a scrub
 * while paused; and whatever is due as the page goes away (hidden, pagehide) - a position save by sendBeacon, a full
 * one `keepalive` while its body's bytes, with the other keepalive saves still out, fit BEACON_MAX. One request at a time (a save due meanwhile waits for it); a failure
 * is tried again at the next trigger, at most every 30 s; a 409 (another device replaced the ids) a full save now; a
 * 401 stops saving until someone signs in again; an answer of no rev (the break-glass admin, who keeps no queue) for
 * good. Neither ask needs a secure page.
 *
 * It calls nothing of the player but restoreQueue (ui/test/app-rules.sim.cjs): nothing here plays.
 */
export function useResume(player: ResumePlayer): void {
  const resume = useMemo(createResume, [])
  //? the render's queue and play state, kept as they are drawn - a render comes reliably after every change, where an
  //? effect waits for the next frame, which a locked phone may not draw. Bookkeeping only: what it asks for is sent
  //? after this render, never during it
  resume.render(player)
  useEffect(() => resume.mount(), [])
}

export interface Resume {
  render(player: ResumePlayer): void
  mount(): () => void
}

const sameIds = (queue: UpNextQueue, ids: readonly string[]) => queue.tracks.length === ids.length && queue.tracks.every((track, i) => track.id === ids[i])

/** What an answer was, to tell a newer one from the one taken last. */
function signature(answer: QueueAnswer<Song>): string {
  if (answer.kept) return `kept:${answer.kept.rev}`
  return `${answer.changed_by}|${answer.index}|${answer.position}|${answer.tracks.map((song) => song.id).join(',')}`
}

export function createResume(): Resume {
  const device = readPlayerDevice()
  const label = deviceLabel(typeof navigator !== 'undefined' ? navigator.userAgent ?? '' : '',
    typeof navigator !== 'undefined' ? navigator.maxTouchPoints ?? 0 : 0)
  let player: ResumePlayer | null = null
  //? the queue and play state as last drawn (render() compares the next drawing with them)
  let queue: UpNextQueue | null = null
  let playing = false
  const clock: SaveClock = { saved: null, idsRev: null, countFrom: null, changedAt: null, failedAt: null }
  //? the rev this page last saved, or took; whether the queue is everyone's (logins off), as deadwax last said
  let lastRev: number | null = null
  let shared: boolean | null = null
  //? a queue put back, while nothing has been done to it
  let parked: { queue: UpNextQueue; position: number } | null = null
  //? what was put back last; when deadwax was last asked
  let taken: string | null = null
  let askedAt = -Infinity
  let flying = 0
  //? the bytes of keepalive saves still out - the browser's 64 KiB is for all of them together
  let keepaliveOut = 0
  //? where the notice last said a queue came from, and that queue's songs
  let said: { from: string; ids: string } | null = null
  //? what came while a request was out, asked again once it is answered - the most pressing first
  const owed = new Set<SaveTrigger>()
  //? deadwax keeps no queue for whoever this is (the break-glass admin); a 401 under this session
  let off = false
  let signedOutUnder: number | null = null
  let fullWait: ReturnType<typeof setTimeout> | undefined
  let atWait: ReturnType<typeof setTimeout> | undefined
  let focusWait: ReturnType<typeof setTimeout> | undefined
  const asks = latestOnly()
  const albums = latestOnly()

  const later = (work: () => void) => {
    void Promise.resolve().then(work)
  }

  function wait(kind: 'full' | 'at') {
    if (kind === 'full') {
      clearTimeout(fullWait)
      fullWait = setTimeout(() => consider('wait'), RESUME_FULL_WAIT_MS + MARGIN_MS)
    } else {
      clearTimeout(atWait)
      atWait = setTimeout(() => consider('wait'), RESUME_AT_WAIT_MS + MARGIN_MS)
    }
  }

  function consider(trigger: SaveTrigger) {
    if (off || !player || !queue) return
    if (signedOutUnder !== null) {
      if (currentSession() === signedOutUnder) return
      signedOutUnder = null
    }
    const position = player.position()
    const now = Date.now()
    const due = saveDue(clock, queue, position, playing, now, trigger)
    if (!due) return
    //? one at a time - but the page going away sends what it must at once
    if (flying > 0 && trigger !== 'hidden') {
      owed.add(trigger)
      return
    }
    send(due, queue, position, trigger === 'hidden', now)
  }

  function answered(baseline: SaveBaseline, answer: SavedQueue | null, sentAt: number, full: boolean) {
    if (answer && answer.rev === null) {
      off = true
      return
    }
    clock.saved = baseline
    clock.failedAt = null
    clock.countFrom = sentAt
    if (answer) {
      lastRev = answer.rev
      if (full) clock.idsRev = answer.ids_rev
    }
  }

  function refused(error: unknown, position: boolean) {
    if (error instanceof ApiError && error.status === 401) {
      signedOutUnder = currentSession()
      return
    }
    //? (a position save) the ids changed elsewhere, or aren't the ones kept: saved in full, now
    if (position && error instanceof ApiError && (error.status === 409 || error.status === 422)) {
      clock.idsRev = null
      owed.add('pause')
      return
    }
    clock.failedAt = Date.now()
  }

  function settled() {
    flying -= 1
    if (flying > 0 || owed.size === 0) return
    const triggers = OWED_ORDER.filter((trigger) => owed.has(trigger))
    owed.clear()
    for (const trigger of triggers) {
      consider(trigger)
      if (flying > 0) return
    }
  }

  function send(kind: 'full' | 'at', sending: UpNextQueue, position: number, leaving: boolean, now: number) {
    const shown = { tracks: sending.tracks, upNext: sending.upNext, index: sending.index, position }
    if (kind === 'at' && clock.saved && clock.idsRev !== null) {
      const { start, count } = clock.saved
      const body = { ids_rev: clock.idsRev, index: sending.index - start, position, device, label }
      if (leaving) {
        //? nobody waits for a beacon's answer: taken as saved, so pagehide after hidden sends nothing again
        void saveQueueAt(body, true)
        answered({ ...shown, start, count }, null, now, false)
        return
      }
      flying += 1
      saveQueueAt(body).then((answer) => answered({ ...shown, start, count }, answer, now, false), (error) => refused(error, true))
        .finally(settled)
      return
    }
    const made = toSave(sending, position)
    const body = { ids: made.ids, index: made.index, position, device, label, snapshot: made.snapshot }
    //? bytes, not characters: a title in Japanese is three of them a character, and a keepalive over the browser's
    //? budget is refused outright - sent as an ordinary request instead, which may still get out
    const bytes = leaving ? utf8Length(JSON.stringify(body)) : 0
    const keepalive = leaving && keepaliveOut + bytes <= BEACON_MAX
    if (keepalive) keepaliveOut += bytes
    flying += 1
    saveQueue(body, keepalive).then((answer) => answered({ ...shown, start: made.start, count: made.ids.length }, answer, now, true),
      (error) => refused(error, false)).finally(() => {
      if (keepalive) keepaliveOut -= bytes
      settled()
    })
  }

  /** Whether deadwax holds a queue saved since this page's last save, by another of the person's devices or apps. */
  function newer(answer: QueueAnswer<Song>): boolean {
    if (answer.kept) return answer.kept.device !== device && answer.kept.rev > (lastRev ?? 0)
    return answer.changed_by !== '' && answer.changed_by !== DEADWAX_CLIENT
  }

  function take(answer: QueueAnswer<Song>, why: 'open' | 'front') {
    if (!player || !queue) return
    const back = resumed(answer, answer.tracks.map(shuffledTrack), readPlayerNormalization(), device)
    if (!back) return
    const sign = signature(answer)
    const untouched = parked !== null && parked.queue === queue
    if (why === 'front') {
      if (sign === taken) return
      if (current(queue) && !untouched && (answer.shared || !newer(answer))) return
    }
    const put = player.restoreQueue(back.queue, back.position)
    if (!put) return
    taken = sign
    const position = player.position()
    parked = { queue: put, position }
    clock.saved = { tracks: put.tracks, upNext: put.upNext, index: put.index, position, start: 0, count: put.tracks.length }
    //? a position save is made against deadwax's ids only while the queue put back is exactly them
    clock.idsRev = answer.kept && back.exact && sameIds(put, answer.kept.ids) ? answer.kept.ids_rev : null
    clock.changedAt = null
    clock.failedAt = null
    clock.countFrom = null
    if (answer.kept) lastRev = answer.kept.rev
    clearTimeout(fullWait)
    clearTimeout(atWait)
    //? said once: a queue put back and untouched, taken again from where the notice said with the same songs - the
    //? other device playing on in them - is the same pick-up, its second moved
    const from = back.from ? JSON.stringify(back.from) : null
    const songs = put.tracks.map((track) => track.id).join(',')
    const again = why === 'front' && untouched && said !== null && said.from === from && said.ids === songs
    const words = again ? null : pickedUpWords(back.from, answer.shared)
    if (words) sayPins(words)
    said = from === null ? null : { from, ids: songs }
    //? the song's album, as a tap would have had it in hand - for Info, the turntable's disc art and Go to album -
    //? unless it is in hand already
    const song = current(put)
    if (song?.albumId && !playedAlbum(song.albumId)) {
      const request = albums.begin()
      album(song.albumId, request.signal).then((found) => {
        if (request.current() && queue && current(queue)?.id === song.id) rememberAdded([found])
      }, () => {})
    }
  }

  function ask(why: 'open' | 'front') {
    const asked = queue
    askedAt = Date.now()
    const request = asks.begin()
    resumeQueue(request.signal).then((answer) => {
      if (!request.current()) return
      shared = answer.shared
      //? a tap since wins: the queue has changed, or music plays
      if (queue !== asked || playing) return
      take(answer, why)
    }, () => {
      //? Navidrome or deadwax not answering: nothing put back - asked again when the app comes back to the front
    })
  }

  function front() {
    if (!player || !queue || playing) return
    if (Date.now() - askedAt < RESUME_RECHECK_MS) return
    if (current(queue) && changedSince(clock.saved, queue, player.position()) !== null) {
      consider('pause')
      return
    }
    const untouched = parked !== null && parked.queue === queue
    //? logins off: a paused player never takes somebody else's queue - nothing to ask for
    if (current(queue) && !untouched && shared === true) return
    ask('front')
  }

  function onPosition(seconds: number) {
    if (parked && Math.abs(seconds - parked.position) > 0.5) parked = null
    later(() => {
      if (!player) return
      if (playing) consider('position')
      else if (clock.saved && Math.abs(player.position() - clock.saved.position) > 1) wait('at')
    })
  }

  return {
    render(next: ResumePlayer) {
      player = next
      const was = queue
      const wasPlaying = playing
      queue = next.queue
      playing = next.playing
      if (was === null) return
      if (parked && (queue !== parked.queue || playing)) parked = null
      if (queue !== was) {
        clock.changedAt = Date.now()
        //? the wait is chosen against what was last SAVED, not the last drawing: an edit not yet saved, then a song
        //? change inside its 2 s, is still a change of the songs - its full wait armed again from now, or (paused, no
        //? position updates to ask) nothing would save it until the page went away or came back
        wait(changedSince(clock.saved, queue, next.position()) === 'songs' ? 'full' : 'at')
      }
      if (playing && !wasPlaying) clock.countFrom = Date.now()
      if (!playing && wasPlaying) later(() => consider('pause'))
    },
    mount() {
      const visibility = () => {
        if (document.visibilityState === 'hidden') consider('hidden')
        else front()
      }
      const leaving = () => consider('hidden')
      //? the click that focused the window lands before anything is asked - see RESUME_FOCUS_GRACE_MS
      const focused = () => {
        clearTimeout(focusWait)
        focusWait = setTimeout(front, RESUME_FOCUS_GRACE_MS)
      }
      document.addEventListener('visibilitychange', visibility)
      globalThis.addEventListener('pageshow', front)
      globalThis.addEventListener('focus', focused)
      globalThis.addEventListener('pagehide', leaving)
      const unsubscribe = player ? player.onPosition(onPosition) : () => {}
      if (queue && !current(queue)) ask('open')
      return () => {
        document.removeEventListener('visibilitychange', visibility)
        globalThis.removeEventListener('pageshow', front)
        globalThis.removeEventListener('focus', focused)
        globalThis.removeEventListener('pagehide', leaving)
        unsubscribe()
        clearTimeout(fullWait)
        clearTimeout(atWait)
        clearTimeout(focusWait)
        asks.supersede()
        albums.supersede()
      }
    },
  }
}
