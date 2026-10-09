/**
 * Keeping the desktop visualizer's silent copy in time with the song (2.0.0-player.20) -
 * lib/vizSync.ts, pure: what the player's element is doing goes in, what to do with the analysed copy
 * comes out (player/vizAudio.ts does it).
 *
 * The player's own audio element is never connected to Web Audio; the visualizer analyses a separate,
 * silent copy of the stretch playing - the turntable's FLAC window - started where the element is,
 * paused with it, started again where a seek put it, re-synced past DRIFT_S, and the next window asked
 * for before this one runs out.
 *
 * What it pins:
 *  - nothing playing, no Web Audio, not a FLAC, windows refused: the copy stops, nothing is asked, and
 *    (but for nothing playing) one plain line says the song can't be seen; a context still starting
 *    says nothing;
 *  - paused or stalled: the copy stops with the element, nothing is asked;
 *  - playing: the window asked for from VIZ_BACK_S before the playhead on the VIZ_GRID_S grid; not asked
 *    again while one is on its way that will cover it, or within VIZ_RETRY_MS of a failure (said);
 *  - inside the window: started at the playhead; left alone while within DRIFT_S; started again past
 *    it, on a seek, on a fresh window, on a song change; stopped outside it and at its very end;
 *  - the next window asked VIZ_AHEAD_S before the end, always moving on (a short window never asks for
 *    itself again), never past the song's end; the margins shrink with a window deadwax cut short;
 *  - each song's refusal, failure, window length, window on its way and window held its own: another
 *    song's never stands for this one's;
 *  - the NEXT song's first window asked in this one's last VIZ_AHEAD_S, once this one needs nothing and
 *    nothing is on its way (and even while this one can't be seen) - never for a next song that isn't a
 *    FLAC, is refused, failed under VIZ_RETRY_MS ago or is in hand; taken up as it starts (takeAhead);
 *  - a whole song played through a fake copy: a handful of windows, every one asked ahead, the copy
 *    never running outside its window, never further than DRIFT_S from the element; and two songs back
 *    to back, gaplessly: the second's copy running from its first frame.
 *  - the player's speed (2.0.0-player.39): the copy where its anchor and its rate say (copyAt), carried
 *    on without a jump through a change of rate (reanchor); a whole song at 1.5x and at 2x through a copy
 *    playing at the speed - started once per window and never re-synced, never further than DRIFT_S -
 *    where a copy left at 1x is re-synced over and over.
 *
 * Run it with:  node ui/test/vizsync.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-vizsync-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/vizSync.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const sync = require(path.join(OUT, 'vizSync.js'))
const { planSync, takeAhead, vizMargins, windowFrom, copyAt, reanchor, VIZ_WINDOW_S, VIZ_BACK_S, VIZ_GRID_S, VIZ_AHEAD_S, DRIFT_S, VIZ_RETRY_MS, END_GUARD_S } = sync

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const SONG = { id: 'a', length: 300, flac: true, maxRate: null }
const NEXT = { id: 'b', length: 200, flac: true, maxRate: null }
const base = (over = {}) => ({
  song: SONG, following: null, running: true, position: 50, now: 1000, audio: 'running',
  held: null, ahead: null, pending: null, source: null, refused: [], failed: [], span: null, ...over,
})
const plan = (over) => planSync(base(over))
const held = (start, end, key = 1, song = 'a') => ({ song, start, end, key })
const brief = (p) => [p.stop, p.start, p.fetch, p.seeing]

console.log('\nthe constants')
check('a 40 s window from 2 s back on a 2 s grid, asked again 6 s before its end; re-synced past 0.25 s; a failure asked again after 10 s',
  [VIZ_WINDOW_S, VIZ_BACK_S, VIZ_GRID_S, VIZ_AHEAD_S, DRIFT_S, VIZ_RETRY_MS, END_GUARD_S], [40, 2, 2, 6, 0.25, 10000, 0.1])
check('a window starts 2 s before the playhead, on the grid, never below 0', [windowFrom(50, 2), windowFrom(51.9, 2), windowFrom(0.5, 2), windowFrom(101, 2)], [48, 48, 0, 98])
const margins = (span) => Object.fromEntries(Object.entries(vizMargins(span)).map(([k, v]) => [k, Math.round(v * 1000) / 1000]))
check('margins whole for a whole window, in proportion for one cut short (13 s of a hi-res song)',
  [margins(40), margins(13), margins(80)], [{ back: 2, ahead: 6 }, { back: 0.65, ahead: 1.95 }, { back: 2, ahead: 6 }])

console.log('\nwhen there is nothing to see')
check('nothing playing: nothing asked, nothing said', [brief(plan({ song: null })), plan({ song: null }).why], [[false, null, null, 'nothing'], null])
check('...a copy still running is stopped', plan({ song: null, source: { song: 'a', key: 1, at: 50 } }).stop, true)
check('no Web Audio: the copy stops, nothing asked, and one plain line says so',
  [brief(plan({ audio: 'none', source: { song: 'a', key: 1, at: 50 } })), plan({ audio: 'none' }).why],
  [[true, null, null, 'unseen'], "This browser can't analyse sound, so the song can't be seen."])
check('a context still starting (its resume on the way, the page hidden): nothing asked, nothing said',
  [brief(plan({ audio: 'starting' })), plan({ audio: 'starting' }).why], [[false, null, null, 'waiting'], null])
check('not a FLAC: nothing asked - the song can\'t be seen, said plainly',
  [brief(plan({ song: { ...SONG, flac: false } })), plan({ song: { ...SONG, flac: false } }).why],
  [[false, null, null, 'unseen'], "This song can't be seen - it isn't a FLAC file."])
check('its windows refused (deadwax\'s 415, or a window the browser couldn\'t decode): the same, in their words',
  [brief(plan({ refused: [{ song: 'a', why: "this browser couldn't read its sound" }] })), plan({ refused: [{ song: 'a', why: "this browser couldn't read its sound" }] }).why],
  [[false, null, null, 'unseen'], "This song can't be seen - this browser couldn't read its sound."])
check('...another song\'s refusal is not this one\'s', plan({ refused: [{ song: 'b', why: 'x' }] }).seeing, 'waiting')

console.log('\npaused, or stalled')
check('paused: the copy stops with the element, nothing asked, nothing said',
  [brief(plan({ running: false, held: held(48, 88), source: { song: 'a', key: 1, at: 50 } })), plan({ running: false }).why], [[true, null, null, 'paused'], null])
check('...and with no copy running, nothing to stop', brief(plan({ running: false, held: held(48, 88) })), [false, null, null, 'paused'])

console.log('\nplaying: the window')
check('no window: asked from 2 s back on the grid, the screen waiting', brief(plan({ position: 51.3 })), [false, null, 48, 'waiting'])
check('...not asked again while one is on its way that will cover it', brief(plan({ position: 51.3, pending: { song: 'a', from: 48, to: 88 } })), [false, null, null, 'waiting'])
check('...but asked when the one on its way won\'t (a seek away from it)', plan({ position: 150, pending: { song: 'a', from: 48, to: 88 } }).fetch, 148)
check('...nor while the last ask failed under 10 s ago - said, in a plain line',
  [brief(plan({ failed: [{ song: 'a', why: "deadwax couldn't send its sound", until: 5000 }] })), plan({ failed: [{ song: 'a', why: "deadwax couldn't send its sound", until: 5000 }] }).why],
  [[false, null, null, 'unseen'], "This song can't be seen just now - deadwax couldn't send its sound."])
check('...asked again once the 10 s are up', plan({ now: 5000, failed: [{ song: 'a', why: 'x', until: 5000 }] }).fetch, 48)
check('a window covering the playhead and what comes next: nothing asked', plan({ held: held(48, 88), source: { song: 'a', key: 1, at: 50 } }).fetch, null)
check('the next asked 6 s before the end - and it moves on', [plan({ position: 81.5, held: held(48, 88), source: { song: 'a', key: 1, at: 81.5 } }).fetch,
  plan({ position: 82.5, held: held(48, 88), source: { song: 'a', key: 1, at: 82.5 } }).fetch], [null, 80])
check('a window shorter than claimed never asks for itself again: from 98, it would start where it does', plan({ position: 101, held: held(100, 104) }).fetch, null)
check('...and with the margins shrunk to its span, the next moves on (13 s of a hi-res song)',
  [plan({ position: 111.2, held: held(100, 113), span: { song: 'a', seconds: 13 } }).fetch, plan({ position: 110.5, held: held(100, 113), span: { song: 'a', seconds: 13 } }).fetch], [110, null])
check('near the song\'s end it asks for nothing past it: the window ending with the song is enough',
  plan({ position: 297, held: held(260, 300), song: { ...SONG, length: 300 }, source: { song: 'a', key: 1, at: 297 } }).fetch, null)

console.log('\nplaying: the copy')
check('inside the window with no copy: started at the playhead', brief(plan({ position: 50, held: held(48, 88) })), [false, 50, null, 'seen'])
check('a copy running in time: left alone', brief(plan({ position: 50, held: held(48, 88), source: { song: 'a', key: 1, at: 50.2 } })), [false, null, null, 'seen'])
check('...drifted past 0.25 s (a stall, a clock apart): started again where the element is', plan({ position: 50, held: held(48, 88), source: { song: 'a', key: 1, at: 50.3 } }).start, 50)
check('...behind it as well as ahead', plan({ position: 50, held: held(48, 88), source: { song: 'a', key: 1, at: 49.7 } }).start, 50)
check('a seek inside the window: started there', plan({ position: 70, held: held(48, 88), source: { song: 'a', key: 1, at: 52 } }).start, 70)
check('a seek outside it: the copy stops and that window is asked for', brief(plan({ position: 200, held: held(48, 88), source: { song: 'a', key: 1, at: 52 } })), [true, null, 198, 'waiting'])
check('a fresh window decoded: started on it, at the playhead', plan({ position: 84, held: held(80, 120, 2), source: { song: 'a', key: 1, at: 84 } }).start, 84)
check('a song change: another song\'s copy is never left running - started on this song\'s window, or stopped and its window asked',
  [plan({ position: 3, held: held(0, 40, 3), source: { song: 'z', key: 2, at: 120 } }).start,
    brief(plan({ position: 3, held: held(80, 120, 2, 'z'), source: { song: 'z', key: 2, at: 120 } }))],
  [3, [true, null, 0, 'waiting']])
check('...another song\'s copy never counts as this one\'s, even under the same window number',
  plan({ position: 3, held: held(0, 40, 1), source: { song: 'z', key: 1, at: 3 } }).start, 3)
check('at the very end of its window: not started, a copy there stopped', [plan({ position: 87.95, held: held(48, 88) }).start,
  plan({ position: 87.95, held: held(48, 88), source: { song: 'a', key: 1, at: 87.95 } }).stop], [null, true])

console.log('\neach song\'s own: another song\'s never stands for this one\'s')
check('another song\'s failure doesn\'t hold this one back, nor say it can\'t be seen',
  [brief(plan({ position: 51.3, failed: [{ song: 'b', why: 'x', until: 5000 }] })), plan({ position: 51.3, failed: [{ song: 'b', why: 'x', until: 5000 }] }).why],
  [[false, null, 48, 'waiting'], null])
check('another song\'s short windows don\'t shrink this one\'s margins (13 s of a hi-res song next door)',
  plan({ position: 51.3, span: { song: 'b', seconds: 13 } }).fetch, 48)
check('another song\'s window on its way doesn\'t count as this one\'s', plan({ position: 51.3, pending: { song: 'b', from: 48, to: 88 } }).fetch, 48)
check('another song\'s window held - the same stretch - is never started as this one\'s',
  brief(plan({ position: 50, held: held(48, 88, 1, 'b') })), [false, null, 48, 'waiting'])

console.log('\nthe next song\'s first window, fetched ahead')
{
  const near = (over = {}) => plan({ position: 296, following: NEXT, held: held(260, 300), source: { song: 'a', key: 1, at: 296 }, ...over })
  check('in the song\'s last 6 s, with its window covering the rest and nothing on its way: the next song\'s window from 0',
    [near().fetch, near().prefetch, near().seeing], [null, 0, 'seen'])
  check('...not before those 6 s', [near({ position: 293.9, source: { song: 'a', key: 1, at: 293.9 } }).prefetch, near({ position: 294, source: { song: 'a', key: 1, at: 294 } }).prefetch], [null, 0])
  check('...not while this song still needs a window of its own (that first)',
    [plan({ position: 296, following: NEXT, held: held(200, 240) }).fetch, plan({ position: 296, following: NEXT, held: held(200, 240) }).prefetch], [294, null])
  check('...not while anything is on its way - this song\'s, or the next one\'s already asked',
    [near({ pending: { song: 'a', from: 280, to: 300 } }).prefetch, near({ pending: { song: 'b', from: 0, to: 40 } }).prefetch], [null, null])
  check('...not when the next song is in hand already', near({ ahead: held(0, 40, 2, 'b') }).prefetch, null)
  check('...not for a next song that isn\'t a FLAC, is refused, or failed under 10 s ago - asked again once they are up',
    [near({ following: { ...NEXT, flac: false } }).prefetch, near({ refused: [{ song: 'b', why: 'x' }] }).prefetch,
      near({ failed: [{ song: 'b', why: 'x', until: 5000 }] }).prefetch, near({ now: 5000, failed: [{ song: 'b', why: 'x', until: 5000 }] }).prefetch],
    [null, null, null, 0])
  check('...nor while paused, with no next song, a song of unknown length, or the song itself next',
    [near({ running: false }).prefetch, near({ following: null }).prefetch, near({ song: { ...SONG, length: 0 } }).prefetch, near({ following: SONG }).prefetch],
    [null, null, null, null])
  check('...and even while this song can\'t be seen (not a FLAC, or refused): the next may be',
    [plan({ position: 296, following: NEXT, song: { ...SONG, flac: false } }).prefetch, plan({ position: 296, following: NEXT, refused: [{ song: 'a', why: 'x' }] }).prefetch,
      plan({ position: 296, following: NEXT, refused: [{ song: 'a', why: 'x' }] }).seeing], [0, 0, 'unseen'])
  //? the song changes to it: the window fetched ahead is the one held
  const a = held(260, 300, 1, 'a'), b = held(0, 40, 2, 'b')
  check('as the next song starts, its window fetched ahead becomes the one held, at once started at the playhead',
    [takeAhead(a, b, 'b', 'c'), brief(plan({ song: NEXT, position: 0.02, held: b, source: { song: 'a', key: 1, at: 299.9 } }))],
    [{ held: b, ahead: null }, [false, 0.02, null, 'seen']])
  check('...kept while this song plays and it is next; let go once a skip passes it by; never over this song\'s own',
    [takeAhead(a, b, 'a', 'b'), takeAhead(a, b, 'a', 'c'), takeAhead(b, held(0, 40, 3, 'b'), 'b', 'c')],
    [{ held: a, ahead: b }, { held: a, ahead: null }, { held: b, ahead: held(0, 40, 3, 'b') }])
}

console.log('\na whole song played through a fake copy')
{
  //? a 4-minute song played from 0 at 60 frames a second; windows arrive 0.6 s after they are asked
  //? for; the copy keeps the same clock as the element, so it drifts only through a stall
  const song = { id: 's', length: 240, flac: true, maxRate: null }
  let t = 0, position = 0, heldW = null, pending = null, source = null, keys = 0
  const asked = [], starts = []
  let outside = 0, worst = 0, early = 0
  const arrive = []
  for (let frame = 0; frame < 240 * 60; frame++) {
    t = frame / 60
    //? a stall at 100 s: the element holds still for 2 s while "playing"... then carries on
    const stalled = t >= 100 && t < 102
    if (!stalled) position += 1 / 60
    while (arrive.length && arrive[0].at <= t) {
      const w = arrive.shift()
      keys += 1
      heldW = { song: 's', start: w.from, end: Math.min(240, w.from + 40), key: keys }
      pending = null
    }
    const at = source ? source.at + (t - source.t) : null
    const p = planSync({ song, following: null, running: !stalled, position, now: t * 1000, audio: 'running', held: heldW, ahead: null, pending,
      source: source ? { song: source.song, key: source.key, at } : null, refused: [], failed: [], span: null })
    if (p.stop || p.start !== null) source = null
    if (p.start !== null) {
      source = { song: 's', key: heldW.key, at: p.start, t }
      starts.push(Math.round(p.start * 10) / 10)
    }
    if (p.fetch !== null) {
      asked.push(p.fetch)
      pending = { song: 's', from: p.fetch, to: p.fetch + 40 }
      arrive.push({ from: p.fetch, at: t + 0.6 })
      if (heldW && position >= heldW.end - 1) early += 1
    }
    if (source) {
      const now = source.at + (t - source.t)
      if (now < heldW.start || now > heldW.end) outside += 1
      worst = Math.max(worst, Math.abs(now - position))
    }
  }
  //? each window moves on 32 s (40, less the 2 s back and the 6 s ahead): 40 s fetched for 32 played
  check('eight windows for four minutes, each asked once, ahead of the one before running out - the last ending with the song', asked, [0, 32, 64, 96, 128, 160, 192, 224])
  check('...none of them asked in the last second of the one before', early, 0)
  check('the copy never ran outside its window', outside, 0)
  check('...never further than 0.25 s from the element - the stall stopped it, and it started again where the element was', worst <= DRIFT_S, true)
  check('...started once at the beginning, once per new window, and again after the stall', starts.length, 1 + 7 + 1)
}

console.log('\nthe player\'s speed (2.0.0-player.39): the copy plays at it')
{
  const anchor = { at: 50, time: 10, rate: 1.5 }
  check('where the copy has got to: its anchor on by its rate - 2 s at 1.5x is 3 s of the song', [copyAt(anchor, 12), copyAt({ ...anchor, rate: 0.25 }, 14)], [53, 51])
  const moved = reanchor(anchor, 12, 0.5)
  check('...a change of rate carries it on from where it had got to, no jump - then at the new rate',
    [moved, copyAt(moved, 12), copyAt(moved, 14)], [{ at: 53, time: 12, rate: 0.5 }, 53, 54])
  //? a 4-minute song at the speed, 60 frames a second, through a fake copy: the element and the copy
  //? both at the speed - or the copy left at 1x, which the drift rule then re-syncs over and over
  const whole = (speed, copyRate) => {
    const song = { id: 's', length: 240, flac: true, maxRate: null }
    let position = 0, heldW = null, pending = null, source = null, keys = 0, worst = 0, frames = 0
    const arrive = [], starts = [], asked = []
    for (let frame = 0; position < 239; frame++) {
      const t = frame / 60
      position = Math.min(240, position + speed / 60)
      while (arrive.length && arrive[0].at <= t) {
        const w = arrive.shift()
        keys += 1
        heldW = { song: 's', start: w.from, end: Math.min(240, w.from + 40), key: keys }
        pending = null
      }
      const at = source ? copyAt(source.anchor, t) : null
      const p = planSync({ song, following: null, running: true, position, now: t * 1000, audio: 'running', held: heldW, ahead: null, pending,
        source: source ? { song: 's', key: source.key, at } : null, refused: [], failed: [], span: null })
      if (p.stop || p.start !== null) source = null
      if (p.start !== null) {
        source = { key: heldW.key, anchor: { at: p.start, time: t, rate: copyRate } }
        starts.push(p.start)
      }
      if (p.fetch !== null) {
        asked.push(p.fetch)
        pending = { song: 's', from: p.fetch, to: p.fetch + 40 }
        arrive.push({ from: p.fetch, at: t + 0.6 })
      }
      if (source) worst = Math.max(worst, Math.abs(copyAt(source.anchor, t) - position))
      frames = frame
    }
    return { starts: starts.length, windows: asked.length, worst, seconds: frames / 60 }
  }
  for (const speed of [1.5, 2]) {
    const run = whole(speed, speed)
    check(`a 4-minute song at ${speed}x, the copy at ${speed}x: done in ${Math.round(240 / speed)} s, started once a window and never re-synced, never ${DRIFT_S} s from the element`,
      [Math.round(run.seconds), run.starts, run.windows, run.worst <= DRIFT_S], [Math.round(239 / speed), run.windows, 8, true])
  }
  const wrong = whole(1.5, 1)
  check('...a copy left at 1x under a song at 1.5x is re-synced over and over - what the copy\'s rate saves', wrong.starts > 4 * wrong.windows, true)
}

console.log('\ntwo songs back to back, gaplessly')
{
  //? a 60 s song and then a 50 s one, the second starting the frame the first ends; windows arrive
  //? 0.6 s after they are asked for; the fake copy follows vizAudio.ts - a window decoded for the song
  //? playing is held, for another one ahead, and takeAhead takes it up as its song starts
  const songs = [{ id: 'x', length: 60, flac: true, maxRate: null }, { id: 'y', length: 50, flac: true, maxRate: null }]
  let heldW = null, ahead = null, pending = null, source = null, keys = 0
  const arrive = [], asked = []
  let idleWhilePlaying = 0, firstFrameOfY = null
  const FRAMES = 110 * 60
  for (let frame = 0; frame < FRAMES; frame++) {
    const t = frame / 60
    const onFirst = t < 60
    const song = onFirst ? songs[0] : songs[1]
    const following = onFirst ? songs[1] : null
    const position = onFirst ? t : t - 60
    while (arrive.length && arrive[0].at <= t) {
      const w = arrive.shift()
      keys += 1
      const decoded = { song: w.song, start: w.from, end: Math.min(w.length, w.from + 40), key: keys }
      if (w.song === song.id) heldW = decoded
      else ahead = decoded
      if (pending && pending.song === w.song) pending = null
    }
    const taken = takeAhead(heldW, ahead, song.id, following ? following.id : null)
    heldW = taken.held
    ahead = taken.ahead
    const at = source ? source.at + (t - source.t) : null
    const p = planSync({ song, following, running: true, position, now: t * 1000, audio: 'running', held: heldW, ahead, pending,
      source: source ? { song: source.song, key: source.key, at } : null, refused: [], failed: [], span: null })
    if (p.stop || p.start !== null) source = null
    if (p.start !== null) source = { song: song.id, key: heldW.key, at: p.start, t }
    const ask = p.fetch !== null ? { song, from: p.fetch } : p.prefetch !== null ? { song: following, from: p.prefetch } : null
    if (ask) {
      asked.push(`${ask.song.id}@${ask.from}`)
      pending = { song: ask.song.id, from: ask.from, to: ask.from + 40 }
      arrive.push({ song: ask.song.id, from: ask.from, length: ask.song.length, at: t + 0.6 })
    }
    //? (a song's last END_GUARD_S has nothing left to see by design: not counted)
    if (!source && position < song.length - END_GUARD_S - 1e-9) idleWhilePlaying += 1
    if (!onFirst && firstFrameOfY === null && source && source.song === 'y') firstFrameOfY = frame - 60 * 60
  }
  check('the second song\'s first window asked in the first one\'s last seconds - every window asked once', asked, ['x@0', 'x@32', 'y@0', 'y@32'])
  check('...so its copy runs from its very first frame - no standing still at the song change', firstFrameOfY, 0)
  check('...and the copy stood still only while the first song\'s first window was on its way (0.6 s) - each song\'s last 0.1 s, left out by design, aside', idleWhilePlaying, 36)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
