/**
 * Info > Debug in the app's now-playing screen (2.0.0-player.10): lib/debugRows.ts, compiled with
 * the repo's TypeScript and asked for its rows.
 *
 * Until 2.0.0-player.10 this was two lines at the top of the now-playing sheet - the gapless
 * readout and the "Last seek" line. James: "the 'in one stream' and the quality shouldn't be
 * displayed in the player, at least not by default, but I would like an 'info' tab in the menu in
 * the player that would show you everything", and "maybe a debug tab to show everything there
 * now". So the rows are built on the same three functions the lines were (describeGaps,
 * describeSeek, describeWrap), and say the same words.
 *
 * What it pins, row by row:
 *  - Format from samplingRate, bitDepth and channelCount, each left out when Navidrome didn't say.
 *  - Sent as, Resampled and Why for a 24/192 FLAC resampled (in an MP4, and in one stream), a
 *    16-bit one resampled (sent at 24-bit all the same), one NOT resampled for each reason
 *    resamples() has, a FLAC wrapped for Safari, one deadwax sent as it is, a transcode, another
 *    song's answer (ignored), and the setting changed mid-song.
 *  - Not answered yet, said as not known: asked for resampled in an MP4 before its headers, and
 *    in one stream before the song's head is in (deadwax makes the whole song first) - never
 *    "No" with the file's own rate. A stream song that isn't to be resampled keeps its rate.
 *  - Gapless, and whether this song is in one stream - an MP4 outside one is just "On".
 *  - Gap: no change timed yet, a stream change, handovers with the earlier ones on their own
 *    line, and a failed change.
 *  - Last seek: none yet, interrupted, and judged at the song's end.
 *  - Speed (2.0.0-player.39): not known, normal, the pitch moving or held or no switch, a rate refused in
 *    the browser's words or read back as another, and the measured pace on the line under it.
 *  - Turntable sound (2.0.0-player.14): ready, or off and why, with the cost. Since 2.0.0-player.16
 *    every way the record can't sound reads Off - starting, its window loading, none yet - since a
 *    press then is 2.0.0-player.11's; and the note names the voice: its own audio thread, or the main
 *    thread and why (the page not on HTTPS, the AudioWorklet refused). Since 2.0.0-player.24 it says how
 *    far the audio's clock moves at a time, once the deck has seen it move - after the voice, before
 *    the cost. Since 2.0.7 (UX batch 4) each of those is a row of its own - Voice, Clock step, Data used - and
 *    Turntable timing's are too: Main-thread sound, Limiter, Frames under a hand, Not restarted, Interruptions,
 *    Delay behind the hand - none a dot-joined note.
 *  - (2.0.7) the labels say what each row is: "Sent to this device", "Why sent this way", "Last song change",
 *    "Fields from Navidrome" with "Song fields", "Only on other songs", "Album fields"; notes in the text face but
 *    the field names' Empty line (`noteMono`).
 *  - "Fields from Navidrome" (was "Navidrome sent"): the names of the song's and the album's fields, sorted; those sent EMPTY
 *    ("", 0, [], {} - Navidrome always writes musicBrainzId and discTitles) named apart; the
 *    fields other songs of the album carry and this one doesn't (playCount and played are left
 *    out of a song never played); and "Not known" when the answer isn't in hand.
 *  - The headroom is src/resample.py's HEADROOM_DB and the setting's names are QualityChoice's.
 *  - (2.0.0-player.63) Debug is an admin's: Info's tabs are About and Debug for an admin and About alone for
 *    anyone else (infoTabs), About shown once the role goes (shownTab). About's group - "Sound" since 2.0.7 - has
 *    its own formatters (lib/aboutSound.ts, pinned by info.sim); Debug keeps its rows and their numbers.
 *  - Normalization (2.0.0-player.62), after Resampled: Off for an entry with no level; not levelled for an
 *    MP3 (its kind upper-cased) or a transcode; deadwax's answer in each state - measured by album or by song,
 *    held by its peak, its album being measured (how far along), not measured yet, not levelled and why - and
 *    an answer about another level ignored. The Resampled row drops "3 dB quieter" for a levelled song, and
 *    keeps it when deadwax says the song played unlevelled.
 *
 * Run it with:  node ui/test/debug.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const REPO = path.resolve(UI, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-debug-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/debugRows.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const rows = require(path.join(OUT, 'debugRows.js'))
const { streamReading } = require(path.join(OUT, 'gapless.js'))
const { seekStep } = require(path.join(OUT, 'scrub.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const DOT = String.fromCharCode(0xb7)

function track(overrides = {}) {
  return {
    id: 's1', title: 'Time', artist: 'Pink Floyd', album: 'The Dark Side of the Moon', albumId: 'a1',
    coverArt: 'c1', duration: 425, contentType: 'audio/flac', suffix: 'flac',
    sampleRate: 44100, bitDepth: 16, channels: 2,
    ...overrides,
  }
}
const HIRES = { sampleRate: 192000, bitDepth: 24 }
const input = (overrides = {}) => ({
  track: track(), gapless: false, maxRate: '48000', gaps: [], lastSeek: null, wrapped: null,
  format: 'raw', song: null, album: null, ...overrides,
})
//? each section's rows as label -> value (and a note, where there is one)
function table(sections) {
  return Object.fromEntries(sections.flatMap((section) => section.rows.map((row) => [row.label, row.note ? [row.value, row.note] : row.value])))
}
const sent = (overrides) => {
  const all = table(rows.debugSections(input(overrides)))
  return [all['Sent as'], all.Resampled, all['Why sent this way'], all.Gapless]
}

console.log('\nthe layout: five sections, their rows in order')
{
  const sections = rows.debugSections(input())
  //? (2.0.7) labels that say what each row is: "Sent to this device", "Fields from Navidrome", "Why sent this way"...
  check('sections', sections.map((section) => section.title), ['The file', 'Sent to this device', 'Last song change and seek', 'The turntable', 'Fields from Navidrome'])
  check('rows', sections.map((section) => section.rows.map((row) => row.label)), [
    //? (2.0.0-player.36: and the turntable's test bench, after the recording; 2.0.0-player.39: the
    //? speed, after Gapless)
    //? (2.0.0-player.62: and Normalization, after Resampled)
    ['Format'], ['Sent as', 'Resampled', 'Normalization', 'Why sent this way', 'Gapless', 'Speed'], ['Last song change', 'Last seek'], ['Turntable sound', 'Turntable timing', 'Recording', 'Test bench'],
    ['Song fields', 'Only on other songs', 'Album fields'],
  ])
}

console.log('\nSpeed (2.0.0-player.39): the speed, whether the pitch moves with it, and anything the browser refused')
{
  const speed = (over = {}) => rows.speedRow({ speed: 1, rate: 1, pitch: 'held', refused: null, measured: null, ...over })
  const words = (row) => (row.note ? [row.value, row.note] : row.value)
  check('nobody said (a page with no player to read): not known; from what Info is handed', [words(rows.speedRow(null)), table(rows.debugSections(input())).Speed], ['Not known', 'Not known'])
  check('1x: the song as it is - the pitch switch the browser\'s own, untouched', words(speed()), 'Normal (1.00x) - the song as it is, nothing changed')
  check('another speed, the pitch let go: moving with it, as a record deck\'s', words(speed({ speed: 1.25, rate: 1.25, pitch: 'moves' })), '1.25x, the pitch moving with it')
  check('...a browser holding it all the same, or with no pitch switch at all: said',
    [words(speed({ speed: 0.5, rate: 0.5, pitch: 'held' })), words(speed({ speed: 0.5, rate: 0.5, pitch: 'no switch' }))],
    ['0.50x, but the browser is holding the pitch', '0.50x - this browser has no pitch switch, so it may be holding the pitch'])
  check('a rate the browser refused: its words', words(speed({ speed: 2, rate: 1, pitch: 'moves', refused: "Failed to set the 'playbackRate' property" })),
    "Asked for 2.00x; the browser refused it - Failed to set the 'playbackRate' property")
  check('a rate that reads back as another', words(speed({ speed: 0.25, rate: 0.5, pitch: 'moves' })), 'Asked for 0.25x; the browser plays it at 0.50x')
  check('the song\'s own pace, measured while it played, on the line under it - so a browser not playing the speed it was given shows',
    [words(speed({ speed: 0.25, rate: 0.25, pitch: 'moves', measured: 1 })), words(speed({ measured: 1.004 }))],
    [['0.25x, the pitch moving with it', 'The song moved at 1.00x over the last few seconds of playing'], ['Normal (1.00x) - the song as it is, nothing changed', 'The song moved at 1.00x over the last few seconds of playing']])
  check('...and in the debug sections, from what Info is handed', table(rows.debugSections(input({ speed: { speed: 1.5, rate: 1.5, pitch: 'moves', refused: null, measured: null } }))).Speed,
    '1.50x, the pitch moving with it')
}

//? (2.0.7) the turntable's facts are a row each - turntableRows - where they were a dot-joined note under two rows
const facts = (report) => Object.fromEntries(rows.turntableRows(report).map((row) => [row.label, row.note ? [row.value, row.note] : row.value]))
const factLabels = (report) => rows.turntableRows(report).map((row) => row.label)

console.log('\nTurntable sound (2.0.0-player.14): ready, or off and why - how an iPhone says what WebKit made of it')
{
  const turntable = (report) => rows.turntableRow(report)
  const ready = {
    context: 'running', problem: null, window: { start: 42, end: 72.4, kind: 'FLAC', decodedAt: 48000, bytes: 3_400_000 },
    loading: false, refused: null, failed: null, fetched: 6_800_000, lastFetchAt: 61_000,
  }
  check('ready: the stretch of the song, its kind, the rate it was decoded at - and what windows have cost a row of its own (2.0.7)',
    [turntable(ready).value, turntable(ready).note, turntable(ready).mono, facts(ready)['Data used']],
    ['Ready: 0:42-1:12, FLAC, decoded at 48 kHz', undefined, undefined, '3.4 MB a window; 6.8 MB fetched since the turntable showed, the last window 1:01 in'])
  check('...and the rows in the debug sections, from what Info is handed',
    [table(rows.debugSections(input({ turntable: ready })))['Turntable sound'], table(rows.debugSections(input({ turntable: ready })))['Data used']],
    ['Ready: 0:42-1:12, FLAC, decoded at 48 kHz', '3.4 MB a window; 6.8 MB fetched since the turntable showed, the last window 1:01 in'])
  check('no turntable showing: that alone - no facts of a turntable that isn\'t there', [turntable(null).value, table(rows.debugSections(input()))['Turntable sound'], factLabels(null)],
    ["Off: the turntable isn't showing", "Off: the turntable isn't showing", ['Turntable sound', 'Turntable timing']])
  check('no Web Audio, and nothing to play it on (neither an AudioWorklet nor a ScriptProcessorNode): said as such',
    [turntable({ ...ready, context: 'unsupported', window: null }).value, turntable({ ...ready, context: 'no-voice', window: null }).value],
    ['Off: this browser has no Web Audio', 'Off: this browser has neither an AudioWorklet nor a ScriptProcessorNode to play it'])
  check('the sound couldn\'t start: the browser\'s own words',
    [turntable({ ...ready, context: 'failed', problem: "the sound couldn't start - NotAllowedError: not allowed", window: null }).value,
      turntable({ ...ready, context: 'failed', problem: "the sound's ScriptProcessorNode couldn't be made - NotSupportedError: no", window: null }).value],
    ["Off: the sound couldn't start - NotAllowedError: not allowed", "Off: the sound's ScriptProcessorNode couldn't be made - NotSupportedError: no"])
  check('not a FLAC, and a window this browser couldn\'t decode - its words - before anything else',
    [turntable({ ...ready, refused: "it isn't a FLAC file (it is MP3)" }).value,
      turntable({ ...ready, refused: "this browser couldn't decode its window - EncodingError: Decoding failed" }).value],
    ["Off: it isn't a FLAC file (it is MP3)", "Off: this browser couldn't decode its window - EncodingError: Decoding failed"])
  check('waiting for a tap: the audio context starts only from one - and a window ready meanwhile is said under it, the cost apart',
    [turntable({ ...ready, context: 'none', window: null, fetched: 0 }), turntable({ ...ready, context: 'none' }).note, facts({ ...ready, context: 'none' })['Data used']],
    [{ label: 'Turntable sound', value: 'Off: waiting for a tap to start the sound' },
      'Its window is ready: 0:42-1:12, FLAC, decoded at 48 kHz', '3.4 MB a window; 6.8 MB fetched since the turntable showed, the last window 1:01 in'])
  //? 2.0.0-player.16: a press is the deck's only when the record can sound there, so every way it can't
  //? says Off - and that a press then scrubs silently, as 2.0.0-player.11's did
  check('starting - the voice not yet playing: off, a press silent until it is',
    [turntable({ ...ready, context: 'starting', window: null, fetched: 0 }).value, turntable({ ...ready, context: 'starting', fetched: 0 }).note],
    ['Off: still starting - a press scrubs silently until it has', 'Its window is ready: 0:42-1:12, FLAC, decoded at 48 kHz'])
  check('deadwax didn\'t send a window, its window loading, and none asked for yet: each off, a press silent',
    [turntable({ ...ready, window: null, failed: "deadwax didn't send it - its MP4 couldn't be made just now", fetched: 0 }).value,
      turntable({ ...ready, window: null, loading: true, fetched: 0 }).value, turntable({ ...ready, window: null, fetched: 0 }).value],
    ["Off: deadwax didn't send it - its MP4 couldn't be made just now", 'Off: its window is loading - a press scrubs silently until it is in',
      'Off: no window yet - a press scrubs silently; one is fetched while the song plays, or as the record is pressed'])
  check('...the cost said only once something was fetched',
    [turntable({ ...ready, window: null, loading: true, fetched: 0 }).note, facts({ ...ready, window: null, loading: true, fetched: 0 })['Data used']], [undefined, undefined])
  check('...and measured to the moment the last window came - the report is made as things change, not as time passes - never a running clock it hasn\'t got',
    facts({ ...ready, fetched: 2_500_000, lastFetchAt: 1_200 })['Data used'], '3.4 MB a window; 2.5 MB fetched since the turntable showed, the last window 0:01 in')
}

console.log('\nTurntable sound (2.0.0-player.16): which voice plays it, and why - its own row since 2.0.7')
{
  const ready = {
    context: 'running', problem: null, voice: 'script', voiceWhy: "this page isn't on HTTPS, so the browser has no AudioWorklet",
    window: { start: 31, end: 72.6, kind: 'FLAC', decodedAt: 44100, bytes: 3_400_000 },
    loading: false, refused: null, failed: null, fetched: 0, lastFetchAt: 0,
  }
  check('on the main thread, the page not on HTTPS: ready - and Voice says where it plays and why',
    [rows.turntableRow(ready).value, rows.turntableRow(ready).note, facts(ready).Voice],
    ['Ready: 0:31-1:12, FLAC, decoded at 44.1 kHz', undefined, "On the main thread - this page isn't on HTTPS, so the browser has no AudioWorklet"])
  check('...the AudioWorklet refused: its words',
    facts({ ...ready, voiceWhy: "the AudioWorklet wouldn't load (SyntaxError: Unexpected token)" }).Voice, "On the main thread - the AudioWorklet wouldn't load (SyntaxError: Unexpected token)")
  check('the worklet: its own audio thread', facts({ ...ready, voice: 'worklet', voiceWhy: null }).Voice, 'On its own audio thread (an AudioWorklet)')
  check('...the voice before the cost, each a row - an off sound too',
    [factLabels({ ...ready, fetched: 6_800_000, lastFetchAt: 61_000 }), factLabels({ ...ready, window: null, loading: true })],
    [['Turntable sound', 'Voice', 'Data used', 'Turntable timing'], ['Turntable sound', 'Voice', 'Turntable timing']])
  check('...and no Voice row while there is none', facts({ ...ready, voice: null, voiceWhy: null, window: null }).Voice, undefined)
}

console.log('\nTurntable sound (2.0.0-player.24): how far the audio\'s clock moves at a time - its own row since 2.0.7')
{
  const ready = {
    context: 'running', problem: null, voice: 'worklet', voiceWhy: null,
    window: { start: 31, end: 72.6, kind: 'FLAC', decodedAt: 44100, bytes: 3_400_000 },
    loading: false, refused: null, failed: null, fetched: 6_800_000, lastFetchAt: 61_000, clockStep: 1024 / 48000,
  }
  check('...and Turntable sound itself says only what it says: no note of the voice, the clock or the cost',
    rows.turntableRow(ready), { label: 'Turntable sound', value: 'Ready: 0:31-1:12, FLAC, decoded at 44.1 kHz' })
  check('an iPhone\'s 1024 frames a render: after the voice, before the cost, in the text face (2.0.9: a phrase)',
    [facts(ready)['Clock step'], factLabels(ready), rows.turntableRows(ready).find((row) => row.label === 'Clock step').mono],
    ['21.3 ms at a time', ['Turntable sound', 'Voice', 'Clock step', 'Data used', 'Turntable timing'], undefined])
  check('...desktop Brave\'s 256 at 44.1 kHz; nothing said before it has been seen to move (0), nor by a report without it',
    [facts({ ...ready, clockStep: 256 / 44100, fetched: 0 })['Clock step'], facts({ ...ready, clockStep: 0, fetched: 0 })['Clock step'],
      facts({ ...ready, clockStep: undefined, fetched: 0 })['Clock step']],
    ['5.8 ms at a time', undefined, undefined])
}

console.log('\nRecording (2.0.0-player.32): the record\'s sound, every touch and what the voice made of it, as a file to send')
{
  const base = { context: 'running', problem: null, voice: 'script', voiceWhy: null, window: null, loading: false, refused: null, failed: null, fetched: 0, lastFetchAt: 0 }
  const run = () => {}
  check('no turntable showing: says what the recording is of, and offers no button', rows.recordingRow(null, run, null), { label: 'Recording', value: 'Shows the turntable first: the recording is of its sound' })
  check('the turntable showing: the button that starts one', rows.recordingRow(null, run, base).action, { label: 'Record 20 s', onClick: run })
  check('...and no button when nothing would start one', rows.recordingRow(null, null, base).action, undefined)
  check('under way: how long, and what to do', rows.recordingRow({ state: 'recording', seconds: 20 }, run, base), { label: 'Recording', value: "Recording the record's sound for 20 s - turn the record as you would" })
  check('made: the file to save, by its name and size, as a link that downloads it', rows.recordingRow({ state: 'saved', seconds: 20, href: 'blob:x', name: 'deadwax-turntable-script-2026.json', bytes: 5.2 * 1048576 }, run, base),
    { label: 'Recording', value: '20 s recorded: save the file and send it', note: 'deadwax-turntable-script-2026.json', action: { label: 'Save the recording (5.2 MB)', href: 'blob:x', download: 'deadwax-turntable-script-2026.json' } })
}

console.log('\nTest bench (2.0.0-player.36): the turntable over test tones, a link that opens beside the app')
{
  const row = rows.benchRow()
  check('a link to /player/lab/, opening beside the app - never a download', [row.label, row.action, rows.BENCH_ADDRESS],
    ['Test bench', { label: 'Open the test bench', href: '/player/lab/', beside: true }, '/player/lab/'])
  check('...in the turntable\'s section whatever the turntable is doing, shown or not',
    [rows.debugSections(input()).find((section) => section.title === 'The turntable').rows.at(-1), rows.debugSections(input({ turntable: { context: 'none', problem: null, voice: null, voiceWhy: null, window: null, loading: false, refused: null, failed: null, fetched: 0, lastFetchAt: 0 } })).find((section) => section.title === 'The turntable').rows.at(-1)],
    [row, row])
}

console.log('\nTurntable timing (2.0.0-player.28): how the turntable keeps up on this device, for a phone to say - a fact a row since 2.0.7')
{
  const base = { context: 'running', problem: null, voice: 'script', voiceWhy: "this page isn't on HTTPS, so the browser has no AudioWorklet", window: null, loading: false, refused: null, failed: null, fetched: 0, lastFetchAt: 0 }
  const health = { blocks: 3400, lateBlocks: 12, worstBlockMs: 37.6, frames: 310, slowFrames: 4, worstFrameMs: 118.2, backMs: 1240, motorMs: 400, notBack: 0, interruptions: 0 }
  //? the timing row's facts, in order, after the row itself
  const timing = (report) => {
    const all = rows.turntableRows(report)
    return all.slice(all.findIndex((row) => row.label === 'Turntable timing') + 1).map((row) => [row.label, row.value])
  }
  check('nothing to say without a report, or from a deck that sent none - and no facts', [rows.turntableTimingRow(null).value, rows.turntableTimingRow(base).value, timing(base)], ['Not known', 'Not known', []])
  check('the last let-go, and what the page was like under the hand - the main thread\'s sound, the frames, a row each',
    [rows.turntableTimingRow({ ...base, health }), timing({ ...base, health })],
    [{ label: 'Turntable timing', value: "The song was back 1.24 s after the last let-go - 0.40 s of it the record's run back to speed" },
      [['Main-thread sound', '12 of 3400 blocks late, the worst by 38 ms'], ['Frames under a hand', '310 frames, 4 late, the longest gap 118 ms']]])
  check('nothing late, nothing timed yet, on the audio thread: said plainly, and no word of blocks (the worklet has none on the main thread)',
    [rows.turntableTimingRow({ ...base, voice: 'worklet', voiceWhy: null, health: { ...health, lateBlocks: 0, slowFrames: 0, backMs: null, motorMs: null } }),
      timing({ ...base, voice: 'worklet', voiceWhy: null, health: { ...health, lateBlocks: 0, slowFrames: 0, backMs: null, motorMs: null } })],
    [{ label: 'Turntable timing', value: 'No let-go of a playing record timed yet' }, [['Frames under a hand', '310 frames, 0 late']]])
  check('a let-go played in its own gesture has no run back to speed to name; a song that never started and an interruption are counted',
    [rows.turntableTimingRow({ ...base, health: { ...health, blocks: 0, frames: 0, backMs: 180, motorMs: 0, notBack: 2, interruptions: 1 } }),
      timing({ ...base, health: { ...health, blocks: 0, frames: 0, backMs: 180, motorMs: 0, notBack: 2, interruptions: 1 } }),
      timing({ ...base, health: { ...health, notBack: 1, interruptions: 3 } }).slice(-2)],
    [{ label: 'Turntable timing', value: 'The song was back 0.18 s after the last let-go' },
      [['Main-thread sound', 'No block played yet'], ['Frames under a hand', 'No frames yet'], ['Not restarted', "2 let-goes after which the song didn't start"], ['Interruptions', 'The sound was interrupted once']],
      [['Not restarted', "1 let-go after which the song didn't start"], ['Interruptions', 'The sound was interrupted 3 times']]])
  //? 2.0.0-player.35: what the voice's limiter held under full scale - runs of samples over its ceiling, half
  //? a decibel under (Club Diver peak-normalised along James's hand: 36 of them, 65 samples, 1.35 dB)
  const held = { ...health, peaksHeld: 36, samplesHeld: 65, deepestHoldDb: 1.354 }
  check('the peaks the voice\'s limiter held under full scale, after the main thread\'s blocks: how many, how many samples, the deepest it turned the sound down',
    timing({ ...base, health: held }),
    [['Main-thread sound', '12 of 3400 blocks late, the worst by 38 ms'], ['Limiter', '36 peaks held under full scale since it showed (65 samples), the deepest 1.4 dB'],
      ['Frames under a hand', '310 frames, 4 late, the longest gap 118 ms']])
  check('...one peak of one sample, on the audio thread; and none at all, said plainly',
    [timing({ ...base, voice: 'worklet', voiceWhy: null, health: { ...held, peaksHeld: 1, samplesHeld: 1, deepestHoldDb: 0.04 } })[0],
      timing({ ...base, voice: 'worklet', voiceWhy: null, health: { ...held, peaksHeld: 0, samplesHeld: 0, deepestHoldDb: 0 } })[0]],
    [['Limiter', '1 peak held under full scale since it showed (1 sample), the deepest under 0.1 dB'], ['Limiter', 'No peaks held under full scale since it showed']])
  check('...and no word of it with no voice yet (nothing has played)', timing({ ...base, voice: null, health: held }), [['Frames under a hand', '310 frames, 4 late, the longest gap 118 ms']])
  //? 2.0.0-player.40: the record's sound behind the hand by design, and what this device's audio says it adds
  //? after that - each only where the browser gives it
  const mac = { base: 128 / 48000, output: 0.008, speaker: 0.0117, block: 512, design: 0.12 + 1024 / 48000 + 0.0015 }
  check('2.0.0-player.40: behind the hand by design - blocks of 512 on the main thread - and what a Mac\'s Chrome says its audio adds: base, output, and the render clock\'s lead on the speaker - a row of its own, last',
    timing({ ...base, health, latency: mac }).at(-1),
    ['Delay behind the hand', "142.8 ms behind the hand by design (blocks of 512 on the main thread), then what this device's audio adds - it says base 2.7 ms, output 8.0 ms, 11.7 ms from render to speaker"])
  check('...an iPhone before Safari 18.4: blocks of 1024, its base latency alone; the worklet on its own thread; a browser that says nothing; and nothing said with no voice or no figures',
    [rows.latencyNote({ ...base, health, latency: { base: 1024 / 48000, output: null, speaker: null, block: 1024, design: 0.12 + 2048 / 48000 + 0.0015 } }),
      rows.latencyNote({ ...base, voice: 'worklet', voiceWhy: null, health, latency: { base: 0.0107, output: 0.04, speaker: 0.0456, block: 128, design: 0.1215 } }),
      rows.latencyNote({ ...base, health, latency: { base: null, output: null, speaker: null, block: 1024, design: 0.12 + 2048 / 48000 + 0.0015 } }),
      rows.latencyNote({ ...base, voice: null, health, latency: mac }), rows.latencyNote({ ...base, health, latency: null }), rows.latencyNote({ ...base, health })],
    ["The record's sound: 164.2 ms behind the hand by design (blocks of 1024 on the main thread), then what this device's audio adds - it says base 21.3 ms",
      "The record's sound: 121.5 ms behind the hand by design (on its own thread), then what this device's audio adds - it says base 10.7 ms, output 40.0 ms, 45.6 ms from render to speaker",
      "The record's sound: 164.2 ms behind the hand by design (blocks of 1024 on the main thread), then what this device's audio adds - it doesn't say", null, null, null])
  //? (2.0.7) one fact a row: no row's value or note is a dot-joined list any more
  const everything = rows.turntableRows({ ...base, voice: 'script', clockStep: 0.0213, fetched: 6_800_000, lastFetchAt: 61_000, window: { start: 31, end: 72.6, kind: 'FLAC', decodedAt: 44100, bytes: 3_400_000 }, health: { ...held, notBack: 1, interruptions: 1 }, latency: mac })
  check('...every fact a row of its own: none joins two with a dot',
    [everything.map((row) => row.label), everything.filter((row) => [row.value, row.note ?? ''].some((words) => words.includes(` ${DOT} `))).map((row) => row.label)],
    [['Turntable sound', 'Voice', 'Clock step', 'Data used', 'Turntable timing', 'Main-thread sound', 'Limiter', 'Frames under a hand', 'Not restarted', 'Interruptions', 'Delay behind the hand'], []])
}

console.log('\nFormat: what Navidrome said of the file')
check('a 24/192 FLAC', rows.formatRow(track({ ...HIRES })).value, 'FLAC, 24-bit, 192 kHz, stereo')
check('a CD-quality one', rows.formatRow(track()).value, 'FLAC, 16-bit, 44.1 kHz, stereo')
check('mono, and more than two channels', [rows.formatRow(track({ channels: 1 })).value, rows.formatRow(track({ channels: 6 })).value],
  ['FLAC, 16-bit, 44.1 kHz, mono', 'FLAC, 16-bit, 44.1 kHz, 6 channels'])
check('an MP3 says no depth', rows.formatRow(track({ suffix: 'mp3', contentType: 'audio/mpeg', bitDepth: 0 })).value, 'MP3, 44.1 kHz, stereo')
check('missing fields are left out, not guessed', rows.formatRow(track({ sampleRate: 0, bitDepth: 0 })).value, 'FLAC, stereo')
check('nothing said at all', rows.formatRow(track({ suffix: null, contentType: null, sampleRate: 0, bitDepth: 0, channels: 0 })).value, "Navidrome didn't say")
check('the kind from the type when there is no extension', rows.formatRow(track({ suffix: null, contentType: 'audio/x-flac' })).value, 'FLAC, 16-bit, 44.1 kHz, stereo')
//? (2.0.9) words in the text face: the data face is for numbers, times, ids and paths, never a phrase
check('set in the text face (2.0.9: a phrase, not data)', rows.formatRow(track()).mono, undefined)

console.log('\na FLAC 24/192, resampled')
check('in an MP4 (Safari): sent at 24-bit 48 kHz, 3 dB quieter, because of the setting',
  sent({ track: track(HIRES), wrapped: { id: 's1', got: 'mp4', resampled: { from: 192000, to: 48000 }, hiRes: null } }),
  ['FLAC in MP4, 24-bit, 48 kHz', '192 kHz to 48 kHz, 3 dB quieter', 'Maximum quality: Up to 48 kHz', 'Off'])
check('in one stream, with Gapless on',
  sent({ track: track(HIRES), gapless: true, wrapped: { id: 's1', got: 'stream', resampled: { from: 192000, to: 48000 }, hiRes: null } }),
  ['In one stream, 24-bit, 48 kHz', '192 kHz to 48 kHz, 3 dB quieter', 'Maximum quality: Up to 48 kHz', 'On, in one stream'])
check('a 16-bit hi-res FLAC resampled is sent at 24-bit, as every resampled song is',
  sent({ track: track({ sampleRate: 96000, bitDepth: 16 }), wrapped: { id: 's1', got: 'mp4', resampled: { from: 96000, to: 48000 }, hiRes: null } }).slice(0, 2),
  ['FLAC in MP4, 24-bit, 48 kHz', '96 kHz to 48 kHz, 3 dB quieter'])
check('the 88.2 family goes to 44.1',
  sent({ track: track({ sampleRate: 88200, bitDepth: 24 }), wrapped: { id: 's1', got: 'mp4', resampled: { from: 88200, to: 44100 }, hiRes: null } }).slice(0, 2),
  ['FLAC in MP4, 24-bit, 44.1 kHz', '88.2 kHz to 44.1 kHz, 3 dB quieter'])
check('resampled, then the setting moved to Original: says what it was when asked for',
  sent({ track: track(HIRES), maxRate: 'original', wrapped: { id: 's1', got: 'mp4', resampled: { from: 192000, to: 48000 }, hiRes: null } })[2],
  'Maximum quality was Up to 48 kHz when this song was asked for')

console.log('\nnot resampled, and why')
check('a CD-quality FLAC in Chromium: the file as it is', sent({}), ['FLAC, as the file is', 'No', '48 kHz and below is never resampled', 'Off'])
check('24/192 under Original, in one stream: the rate kept',
  sent({ track: track(HIRES), maxRate: 'original', gapless: true, wrapped: { id: 's1', got: 'stream', resampled: null, hiRes: 192000 } }),
  ['In one stream, 24-bit, 192 kHz', 'No', 'Maximum quality: Original', 'On, in one stream'])
check('a CD-quality FLAC under Original: the rate, not the setting', sent({ maxRate: 'original' })[2], '48 kHz and below is never resampled')
check('an MP3 at 44.1: the rate is the first reason', sent({ track: track({ suffix: 'mp3', contentType: 'audio/mpeg', bitDepth: 0 }) })[2], '48 kHz and below is never resampled')
check('an ALAC at 192: only FLAC is', sent({ track: track({ ...HIRES, suffix: 'm4a', contentType: 'audio/mp4' }) }).slice(1, 3), ['No', 'Only FLAC is resampled'])
check('a rate deadwax has no ratio for', sent({ track: track({ sampleRate: 128000, bitDepth: 24 }) })[2], "deadwax doesn't resample 128 kHz")
check('32 bits', sent({ track: track({ sampleRate: 192000, bitDepth: 32 }) })[2], 'deadwax resamples only 16-bit and 24-bit songs')
check('no rate from Navidrome', sent({ track: track({ sampleRate: 0 }) })[2], "Navidrome didn't give its sample rate, so it is sent as it is")
check('asked for resampled, no answer yet', sent({ track: track(HIRES), wrapped: { id: 's1', got: null, resampled: null, hiRes: null } }).slice(0, 3),
  ['Asked for FLAC in MP4', 'Not known yet', "Asked for resampled; deadwax hasn't answered yet"])
check('asked for, not resampled and no answer yet: "No" - it was never asked for resampled',
  sent({ wrapped: { id: 's1', got: null, resampled: null, hiRes: null } }).slice(0, 3),
  ['Asked for FLAC in MP4', 'No', '48 kHz and below is never resampled'])
check('the setting moved to 48 kHz after this song started, or deadwax declined',
  sent({ track: track(HIRES), wrapped: { id: 's1', got: 'mp4', resampled: null, hiRes: null } })[2],
  'Maximum quality changed after this song started, or deadwax sent it as it is (its log says why)')
check('the setting not known to apply because nothing could say how it was asked for', sent({ track: track(HIRES), format: null }).slice(0, 3), ['Not known', 'No', 'Not known'])

console.log('\nin one stream, before the song\'s head is in')
check('a 24/192 FLAC under 48 kHz while deadwax makes it: not known yet, not "No" at 192 kHz',
  sent({ track: track(HIRES), gapless: true, wrapped: { id: 's1', got: 'stream', resampled: null, hiRes: null } }),
  ['In one stream', 'Not known yet', "Asked for resampled; deadwax hasn't answered yet", 'On, in one stream'])
check('...and once its head is in, what deadwax did',
  sent({ track: track(HIRES), gapless: true, wrapped: { id: 's1', got: 'stream', resampled: { from: 192000, to: 48000 }, hiRes: null } }).slice(0, 3),
  ['In one stream, 24-bit, 48 kHz', '192 kHz to 48 kHz, 3 dB quieter', 'Maximum quality: Up to 48 kHz'])
check('under Original, before its head: sent as it is, so its own rate',
  sent({ track: track(HIRES), maxRate: 'original', gapless: true, wrapped: { id: 's1', got: 'stream', resampled: null, hiRes: null } }).slice(0, 3),
  ['In one stream, 24-bit, 192 kHz', 'No', 'Maximum quality: Original'])
check('a CD-quality song before its head: its own rate, never resampled',
  sent({ gapless: true, wrapped: { id: 's1', got: 'stream', resampled: null, hiRes: null } }).slice(0, 3),
  ['In one stream, 16-bit, 44.1 kHz', 'No', '48 kHz and below is never resampled'])
check('the setting moved to 48 kHz after an Original stream\'s head was in: the rate it kept',
  sent({ track: track(HIRES), gapless: true, wrapped: { id: 's1', got: 'stream', resampled: null, hiRes: 192000 } }).slice(0, 3),
  ['In one stream, 24-bit, 192 kHz', 'No', 'Maximum quality changed after this song started, or deadwax sent it as it is (its log says why)'])

console.log('\nwrapped for Safari, and not')
check('a CD-quality FLAC in an MP4: its own depth and rate', sent({ wrapped: { id: 's1', got: 'mp4', resampled: null, hiRes: null } }).slice(0, 2), ['FLAC in MP4, 16-bit, 44.1 kHz', 'No'])
check('deadwax sent it as it is (describeWrap\'s words, less "sent as")', sent({ wrapped: { id: 's1', got: 'flac', resampled: null, hiRes: null } })[0], 'FLAC, not in an MP4, 16-bit, 44.1 kHz')
check('another song\'s answer is not this one\'s', sent({ wrapped: { id: 'other', got: 'mp4', resampled: { from: 192000, to: 48000 }, hiRes: null } }).slice(0, 2), ['FLAC, as the file is', 'No'])
check('a stream with Gapless off says Off', sent({ wrapped: { id: 's1', got: 'stream', resampled: null, hiRes: null } })[3], 'Off')
check('Gapless on, not in a stream', sent({ gapless: true })[3], 'On')
check('Gapless on, an MP4 outside a stream (a stream that gave up): "On", not "in one stream"',
  sent({ gapless: true, wrapped: { id: 's1', got: 'mp4', resampled: null, hiRes: null } })[3], 'On')

console.log('\na transcode')
check('an Opus file a browser can\'t play',
  sent({ track: track({ suffix: 'opus', contentType: 'audio/ogg', sampleRate: 48000, bitDepth: 0 }), format: 'mp3' }).slice(0, 3),
  ['MP3, transcoded by Navidrome', 'No', "This browser can't play OPUS, so Navidrome transcodes it to MP3"])
check('an MP3 sent as it is', sent({ track: track({ suffix: 'mp3', contentType: 'audio/mpeg', bitDepth: 0 }) })[0], 'MP3, as the file is')
check('nothing known of the file at all', sent({ track: track({ suffix: null, contentType: null }), format: 'raw' })[0], 'The file as it is')

console.log('\nGap: the song changes, newest first')
const handover = (ms, source = 'memory', extra = {}) => ({ ms, how: { kind: 'handover', source }, readyState: 4, failed: false, ...extra })
const oneElement = (ms, extra = {}) => ({ ms, how: { kind: 'same element', reason: 'off' }, readyState: null, failed: false, ...extra })
check('no gaps yet', rows.gapRow([]), { label: 'Last song change', value: 'No song change timed yet' })
check('a stream change', rows.gapRow([streamReading(0)]), { label: 'Last song change', value: '0 ms, in one stream' })
check('handovers, the earlier ones on their own line', rows.gapRow([handover(96), oneElement(581), oneElement(511), handover(2867, 'unfinished'), oneElement(218)]),
  { label: 'Last song change', value: '96 ms, handed over, from memory', note: 'Earlier: 581, 511, 2867, 218 ms' })
check('a failed change', rows.gapRow([oneElement(1650, { failed: true })]), { label: 'Last song change', value: '1650 ms, one element, failed before playing' })
check('a handover that had to load', rows.gapRow([handover(143, 'stream', { readyState: 2 })]).value, '143 ms, handed over, streamed, had to load')

console.log('\nLast seek')
check('none yet', rows.seekRow(null), { label: 'Last seek', value: 'No seek yet' })
{
  let reading = seekStep(null, { kind: 'asked', asked: 90, length: 300, track: 's1' })
  check('on its way', rows.seekRow(reading).value, 'Asked 1:30, seeking…')
  check('interrupted', rows.seekRow(seekStep(reading, { kind: 'song change' })).value, 'Asked 1:30, interrupted')
  reading = seekStep(reading, { kind: 'seeked', position: 90 })
  reading = seekStep(reading, { kind: 'ended', position: 300, at: 1000, rate: 1 })
  check('judged at the song\'s end', rows.seekRow(reading).value, `Asked 1:30, the player said 1:30 ${DOT} the song ended on time, so it landed there`)
}

console.log('\n"Fields from Navidrome": the names of the fields, as they came')
{
  const song = { id: 's1', title: 'Time', musicBrainzId: 'mb', played: '2026-09-30', playCount: 12, discNumber: 1, bitDepth: 24 }
  const album = { id: 'a1', name: 'The Dark Side of the Moon', discTitles: [{ disc: 1, title: 'Side one' }], song: [song], year: 1973 }
  const all = table(rows.debugSections(input({ song, album })))
  check('the song\'s, sorted as plain strings', all['Song fields'], 'bitDepth, discNumber, id, musicBrainzId, playCount, played, title')
  check('the album\'s, its song list and disc titles included', all['Album fields'], 'discTitles, id, name, song, year')
  check('only the names - no value leaks into the row', /2026|Time|Moon|12|Side/.test(JSON.stringify([all['Song fields'], all['Album fields']])), false)
  check('the names in the data face', rows.debugSections(input({ song, album }))[4].rows.map((row) => [row.label, row.mono ?? false]), [['Song fields', true], ['Only on other songs', false], ['Album fields', true]])
  check('one song on the album: nothing on others it lacks', all['Only on other songs'], 'Nothing this song lacks')
  const none = table(rows.debugSections(input()))
  check('not in hand: said so, nothing invented', [none['Song fields'], none['Only on other songs'], none['Album fields']], ['Not known', 'Not known', 'Not known'])
  check('an answer with no fields', rows.fieldNames({}), [])
}
{
  //? what Navidrome 0.64.2 writes for an older rip, a song never played: musicBrainzId and
  //? discTitles always (empty), bpm and bitDepth as 0, replayGain as {}; playCount and played
  //? left out - here, not on the song beside it, which has been played
  const mine = { id: 's1', title: 'Time', isDir: false, musicBrainzId: '', bpm: 0, bitDepth: 0, replayGain: {}, genres: [], track: 4 }
  const played = { id: 's2', title: 'Money', isDir: false, musicBrainzId: '', bpm: 0, bitDepth: 0, replayGain: {}, genres: [], track: 6, playCount: 3, played: '2026-09-29', starred: '2026-09-01' }
  const album = { id: 'a1', name: 'The Dark Side of the Moon', musicBrainzId: '', discTitles: [], userRating: 0, isCompilation: false, releaseDate: {}, song: [mine, played] }
  const sections = rows.debugSections(input({ song: mine, album }))
  const all = table(sections)
  check('a field sent empty is named apart, not listed as if it held something',
    all['Song fields'], ['id, isDir, title, track', 'Empty: bitDepth, bpm, genres, musicBrainzId, replayGain'])
  check('...on the album too: musicBrainzId "" and discTitles [] are sent, empty; false is a value',
    all['Album fields'], ['id, isCompilation, name, song', 'Empty: discTitles, musicBrainzId, releaseDate, userRating'])
  //? (2.0.7) notes are in the text face - but these are field names, so this one is data
  check('...its Empty line names fields, so it alone of the notes is in the data face', [sections[4].rows[0].noteMono, sections[4].rows[2].noteMono, rows.gapRow([streamReading(0), streamReading(0)]).noteMono], [true, true, undefined])
  check('the fields another song carries and this one doesn\'t: a song never played has no playCount',
    all['Only on other songs'], 'playCount, played, starred')
  check('...names only, in the data face', [/2026|Money|3/.test(all['Only on other songs']), sections[4].rows[1].mono], [false, true])
  check('a field empty here and filled on another song counts as one this song lacks',
    rows.otherSongsFields({ id: 'x', musicBrainzId: '' }, { song: [{ id: 'x', musicBrainzId: '' }, { id: 'y', musicBrainzId: 'abc' }] }), ['musicBrainzId'])
  check('the song itself, found again by id in the album\'s list, is not "another song"',
    rows.otherSongsFields({ id: 'x', a: 1 }, { song: [{ id: 'x', a: 1, b: 2 }] }), [])
  check('what counts as empty', [rows.isEmptyValue(''), rows.isEmptyValue(0), rows.isEmptyValue([]), rows.isEmptyValue({}), rows.isEmptyValue(null),
    rows.isEmptyValue(false), rows.isEmptyValue('x'), rows.isEmptyValue([0]), rows.isEmptyValue({ a: 0 })], [true, true, true, true, true, false, false, false, false])
  check('an answer of empty fields only', table([{ title: 't', rows: [rows.debugSections(input({ song: { a: '' }, album: null }))[4].rows[0]] }])['Song fields'],
    ['Nothing with a value', 'Empty: a'])
}

console.log('\nNormalization (2.0.0-player.62)')
{
  const answer = (overrides = {}) => ({
    level: 'album', state: 'measured', gain_db: -7.42, wanted_db: -7.42, loudness_lufs: -10.58, peak_db: -0.3, held: false,
    songs: 12, measured_songs: 12, why: null, ...overrides,
  })
  const row = (entry, level = null, format = 'raw') => rows.normalizationRow({ track: track(entry), format, level }).value
  check('no level on the entry: Off', row({}), 'Off')
  check('an MP3 asked with a level: not levelled, its kind upper-cased',
    row({ suffix: 'mp3', contentType: 'audio/mpeg', level: 'album' }), 'Not levelled - MP3 songs play as they are')
  check('...an Opus too, and a FLAC sent as a transcode',
    [row({ suffix: 'opus', contentType: 'audio/ogg', level: 'track' }), row({ level: 'album' }, null, 'mp3')],
    ['Not levelled - OPUS songs play as they are', 'Not levelled - FLAC songs play as they are'])
  check('a level asked, deadwax not answered yet', row({ level: 'album' }), "Asked for; deadwax hasn't said yet")
  check('measured by album: the gain, and the album\'s loudness', row({ level: 'album' }, answer()), `Album, -7.42 dB ${DOT} the album at -10.6 LUFS`)
  check('...by song', row({ level: 'track' }, answer({ level: 'track', gain_db: -3.1, loudness_lufs: -14.92 })), `Song, -3.10 dB ${DOT} the song at -14.9 LUFS`)
  check('...held by its peak, saying what it wanted', row({ level: 'track' }, answer({ level: 'track', gain_db: 1.2, wanted_db: 2.35, held: true })),
    `Song, +1.20 dB ${DOT} held there by its peak (it wanted +2.35)`)
  check('...silence', row({ level: 'track' }, answer({ level: 'track', gain_db: 0, wanted_db: 0, loudness_lufs: null })), `Song, +0.00 dB ${DOT} the song is silent`)
  check('its album being measured, how far along', row({ level: 'album' }, answer({ state: 'measuring', gain_db: null, measured_songs: 7 })),
    'Measuring its album… (7 of 12 songs)')
  check('...a song alone', row({ level: 'track' }, answer({ level: 'track', state: 'measuring', gain_db: null })), 'Measuring the song…')
  check('not measured yet: it played as it is this time', row({ level: 'album' }, answer({ state: 'unmeasured', gain_db: null })),
    'Not measured yet - it played as it is this time')
  check('answered as it is this time (its level not to be had in time): said so, whatever was measured since',
    [row({ level: 'album' }, answer({ state: 'plain', gain_db: null })), row({ level: 'track' }, answer({ level: 'track', state: 'plain', gain_db: null }))],
    ['Played as it is this time - its album was still being measured', 'Played as it is this time - its loudness was still being measured'])
  check('...and Resampled keeps its 3 dB, Sent as its own depth, for that song',
    [rows.resampledRow({ track: track({ ...HIRES, level: 'album' }), wrapped: { id: 's1', got: 'mp4', resampled: { from: 192000, to: 48000 }, hiRes: null }, maxRate: '48000', format: 'raw', level: answer({ state: 'plain', gain_db: null }) }).value,
      rows.sentAsRow({ track: track({ level: 'album' }), wrapped: { id: 's1', got: 'mp4', resampled: null, hiRes: null }, maxRate: '48000', format: 'raw', level: answer({ state: 'plain', gain_db: null }) }).value],
    ['192 kHz to 48 kHz, 3 dB quieter', 'FLAC in MP4, 16-bit, 44.1 kHz'])
  check('deadwax won\'t level it, and why', row({ level: 'album' }, answer({ state: 'not_levelled', gain_db: null, why: "its file can't be read as FLAC by deadwax (20- or 32-bit)" })),
    "Not levelled - its file can't be read as FLAC by deadwax (20- or 32-bit)")
  check('an answer about the other level is not this song\'s', row({ level: 'track' }, answer()), "Asked for; deadwax hasn't said yet")
  check('the gain in the text face, measured or not (2.0.9: a phrase)', [rows.normalizationRow({ track: track({ level: 'album' }), format: 'raw', level: answer() }).mono,
    rows.normalizationRow({ track: track(), format: 'raw', level: null }).mono], [undefined, undefined])
  const resampled = { id: 's1', got: 'mp4', resampled: { from: 192000, to: 48000 }, hiRes: null }
  const resampledRow = (entry, level) => rows.resampledRow({ track: track({ ...HIRES, ...entry }), wrapped: resampled, maxRate: '48000', format: 'raw', level }).value
  check('Resampled: a levelled song gets its level\'s gain instead of the 3 dB - and keeps the 3 dB when it played unlevelled',
    [resampledRow({}, null), resampledRow({ level: 'album' }, null), resampledRow({ level: 'album' }, answer()),
      resampledRow({ level: 'album' }, answer({ state: 'unmeasured', gain_db: null })), resampledRow({ level: 'album' }, answer({ state: 'not_levelled', gain_db: null }))],
    ['192 kHz to 48 kHz, 3 dB quieter', '192 kHz to 48 kHz', '192 kHz to 48 kHz', '192 kHz to 48 kHz, 3 dB quieter', '192 kHz to 48 kHz, 3 dB quieter'])
  const sentAs = (level, got = 'mp4') => rows.sentAsRow({ track: track({ level: 'album' }), wrapped: { id: 's1', got, resampled: null, hiRes: null }, maxRate: '48000', format: 'raw', level }).value
  check('Sent as: a levelled CD song comes 24-bit, in deadwax\'s copy - its own depth when it played unlevelled, or came as the FLAC',
    [sentAs(answer()), sentAs(answer(), 'stream'), sentAs(answer({ state: 'unmeasured', gain_db: null })), sentAs(answer(), 'flac'),
      rows.sentAsRow({ track: track(), wrapped: { id: 's1', got: 'mp4', resampled: null, hiRes: null }, maxRate: '48000', format: 'raw', level: null }).value],
    ['FLAC in MP4, 24-bit, 44.1 kHz', 'In one stream, 24-bit, 44.1 kHz', 'FLAC in MP4, 16-bit, 44.1 kHz', 'FLAC, not in an MP4, 16-bit, 44.1 kHz', 'FLAC in MP4, 16-bit, 44.1 kHz'])
}

console.log('\nDebug is an admin\'s (2.0.0-player.63); About\'s Sound group its own words (2.0.7)')
{
  //? James: "only make the debug info available to an admin"
  check('Info\'s tabs: About and Debug for an admin, About alone for everyone else',
    [rows.infoTabs(true).map((tab) => tab.label), rows.infoTabs(false).map((tab) => tab.label)], [['About', 'Debug'], ['About']])
  check('the tab shown: the one chosen for an admin; About for anyone else, Debug chosen or not - the role gone while it showed',
    [rows.shownTab('debug', true), rows.shownTab('about', true), rows.shownTab('debug', false), rows.shownTab('about', false)], ['debug', 'about', 'about', 'about'])
  const answer = { level: 'album', state: 'measured', gain_db: -7.42, wanted_db: -7.42, loudness_lufs: -10.6, peak_db: -0.5, held: false, songs: 12, measured_songs: 12, why: null }
  const input = {
    track: track({ ...HIRES, level: 'album' }), gapless: true, maxRate: '48000', gaps: [], lastSeek: null,
    wrapped: { id: 's1', got: 'stream', resampled: { from: 192000, to: 48000 }, hiRes: null }, format: 'raw', song: null, album: null, level: answer,
  }
  //? (2.0.7) About's Sound group has formatters of its own (lib/aboutSound.ts, info.sim): Debug keeps the numbers
  check('About\'s rows are no longer Debug\'s: playingRows and PLAYING_TITLE gone', [typeof rows.playingRows, typeof rows.PLAYING_TITLE], ['undefined', 'undefined'])
  check('...and Debug still says Format, Gapless and Normalization in its own words',
    [rows.formatRow(input.track).value, rows.gaplessRow(input).value, rows.normalizationRow(input).value],
    ['FLAC, 24-bit, 192 kHz, stereo', 'On, in one stream', `Album, -7.42 dB ${DOT} the album at -10.6 LUFS`])
  check('...formatWords, which About shares, is Format\'s words without its "Navidrome didn\'t say"',
    [rows.formatWords(input.track), rows.formatWords(track({ suffix: null, contentType: null, sampleRate: 0, bitDepth: 0, channels: 0 }))], ['FLAC, 24-bit, 192 kHz, stereo', ''])
}

console.log('\nheld to the code they describe')
{
  const resample = fs.readFileSync(path.join(REPO, 'src/resample.py'), 'utf8')
  check('the headroom is src/resample.py\'s HEADROOM_DB', rows.RESAMPLE_HEADROOM_DB, Number(/^HEADROOM_DB\s*=\s*([\d.]+)/m.exec(resample)?.[1]))
  const quality = fs.readFileSync(path.join(UI, 'src/app/QualityChoice.tsx'), 'utf8')
  const labels = Object.fromEntries([...quality.matchAll(/rate: '([^']+)',\s*label: '([^']+)'/g)].map((m) => [m[1], m[2]]))
  check('the setting\'s names are the ones You shows', rows.MAX_RATE_LABELS, labels)
  const source = fs.readFileSync(path.join(UI, 'src/lib/debugRows.ts'), 'utf8')
  check('built on describeGaps, describeSeek and describeWrap', ['describeGaps(', 'describeSeek(', 'describeWrap('].map((name) => source.includes(name)), [true, true, true])
  //? (2.0.9, the type review) the data face only for data: Navidrome's field names are its one value in it - every
  //? other value is a phrase ("FLAC, 16-bit, 44.1 kHz, stereo", "96 kHz to 48 kHz, 3 dB quieter"), in the text face
  const monoRows = [...source.matchAll(/^(?:function|export function) (\w+)[\s\S]*?^}/gm)].filter((m) => /mono: true/.test(m[0])).map((m) => m[1])
  check('the data face only on the field names\' rows', [monoRows, (source.match(/mono: true/g) ?? []).length], [['sentRow', 'otherSongsRow'], 2])
  //? (2.0.7) docs/player.md names Debug's sections as Debug draws them: "Fields from Navidrome", never 2.0.6's
  //? "Navidrome sent" or "What this device is sent" (its not-verified list still said the first, after review)
  const guide = fs.readFileSync(path.join(REPO, 'docs/player.md'), 'utf8').replace(/\s+/g, ' ')
  const titles = [...source.matchAll(/title: '([^']+)'/g)].map((m) => m[1])
  check('docs/player.md names Debug\'s fields section by its title, and neither of its old ones',
    [titles.includes('Fields from Navidrome'), guide.includes('**Fields from Navidrome**'), ['Navidrome sent', 'What this device is sent'].filter((old) => guide.includes(`**${old}**`))],
    [true, true, []])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
