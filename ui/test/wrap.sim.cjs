/**
 * Which browsers ask for their FLAC songs inside an MP4 (lib/streamWrap.ts), and what the readout
 * says about what came back.
 *
 * Safari's engine lands a seek in a FLAC seconds off and in an MP4 of the same frames exactly;
 * Chromium lands both exactly. So what this pins is the line between them, drawn from user agents
 * the real browsers send: every browser on an iPhone is WebKit (Chrome and Firefox there too), an
 * iPad asking for desktop sites says it is a Mac, and Chromium says AppleWebKit as well as Chrome -
 * Arc on a Mac, which James uses, is Chromium and must keep the file as it is. And that only a FLAC,
 * asked for as it is, is ever wrapped.
 *
 * And the one rule for which songs deadwax resamples at "Up to 48 kHz" - the same table as the
 * server's, and only depths the server can read - with what the readout says deadwax did, or, under
 * "Original", the rate a hi-res song kept in a stream.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/wrap.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-wrap-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/streamWrap.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

const {
  isAppleWebKit, wrapsFlac, isFlac, asksForMp4, wrappedAs, describeWrap, FLAC_IN_MP4,
  resamples, resampledFrom, RESAMPLED_TO, DEFAULT_MAX_RATE,
} = require(path.join(OUT, 'lib/streamWrap.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const UA = {
  iphoneSafari: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1',
  iphoneHomeScreen: 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
  iphoneChrome: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/140.0.7339.101 Mobile/15E148 Safari/604.1',
  iphoneFirefox: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/142.0 Mobile/15E148 Safari/605.1.15',
  ipadSafari: 'Mozilla/5.0 (iPad; CPU OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1',
  //? an iPad asking for desktop sites - the default in iPadOS Safari - says it is a Mac
  macLike: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15',
  macChrome: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  macEdge: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0',
  macOpera: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36 OPR/123.0.0.0',
  macFirefox: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0',
  androidChrome: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36',
  androidWebView: 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/140.0.0.0 Mobile Safari/537.36',
  samsung: 'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/28.0 Chrome/130.0.0.0 Mobile Safari/537.36',
  windowsChrome: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
  headless: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/140.0.0.0 Safari/537.36',
  linuxFirefox: 'Mozilla/5.0 (X11; Linux x86_64; rv:143.0) Gecko/20100101 Firefox/143.0',
  epiphany: 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15',
  //? an iPad browser asking for desktop sites AS CHROME (Edge's desktop mode) - still WebKit underneath
  ipadAsChrome: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.0.0',
  //? an in-app browser on an iPhone that adds a Chrome/ token of its own
  iphoneInApp: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Chrome/140.0.0.0 Safari/604.1',
}

/* ========================================================================== */
console.log('\nWebKit that isn\'t Chromium')

check('Safari on an iPhone', isAppleWebKit(UA.iphoneSafari, 5), true)
check('the home-screen app on an iPhone (no Safari/ in its agent)', isAppleWebKit(UA.iphoneHomeScreen, 5), true)
check('Chrome on an iPhone is WebKit (CriOS)', isAppleWebKit(UA.iphoneChrome, 5), true)
check('Firefox on an iPhone is WebKit (FxiOS)', isAppleWebKit(UA.iphoneFirefox, 5), true)
check('Safari on an iPad', isAppleWebKit(UA.ipadSafari, 5), true)
check('an iPad asking for desktop sites, saying it is a Mac, with touch points', isAppleWebKit(UA.macLike, 5), true)
check('...even saying it is Chrome on a Mac: the touch points say iPad, and an iPad is WebKit', isAppleWebKit(UA.ipadAsChrome, 5), true)
check('an iPhone agent with a Chrome/ in it is still an iPhone, and WebKit', isAppleWebKit(UA.iphoneInApp, 5), true)
check('Safari on a Mac (no touch points)', isAppleWebKit(UA.macLike, 0), true)
check('Chrome on a Mac is not - and Arc sends exactly this', isAppleWebKit(UA.macChrome, 0), false)
check('Edge on a Mac is not', isAppleWebKit(UA.macEdge, 0), false)
check('Opera on a Mac is not', isAppleWebKit(UA.macOpera, 0), false)
check('Firefox on a Mac is not', isAppleWebKit(UA.macFirefox, 0), false)
check('Chrome on Android is not', isAppleWebKit(UA.androidChrome, 5), false)
check('an Android web view is not', isAppleWebKit(UA.androidWebView, 5), false)
check('Samsung Internet is not', isAppleWebKit(UA.samsung, 5), false)
check('Chrome on Windows is not', isAppleWebKit(UA.windowsChrome, 0), false)
check('headless Chrome is not', isAppleWebKit(UA.headless, 0), false)
check('Firefox on Linux is not', isAppleWebKit(UA.linuxFirefox, 0), false)
check('WebKit on Linux (Epiphany) is - lossless either way, and it is asked about MP4 next', isAppleWebKit(UA.epiphany, 0), true)
check('nothing said at all is not', isAppleWebKit('', 0), false)

/* ========================================================================== */
console.log('\nthe page decides once: WebKit, and a yes to FLAC in an MP4')

const saysYes = (type) => (type === FLAC_IN_MP4 ? 'maybe' : '')
const saysNo = () => ''
check('Safari on an iPhone that can play it', wrapsFlac({ userAgent: UA.iphoneSafari, maxTouchPoints: 5, canPlayType: saysYes }), true)
check('...one that can\'t (an old iOS) keeps the FLAC', wrapsFlac({ userAgent: UA.iphoneSafari, maxTouchPoints: 5, canPlayType: saysNo }), false)
check('Chrome on a Mac that says it can still keeps the FLAC', wrapsFlac({ userAgent: UA.macChrome, maxTouchPoints: 0, canPlayType: saysYes }), false)
{
  const asked = []
  wrapsFlac({ userAgent: UA.iphoneSafari, maxTouchPoints: 5, canPlayType: (type) => { asked.push(type); return 'probably' } })
  check('the browser is asked about FLAC in an MP4, with its codec', asked, ['audio/mp4; codecs="flac"'])
}

/* ========================================================================== */
console.log('\nwhich songs')

check('a .flac', isFlac({ suffix: 'flac', contentType: 'audio/flac' }), true)
check('a .FLAC typed nothing', isFlac({ suffix: 'FLAC', contentType: null }), true)
check('typed audio/flac, no suffix', isFlac({ suffix: null, contentType: 'audio/flac' }), true)
check('typed audio/x-flac', isFlac({ suffix: null, contentType: 'audio/x-flac; charset=binary' }), true)
check('an MP3', isFlac({ suffix: 'mp3', contentType: 'audio/mpeg' }), false)
check('an ALAC m4a', isFlac({ suffix: 'm4a', contentType: 'audio/mp4' }), false)
check('an Ogg', isFlac({ suffix: 'ogg', contentType: 'audio/ogg' }), false)
check('nothing said', isFlac({ suffix: null, contentType: null }), false)

const flac = { suffix: 'flac', contentType: 'audio/flac' }
check('a FLAC, as it is, on a page that wraps', asksForMp4(flac, 'raw', true), true)
check('a FLAC on a page that doesn\'t (Chromium)', asksForMp4(flac, 'raw', false), false)
check('a FLAC this browser can\'t play, transcoded to MP3: nothing to repackage', asksForMp4(flac, 'mp3', true), false)
check('an MP3 on a page that wraps', asksForMp4({ suffix: 'mp3', contentType: 'audio/mpeg' }, 'raw', true), false)

/* ========================================================================== */
console.log('\nwhat came back, and what the readout says')

check('audio/mp4 is an MP4', wrappedAs('audio/mp4'), 'mp4')
check('...with parameters, and in capitals', wrappedAs('Audio/MP4; foo=bar'), 'mp4')
check('audio/flac is the FLAC as it is', wrappedAs('audio/flac'), 'flac')
check('no type at all is not an MP4', wrappedAs(null), 'flac')

check('a song not asked for that way: nothing added', describeWrap(null, 's1'), '')
check('asked, the answer not in yet', describeWrap({ id: 's1', got: null }, 's1'), ' · asked for FLAC in MP4')
check('an MP4 came', describeWrap({ id: 's1', got: 'mp4' }, 's1'), ' · FLAC in MP4')
check('the FLAC came instead', describeWrap({ id: 's1', got: 'flac' }, 's1'), ' · sent as FLAC, not in an MP4')
check('about another song than the one playing: nothing', describeWrap({ id: 's1', got: 'mp4' }, 's2'), '')
//? a song inside a one-stream run: fragmented MP4 appended to a MediaSource, known as it plays
check('a song playing in one stream', describeWrap({ id: 's1', got: 'stream' }, 's1'), ' · in one stream')
check('...about another song: nothing', describeWrap({ id: 's1', got: 'stream' }, 's2'), '')
//? the same answers with the field every Wrapped carries now, saying nothing was resampled
for (const got of ['mp4', 'flac', 'stream', null]) {
  check(`${got}, resampled: null - the line as it was`, describeWrap({ id: 's1', got, resampled: null }, 's1'), describeWrap({ id: 's1', got }, 's1'))
}

/* ========================================================================== */
console.log('\nwhich songs deadwax resamples, at "Up to 48 kHz"')

const hires = (rate, fields = {}) => ({ suffix: 'flac', contentType: 'audio/flac', sampleRate: rate, bitDepth: 24, ...fields })
check('the table: 2, 4 and 8 times 44.1 kHz to 44.1, and of 48 kHz to 48 - nothing else', RESAMPLED_TO,
  { 88200: 44100, 176400: 44100, 352800: 44100, 96000: 48000, 192000: 48000, 384000: 48000 })
for (const rate of [88200, 176400, 352800, 96000, 192000, 384000]) check(`a ${rate / 1000} kHz FLAC`, resamples(hires(rate), '48000', 'raw'), true)
for (const rate of [44100, 48000, 32000]) check(`a ${rate / 1000} kHz FLAC is never touched`, resamples(hires(rate), '48000', 'raw'), false)
for (const rate of [64000, 100000, 50000]) check(`a ${rate / 1000} kHz FLAC, no whole ratio: sent as it is`, resamples(hires(rate), '48000', 'raw'), false)
check('a rate Navidrome didn\'t give (0): unknown, not resampled', resamples(hires(0), '48000', 'raw'), false)
check('...nor one missing altogether (a track built before the field)', resamples({ suffix: 'flac', contentType: 'audio/flac' }, '48000', 'raw'), false)
check('16-bit', resamples(hires(96000, { bitDepth: 16 }), '48000', 'raw'), true)
check('a depth Navidrome didn\'t give: the server decides', resamples(hires(96000, { bitDepth: 0 }), '48000', 'raw'), true)
check('...nor any depth field at all', resamples({ suffix: 'flac', contentType: 'audio/flac', sampleRate: 96000 }, '48000', 'raw'), true)
check('20-bit: the server can\'t read it, so it isn\'t asked', resamples(hires(96000, { bitDepth: 20 }), '48000', 'raw'), false)
check('32-bit: neither', resamples(hires(192000, { bitDepth: 32 }), '48000', 'raw'), false)
check('an MP3 at 192 kHz (it isn\'t a FLAC)', resamples(hires(192000, { suffix: 'mp3', contentType: 'audio/mpeg' }), '48000', 'raw'), false)
check('a hi-res ALAC', resamples(hires(192000, { suffix: 'm4a', contentType: 'audio/mp4' }), '48000', 'raw'), false)
check('a FLAC typed audio/flac with no suffix', resamples(hires(96000, { suffix: null }), '48000', 'raw'), true)
check('a FLAC this browser can\'t play, transcoded: nothing to resample', resamples(hires(192000), '48000', 'mp3'), false)
check('"Original": nothing is', resamples(hires(192000), 'original', 'raw'), false)
check('the default is 48 kHz', DEFAULT_MAX_RATE, '48000')

check('a resampled song is asked for in an MP4 in Chromium too', asksForMp4(flac, 'raw', false, true), true)
check('...and in Safari, as it would be anyway', asksForMp4(flac, 'raw', true, true), true)
check('...but never a transcode', asksForMp4(flac, 'mp3', false, true), false)
check('...nor an MP3', asksForMp4({ suffix: 'mp3', contentType: 'audio/mpeg' }, 'raw', false, true), false)
check('not resampled, in Chromium: the file as it is, as before', asksForMp4(flac, 'raw', false, false), false)

/* ========================================================================== */
console.log('\nwhat deadwax says it did, and the readout')

check('X-Deadwax-Resampled: 192000-48000', resampledFrom('192000-48000'), { from: 192000, to: 48000 })
check('...88.2 to 44.1, with spaces round it', resampledFrom(' 88200-44100 '), { from: 88200, to: 44100 })
check('no header', resampledFrom(null), null)
for (const junk of ['', '192000', '192000-', '-48000', '192000:48000', '192 kHz-48 kHz', '0-48000', '192000-48000-1']) {
  check(`"${junk}": not read`, resampledFrom(junk), null)
}
const from192 = { from: 192000, to: 48000 }
check('an MP4, resampled', describeWrap({ id: 's1', got: 'mp4', resampled: from192 }, 's1'), ' · FLAC in MP4, 192 kHz resampled to 48 kHz')
check('in one stream, resampled', describeWrap({ id: 's1', got: 'stream', resampled: from192 }, 's1'), ' · in one stream, 192 kHz resampled to 48 kHz')
check('the 44.1 family says its tenths', describeWrap({ id: 's1', got: 'mp4', resampled: { from: 176400, to: 44100 } }, 's1'), ' · FLAC in MP4, 176.4 kHz resampled to 44.1 kHz')
check('...and 88.2, 352.8', [88200, 352800].map((from) => describeWrap({ id: 's1', got: 'stream', resampled: { from, to: 44100 } }, 's1')),
  [' · in one stream, 88.2 kHz resampled to 44.1 kHz', ' · in one stream, 352.8 kHz resampled to 44.1 kHz'])
check('the FLAC sent as it is says nothing of resampling', describeWrap({ id: 's1', got: 'flac', resampled: from192 }, 's1'), ' · sent as FLAC, not in an MP4')
check('another song: nothing', describeWrap({ id: 's1', got: 'mp4', resampled: from192 }, 's2'), '')

//? under "Original" a hi-res song streams as it is, and the line shows the rate it kept
const kept = (hiRes, got = 'stream') => describeWrap({ id: 's1', got, resampled: null, hiRes }, 's1')
check('in one stream, as it is at 192 kHz', kept(192000), ' · in one stream, 192 kHz')
check('...96, 176.4 and 352.8 kHz', [96000, 176400, 352800].map((rate) => kept(rate)),
  [' · in one stream, 96 kHz', ' · in one stream, 176.4 kHz', ' · in one stream, 352.8 kHz'])
check('no rate kept: the line as it was', [kept(null), describeWrap({ id: 's1', got: 'stream', resampled: null }, 's1')], [' · in one stream', ' · in one stream'])
check('what deadwax resampled says so, whatever else is set', describeWrap({ id: 's1', got: 'stream', resampled: from192, hiRes: 192000 }, 's1'),
  ' · in one stream, 192 kHz resampled to 48 kHz')
check('the FLAC sent as it is says nothing of a rate', kept(192000, 'flac'), ' · sent as FLAC, not in an MP4')
check('another song: nothing', describeWrap({ id: 's1', got: 'stream', resampled: null, hiRes: 192000 }, 's2'), '')

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
