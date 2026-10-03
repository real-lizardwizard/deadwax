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
 *  - Turntable sound (2.0.0-player.14): ready, or off and why, with the cost. Since 2.0.0-player.16
 *    every way the record can't sound reads Off - starting, its window loading, none yet - since a
 *    press then is 2.0.0-player.11's; and the note names the voice: its own audio thread, or the main
 *    thread and why (the page not on HTTPS, the AudioWorklet refused).
 *  - "Navidrome sent": the names of the song's and the album's fields, sorted; those sent EMPTY
 *    ("", 0, [], {} - Navidrome always writes musicBrainzId and discTitles) named apart; the
 *    fields other songs of the album carry and this one doesn't (playCount and played are left
 *    out of a song never played); and "Not known" when the answer isn't in hand.
 *  - The headroom is src/resample.py's HEADROOM_DB and the setting's names are QualityChoice's.
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
  return [all['Sent as'], all.Resampled, all.Why, all.Gapless]
}

console.log('\nthe layout: five sections, their rows in order')
{
  const sections = rows.debugSections(input())
  check('sections', sections.map((section) => section.title), ['The file', 'What this device is sent', 'Last song change and seek', 'The turntable', 'Navidrome sent'])
  check('rows', sections.map((section) => section.rows.map((row) => row.label)), [
    ['Format'], ['Sent as', 'Resampled', 'Why', 'Gapless'], ['Gap', 'Last seek'], ['Turntable sound'], ['Song', 'On other songs', 'Album'],
  ])
}

console.log('\nTurntable sound (2.0.0-player.14): ready, or off and why - how an iPhone says what WebKit made of it')
{
  const turntable = (report) => rows.turntableRow(report)
  const ready = {
    context: 'running', problem: null, window: { start: 42, end: 72.4, kind: 'FLAC', decodedAt: 48000, bytes: 3_400_000 },
    loading: false, refused: null, failed: null, fetched: 6_800_000, lastFetchAt: 61_000,
  }
  check('ready: the stretch of the song, its kind, the rate it was decoded at; what windows have cost on a line under it',
    [turntable(ready).value, turntable(ready).note, turntable(ready).mono],
    ['Ready: 0:42-1:12, FLAC, decoded at 48 kHz', '3.4 MB a window; 6.8 MB fetched since the turntable showed, the last window 1:01 in', true])
  check('...and the row in the debug sections, from what Info is handed',
    table(rows.debugSections(input({ turntable: ready })))['Turntable sound'], ['Ready: 0:42-1:12, FLAC, decoded at 48 kHz', '3.4 MB a window; 6.8 MB fetched since the turntable showed, the last window 1:01 in'])
  check('no turntable showing', [turntable(null).value, table(rows.debugSections(input()))['Turntable sound']],
    ["Off: the turntable isn't showing", "Off: the turntable isn't showing"])
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
  check('waiting for a tap: the audio context starts only from one - and a window ready meanwhile is said under it',
    [turntable({ ...ready, context: 'none', window: null, fetched: 0 }), turntable({ ...ready, context: 'none' }).note],
    [{ label: 'Turntable sound', value: 'Off: waiting for a tap to start the sound' },
      `Its window is ready: 0:42-1:12, FLAC, decoded at 48 kHz ${DOT} 3.4 MB a window; 6.8 MB fetched since the turntable showed, the last window 1:01 in`])
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
  check('...the cost said only once something was fetched', turntable({ ...ready, window: null, loading: true, fetched: 0 }).note, undefined)
  check('...and measured to the moment the last window came - the report is made as things change, not as time passes - never a running clock it hasn\'t got',
    turntable({ ...ready, fetched: 2_500_000, lastFetchAt: 1_200 }).note, '3.4 MB a window; 2.5 MB fetched since the turntable showed, the last window 0:01 in')
}

console.log('\nTurntable sound (2.0.0-player.16): which voice plays it, and why')
{
  const turntable = (report) => rows.turntableRow(report)
  const ready = {
    context: 'running', problem: null, voice: 'script', voiceWhy: "this page isn't on HTTPS, so the browser has no AudioWorklet",
    window: { start: 31, end: 72.6, kind: 'FLAC', decodedAt: 44100, bytes: 3_400_000 },
    loading: false, refused: null, failed: null, fetched: 0, lastFetchAt: 0,
  }
  check('on the main thread, the page not on HTTPS: ready - and the note says where it plays and why',
    [turntable(ready).value, turntable(ready).note], ['Ready: 0:31-1:12, FLAC, decoded at 44.1 kHz', "On the main thread - this page isn't on HTTPS, so the browser has no AudioWorklet"])
  check('...the AudioWorklet refused: its words',
    turntable({ ...ready, voiceWhy: "the AudioWorklet wouldn't load (SyntaxError: Unexpected token)" }).note, "On the main thread - the AudioWorklet wouldn't load (SyntaxError: Unexpected token)")
  check('the worklet: its own audio thread',
    turntable({ ...ready, voice: 'worklet', voiceWhy: null }).note, 'On its own audio thread (an AudioWorklet)')
  check('...the voice said before the cost, on every row that has one - an off one too',
    [turntable({ ...ready, fetched: 6_800_000, lastFetchAt: 61_000 }).note, turntable({ ...ready, window: null, loading: true }).note],
    [`On the main thread - this page isn't on HTTPS, so the browser has no AudioWorklet ${DOT} 3.4 MB a window; 6.8 MB fetched since the turntable showed, the last window 1:01 in`,
      "On the main thread - this page isn't on HTTPS, so the browser has no AudioWorklet"])
  check('...and none named while there is none', turntable({ ...ready, voice: null, voiceWhy: null, window: null }).note, undefined)
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
check('set in the data face', rows.formatRow(track()).mono, true)

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
check('no gaps yet', rows.gapRow([]), { label: 'Gap', value: 'No song change timed yet' })
check('a stream change', rows.gapRow([streamReading(0)]), { label: 'Gap', value: '0 ms, in one stream' })
check('handovers, the earlier ones on their own line', rows.gapRow([handover(96), oneElement(581), oneElement(511), handover(2867, 'unfinished'), oneElement(218)]),
  { label: 'Gap', value: '96 ms, handed over, from memory', note: 'Earlier: 581, 511, 2867, 218 ms' })
check('a failed change', rows.gapRow([oneElement(1650, { failed: true })]), { label: 'Gap', value: '1650 ms, one element, failed before playing' })
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

console.log('\n"Navidrome sent": the names of the fields, as they came')
{
  const song = { id: 's1', title: 'Time', musicBrainzId: 'mb', played: '2026-09-30', playCount: 12, discNumber: 1, bitDepth: 24 }
  const album = { id: 'a1', name: 'The Dark Side of the Moon', discTitles: [{ disc: 1, title: 'Side one' }], song: [song], year: 1973 }
  const all = table(rows.debugSections(input({ song, album })))
  check('the song\'s, sorted as plain strings', all.Song, 'bitDepth, discNumber, id, musicBrainzId, playCount, played, title')
  check('the album\'s, its song list and disc titles included', all.Album, 'discTitles, id, name, song, year')
  check('only the names - no value leaks into the row', /2026|Time|Moon|12|Side/.test(JSON.stringify([all.Song, all.Album])), false)
  check('the names in the data face', rows.debugSections(input({ song, album }))[4].rows.map((row) => [row.label, row.mono ?? false]), [['Song', true], ['On other songs', false], ['Album', true]])
  check('one song on the album: nothing on others it lacks', all['On other songs'], 'Nothing this song lacks')
  const none = table(rows.debugSections(input()))
  check('not in hand: said so, nothing invented', [none.Song, none['On other songs'], none.Album], ['Not known', 'Not known', 'Not known'])
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
    all.Song, ['id, isDir, title, track', 'Empty: bitDepth, bpm, genres, musicBrainzId, replayGain'])
  check('...on the album too: musicBrainzId "" and discTitles [] are sent, empty; false is a value',
    all.Album, ['id, isCompilation, name, song', 'Empty: discTitles, musicBrainzId, releaseDate, userRating'])
  check('the fields another song carries and this one doesn\'t: a song never played has no playCount',
    all['On other songs'], 'playCount, played, starred')
  check('...names only, in the data face', [/2026|Money|3/.test(all['On other songs']), sections[4].rows[1].mono], [false, true])
  check('a field empty here and filled on another song counts as one this song lacks',
    rows.otherSongsFields({ id: 'x', musicBrainzId: '' }, { song: [{ id: 'x', musicBrainzId: '' }, { id: 'y', musicBrainzId: 'abc' }] }), ['musicBrainzId'])
  check('the song itself, found again by id in the album\'s list, is not "another song"',
    rows.otherSongsFields({ id: 'x', a: 1 }, { song: [{ id: 'x', a: 1, b: 2 }] }), [])
  check('what counts as empty', [rows.isEmptyValue(''), rows.isEmptyValue(0), rows.isEmptyValue([]), rows.isEmptyValue({}), rows.isEmptyValue(null),
    rows.isEmptyValue(false), rows.isEmptyValue('x'), rows.isEmptyValue([0]), rows.isEmptyValue({ a: 0 })], [true, true, true, true, true, false, false, false, false])
  check('an answer of empty fields only', table([{ title: 't', rows: [rows.debugSections(input({ song: { a: '' }, album: null }))[4].rows[0]] }]).Song,
    ['Nothing with a value', 'Empty: a'])
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
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
