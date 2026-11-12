#!/usr/bin/env node
/**
 * The iPhone app's lyrics rules, as the web app's own TypeScript answers them (app 0.4, notes/app-lyrics.md 2 and
 * 4.8): ui/src/lib/lyricsView.ts compiled with the repo's TypeScript - as ui/test/lyrics.sim.cjs compiles it - and run
 * over every case below: the words, the numbers, the button's names and dimming, the clock, the lit line, the
 * intro, the dots, following, the time as VoiceOver says it, the next song's ask and the answers kept. Written to
 *
 *   ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lyrics/lyrics-vectors.json
 *
 * which DeadwaxCoreTests' LyricsTests replays against DeadwaxCore's Lyrics.swift - the port - so a rule changed on
 * the web and not in the app (or the other way about) fails a test.
 *
 *   node ios/scripts/export-lyrics-vectors.cjs           writes the fixture
 *   node ios/scripts/export-lyrics-vectors.cjs --check   fails when the fixture isn't what the TypeScript says now
 *                                                        (ui/test/ioslyrics.sim.cjs runs this in CI)
 *
 * The keyboard's rules (tabStop, lineAfterKey, SCROLL_KEYS) aren't exported: the phone has no tab stop. Every line of
 * lyrics here is invented. Numbers JSON can't hold aren't used - a line's time is a number or null. Needs
 * ui/node_modules (npm install in ui/) and a writable TMPDIR.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lyrics/lyrics-vectors.json')
const CHECK = process.argv.includes('--check')

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-ios-lyrics-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/lyricsView.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const L = require(path.join(OUT, 'lib/lyricsView.js'))
const SC = require(path.join(OUT, 'lib/scrub.js'))
fs.rmSync(OUT, { recursive: true, force: true })

/* ===== the lines ================================================================================= */

const line = (time, text) => ({ time, text })

/** Sets of lines, as the route answers them (synced sorted; plain all null) - each a shape a rule turns on. */
const SETS = {
  //? an intro's break at 0 (LRCLIB's), a verse, a long break, a verse, an outro's break
  verses: [line(0, ''), line(12.5, 'The first line sung'), line(15.25, 'The second line'), line(18, 'A third'),
    line(21, ''), line(33, 'After the guitar'), line(36.5, 'And the last one'), line(40, '')],
  //? no break at 0 - the first line 10 s in: withIntro gives it one
  lateStart: [line(10, 'Late to start'), line(13, 'Then on'), line(16, 'And done')],
  //? the first line sung 3.9 s in: too short an intro for the dots
  shortIntro: [line(3.9, 'Nearly at once'), line(7, 'Next')],
  //? exactly the gap the dots need, and a break whose next line is 3.999 s away
  edges: [line(0, ''), line(4, 'Four seconds in'), line(6, ''), line(9.999, 'Just short'), line(11, ''), line(15, 'Exactly four')],
  //? a duet written once per voice: two lines at one stamp, then a third, then two breaks in a row
  duet: [line(5, 'Me'), line(5, 'You'), line(8, 'Together'), line(9, ''), line(10, ''), line(20, 'Again')],
  //? lines at 0 from the start, a break and no line after it
  fromZero: [line(0, 'At once'), line(2, 'Quickly'), line(4, ''), line(30, '')],
  //? one line
  one: [line(83.4, 'A lone shout')],
  //? plain lyrics: nothing timed
  plain: [line(null, 'Words with no times'), line(null, 'Read as they are'), line(null, 'A joined line\nkeeps its break')],
  //? none
  empty: [],
  //? a line of words that carries a newline, and text in other scripts
  wide: [line(1, 'Line one\nwrapped by hand'), line(2.5, 'Zweite Zeile'), line(4.75, 'Troisi\u00e8me ligne')],
}

/** Times to ask each set at: every stamp, just before and after it, between, before the start, long after. */
function timesFor(lines) {
  const out = new Set([-1, 0, 0.0001, 1, 2, 3, 3.9, 4, 5, 7.5, 9.999, 10, 11.5, 14, 16, 19, 20, 22, 25, 27, 29, 30, 31, 33, 36.5, 41, 60, 83.39, 83.4, 100, 1e6])
  for (const { time } of lines) {
    if (time === null) continue
    for (const t of [time - 0.001, time, time + 0.001]) out.add(Math.round(t * 1e6) / 1e6)
  }
  return [...out].sort((a, b) => a - b)
}

function setVectors(name, lines) {
  const drawn = L.withIntro(lines)
  const times = timesFor(lines)
  return {
    name,
    lines,
    withIntro: drawn,
    sung: lines.map((one) => L.sung(one)),
    at: times.map((t) => ({
      t,
      litRange: L.litRange(lines, t),
      drawnRange: L.litRange(drawn, t),
      litAt: L.litAt(drawn, t),
      gapDots: drawn.map((_, i) => L.gapDots(drawn, i, t)),
    })),
    //? past either end and on a sung line: none drawn
    gapDotsOutside: [-1, drawn.length, drawn.length + 3].map((i) => ({ i, t: 10, dots: L.gapDots(drawn, i, 10) })),
  }
}

/* ===== the rest ================================================================================== */

function grid(as, bs) {
  const out = []
  for (const a of as) for (const b of bs) out.push([a, b])
  return out
}

const answers = [
  { name: 'nothing yet', lyrics: null },
  { name: 'none', lyrics: { synced: false, lines: [] } },
  { name: 'synced', lyrics: { synced: true, lines: [line(1, 'One')] } },
  { name: 'plain', lyrics: { synced: false, lines: [line(null, 'One')] } },
]

const HAVES = ['unknown', 'some', 'none', 'not-kept']

function keptVectors() {
  //? a sequence of keeps and takes on one Map, at `most` 3 and at the default
  //? (the standard run's every step says the order and what came back; only the small one says every value kept)
  const run = (most, steps, values = true) => {
    const kept = new Map()
    return steps.map(([op, id, value]) => {
      let returned = null
      if (op === 'keep') {
        if (most === null) L.keepLyrics(kept, id, value)
        else L.keepLyrics(kept, id, value, most)
      } else {
        returned = L.keptLyrics(kept, id)
      }
      const step = { op, id, value: value ?? null, returned, order: [...kept.keys()] }
      return values ? { ...step, values: [...kept.values()] } : step
    })
  }
  const v = (n) => ({ synced: false, lines: [line(null, `answer ${n}`)] })
  const small = run(3, [
    ['take', 'a'], ['keep', 'a', v(1)], ['keep', 'b', v(2)], ['keep', 'c', v(3)], ['take', 'a'], ['keep', 'd', v(4)],
    ['take', 'b'], ['take', 'c'], ['keep', 'c', v(5)], ['keep', 'e', v(6)], ['take', 'a'], ['take', 'd'], ['keep', 'f', v(7)],
  ])
  const full = []
  for (let n = 0; n < 53; n += 1) full.push(['keep', `s${n}`, v(n)])
  full.push(['take', 's0'], ['take', 's3'], ['keep', 's3', v(99)], ['keep', 'last', v(100)])
  return { small: { most: 3, steps: small }, standard: { most: null, steps: run(null, full, false) } }
}

function vectors() {
  return {
    made_from: 'ui/src/lib/lyricsView.ts (compiled), lib/lyrics.ts lyricTime, lib/scrub.ts LANDED_WITHIN_S',
    words: {
      LYRICS: L.LYRICS, LYRICS_NONE: L.LYRICS_NONE, LYRICS_NOT_KEPT: L.LYRICS_NOT_KEPT, LOADING_LYRICS: L.LOADING_LYRICS,
      NO_LYRICS: L.NO_LYRICS, NOTHING_PLAYING: L.NOTHING_PLAYING, NOT_SYNCED: L.NOT_SYNCED, LYRICS_FAILED: L.LYRICS_FAILED,
      SONG_GONE: L.SONG_GONE, LINE_HINT: L.LINE_HINT, GO_TO_LIT: L.GO_TO_LIT,
    },
    constants: {
      LYRICS_ANCHOR: L.LYRICS_ANCHOR, FOLLOW_AGAIN_MS: L.FOLLOW_AGAIN_MS, GAP_DOTS_S: L.GAP_DOTS_S,
      NEXT_LYRICS_S: L.NEXT_LYRICS_S, LYRICS_KEPT: L.LYRICS_KEPT, LANDED_WITHIN_S: SC.LANDED_WITHIN_S,
    },
    have: answers.map(({ name, lyrics }) => ({ name, lyrics, have: L.lyricsHave(lyrics) })),
    label: HAVES.map((have) => ({ have, label: L.lyricsLabel(have) })),
    dimmed: grid(HAVES, [false, true]).map(([have, on]) => ({ have, on, dimmed: L.lyricsDimmed(have, on) })),
    clock: grid([0, 10, 10.4, 11.5, 11.6, 25, 100], [0, 8.4, 8.5, 8.6, 10, 11.5, 13, 30, 98.5, 99]).map(([raw, reported]) => ({ raw, reported, clock: L.lyricsClock(raw, reported) })),
    clockRuns: [false, true].flatMap((shows) => [false, true].flatMap((playing) => [false, true].flatMap((covered) => [false, true].map((visible) => ({
      shows, playing, covered, visible, runs: L.clockRuns({ shows, playing, covered, visible }),
    }))))),
    sets: Object.entries(SETS).map(([name, lines]) => setVectors(name, lines)),
    sameLit: [
      [{ range: null, dots: 0 }, { range: null, dots: 0 }],
      [{ range: { first: 1, last: 1 }, dots: 0 }, { range: { first: 1, last: 1 }, dots: 0 }],
      [{ range: { first: 1, last: 1 }, dots: 0 }, { range: { first: 1, last: 2 }, dots: 0 }],
      [{ range: { first: 0, last: 0 }, dots: 1 }, { range: { first: 0, last: 0 }, dots: 2 }],
      [{ range: null, dots: 0 }, { range: { first: 0, last: 0 }, dots: 0 }],
      [{ range: { first: 2, last: 3 }, dots: 0 }, { range: { first: 1, last: 3 }, dots: 0 }],
    ].map(([a, b]) => ({ a, b, same: L.sameLit(a, b) })),
    followTop: grid([0, 10, 120, 240.5, 1000], [0, 300, 412, 800.5]).map(([lineTop, height]) => ({ lineTop, height, top: L.followTop(lineTop, height) })),
    endRoom: [-10, 0, 1, 2.5, 5, 15, 25, 412, 500, 600.7, 714.2857142857143, 812].map((height) => ({ height, room: L.endRoom(height) })),
    follows: [
      ...grid([null, 0, 1000, 5000], [0, 3999, 4000, 4001, 5000, 8999, 9000, 100000]).flatMap(([heldAt, now]) =>
        [false, true].flatMap((playing) => [false, true].map((focused) => ({ now, heldAt, playing, focused, follows: L.follows(now, heldAt, playing, focused) })))),
    ],
    followsDefault: [[0, null, true], [4000, 0, true], [3999, 0, true], [4000, 0, false]].map(([now, heldAt, playing]) => ({ now, heldAt, playing, follows: L.follows(now, heldAt, playing) })),
    lineValue: grid([0, 0.4, 9.99, 25.1, 59.999, 60, 83.4, 599.5, 3600, 3725.9, -3], [false, true]).map(([time, lit]) => ({ time, lit, value: L.lineValue(time, lit) })),
    asksAhead: grid([0, 179.9, 180, 180.1, 199, 200, 210], [0, -1, 200, 200.5]).map(([position, duration]) => ({ position, duration, asks: L.asksAhead(position, duration) })),
    kept: keptVectors(),
  }
}

/* ===== writing =================================================================================== */

/** JSON with every character outside ASCII as an escape, so the file holds none raw. */
const say = (value) => JSON.stringify(value, null, 1).replace(/[\u0080-\uffff]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`) + '\n'

const made = say(vectors())
if (CHECK) {
  const committed = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : null
  if (committed !== made) {
    console.error(`  FAIL  ${path.relative(REPO, FIXTURE)} isn't what the web's TypeScript answers today - run node ios/scripts/export-lyrics-vectors.cjs, then port the change to DeadwaxCore's Lyrics.swift and see LyricsTests pass`)
    process.exit(1)
  }
  console.log(`${path.relative(REPO, FIXTURE)} is what the web's TypeScript answers today`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, made)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}`)
}
