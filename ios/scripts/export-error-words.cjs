#!/usr/bin/env node
/**
 * The iPhone app's error words, as the web app's own TypeScript says them (Phase 1, notes/ios.md): ui/src/lib/
 * errorWords.ts and lib/signIn.ts compiled with the repo's TypeScript - as ui/test/errors.sim.cjs compiles them - and
 * run on every case below, with their tables and sentences, and the words a few pages and the player say beside
 * them (read out of their sources). Written to
 *
 *   ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/errors/error-words.json
 *
 * which DeadwaxCoreTests' ErrorWordsTests replays against DeadwaxCore's ErrorWords.swift - the port - so a sentence,
 * a class or a plumbing pattern changed on the web and not in the app (or the other way about) fails a test.
 *
 *   node ios/scripts/export-error-words.cjs           writes the fixture
 *   node ios/scripts/export-error-words.cjs --check   fails when the fixture isn't what the TypeScript says now
 *                                                     (ui/test/ioserrorwords.sim.cjs runs this in CI)
 *
 * The cases are errors.sim's own - its classes, the raw errors it scans, the named refusals, its plumbing and
 * sentence vectors - and the sign-in's (signin.sim.cjs), with the edges a port gets wrong added: JavaScript's \s, \b
 * and /i against ICU's, trim's set, a first character outside the BMP, canonically equal spellings. Characters
 * outside ASCII are made with String.fromCharCode here and written as JSON escapes, so neither file holds one raw.
 * Needs ui/node_modules (npm install in ui/) and a writable TMPDIR.
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/errors/error-words.json')
const CHECK = process.argv.includes('--check')

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-ios-errors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/errorWords.ts', 'src/lib/signIn.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const E = require(path.join(OUT, 'lib/errorWords.js'))
const S = require(path.join(OUT, 'lib/signIn.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))
fs.rmSync(OUT, { recursive: true, force: true })

/** A character by its code (or several) - never a raw one in this file. */
const ch = (...codes) => String.fromCharCode(...codes)
const VT = ch(0x0b), FF = ch(0x0c), NBSP = ch(0xa0), OGHAM = ch(0x1680), THIN = ch(0x2009), LS = ch(0x2028), PS = ch(0x2029)
const NARROW = ch(0x202f), MATH = ch(0x205f), IDEO = ch(0x3000), BOM = ch(0xfeff), NEL = ch(0x85), MONGOLIAN = ch(0x180e)
const ZWSP = ch(0x200b), ELLIPSIS = ch(0x2026)
const E_ACUTE = ch(0xe9), E_COMBINING = 'e' + ch(0x301), SHARP_S = ch(0xdf), LONG_S = ch(0x17f), KELVIN = ch(0x212a)
/* a cased letter outside the BMP: JavaScript's charAt(0) is its lone high surrogate, which toUpperCase leaves be, where
 * Swift's uppercased() would make U+10428 U+10400 */
const DESERET = String.fromCodePoint(0x10428)
const SMILE = String.fromCodePoint(0x1f600), DZ = ch(0x1c6), NAPOSTROPHE = ch(0x149), DOTLESS_I = ch(0x131), LIGATURE_FF = ch(0xfb00)

/* ===== the errors ================================================================================ */

/** An error as the fixture says it, made as the web makes it: api/http.ts's ApiError (its message `detail || "METHOD
 *  path failed"`), fetch's TypeError, a TimeoutError, or any other Error. */
function made(spec) {
  if (spec.answer) {
    const a = spec.answer
    const method = a.method ?? 'GET'
    return new ApiError(a.status, a.detail ?? null, `${method} ${a.path} failed`, a.busy === true, a.kind ?? null, a.why ?? null, a.path)
  }
  if ('offline' in spec) return new TypeError(spec.offline)
  if ('timeout' in spec) return Object.assign(new Error(spec.timeout), { name: 'TimeoutError' })
  return new Error(spec.other)
}

const answer = (status, detail, route = '/library/x', why = null, extra = {}) => {
  const spec = { status, path: route }
  if (detail !== null) spec.detail = detail
  if (why !== null) spec.why = why
  return { answer: { ...spec, ...extra } }
}
const named = (status, detail, kind) => answer(status, detail, '/me/password', null, { method: 'POST', kind })

const ERRORS = [
  // errors.sim: the classes
  { offline: 'Failed to fetch' },
  { offline: 'Load failed' },
  { offline: 'NetworkError when attempting to fetch resource.' },
  answer(504, null),
  answer(408, null),
  { timeout: 'signal timed out' },
  answer(502, "Navidrome couldn't be reached at http://navidrome:4533: All connection attempts failed", '/navidrome/artists'),
  answer(503, "Navidrome isn't set up - fill in NAVIDROME_URL, NAVIDROME_USER and NAVIDROME_PASSWORD in Server settings (Connections)", '/navidrome/albums'),
  answer(404, 'Not Found'),
  answer(401, 'Sign in to use deadwax.'),
  answer(403, "That needs Edit albums, which an admin hasn't given you. You're signed in as ethan."),
  answer(409, 'Home holds up to 50 pins - unpin one first', '/me/pins'),
  answer(503, "deadwax can't keep pins: its database isn't writable", '/me/pins'),
  answer(503, "deadwax can't read its database just now, so it can't check who you are.", '/me', "deadwax can't read its database, so nothing is let in until it can. Check DB_PATH points at a writable volume."),
  answer(500, "Error searching slskd: HTTPConnectionPool(host='127.0.0.1', port=5030): Max retries exceeded", '/download/find_candidates'),
  answer(422, 'LIBRARY_PATH: not a folder'),
  { other: 'Unexpected token < in JSON at position 0' },
  { other: "Cannot read properties of undefined (reading 'id')" },
  answer(502, null, '/navidrome/x'),
  answer(502, null, '/download/jobs'),
  answer(502, null, '/monitor_slskd/ping'),
  answer(502, null, '/me/pins'),
  answer(502, "slskd isn't logged in to Soulseek", '/download/find_candidates'),
  answer(503, null, '/me'),
  answer(502, 'slskd refused the download (500)', '/download/enqueue'),
  answer(404, 'Navidrome has nothing by that id', '/navidrome/albums/x'),
  answer(404, "That playlist isn't on Navidrome any more - deleted in another app, maybe.", '/navidrome/playlists/x'),
  answer(401, 'x'),
  answer(403, "That needs Edit albums, which an admin hasn't given you."),
  answer(403, 'DEADWAX_ADMINS'),
  answer(409, 'reel2reel refused', '/download/retry'),
  answer(502, "The songs were saved, but Navidrome didn't take the name, description or sharing.", '/navidrome/playlists/x', 'Navidrome said: locked'),
  // errors.sim: refusals deadwax named a kind of
  named(504, "Navidrome didn't answer in time, so deadwax can't tell whether your password changed. If it did, deadwax asks you to sign in again within a few minutes - with the new one; if not, try again.", 'timed_out'),
  named(500, "Navidrome changed your password, but deadwax couldn't keep the new one - sign out and sign in again with the new password.", 'not_kept'),
  named(409, "Navidrome says that isn't your current password - nothing changed.", 'wrong_current'),
  named(502, "Navidrome answered in a way deadwax doesn't know (RemoteProtocolError)", 'unknown_shape'),
  named(401, 'x', 'gone'),
  // errors.sim: every raw error the app is known to meet
  answer(500, "Error searching slskd: HTTPConnectionPool(host='127.0.0.1', port=4559): Max retries exceeded with url: /api/v0/searches (Caused by NewConnectionError('<urllib3.connection.HTTPConnection object at 0x7f>: Failed to establish a new connection: [Errno 111] Connection refused'))", '/download/find_candidates'),
  answer(502, 'slskd is not connected to the Soulseek network, so it cannot search', '/download/find_candidates'),
  answer(502, "couldn't reach slskd to queue it: HTTPConnectionPool(host='slskd', port=5030)", '/download/enqueue'),
  answer(502, "Navidrome couldn't be reached at http://127.0.0.1:4558: All connection attempts failed", '/navidrome/albums'),
  answer(502, "the answer wasn't a Subsonic one - is NAVIDROME_URL the address of Navidrome itself?", '/navidrome/albums'),
  answer(502, 'Navidrome refused the login - check NAVIDROME_USER and NAVIDROME_PASSWORD', '/navidrome/albums'),
  answer(502, 'Navidrome said: database is locked', '/navidrome/albums'),
  answer(502, 'Navidrome answered 500', '/navidrome/albums'),
  answer(500, "Error queueing download: [Errno 13] Permission denied: '/downloads/x'", '/download/enqueue'),
  answer(503, 'NAVIDROME_URL is unusable (it has a user name or password in it), so deadwax sends nothing to it - fix it in Server settings (Connections), or in your compose file', '/navidrome/x'),
  answer(503, "Logins are on, but DEADWAX_SECRET_KEY isn't set, so deadwax can't sign anyone in.", '/me'),
  answer(422, 'SLSKD_URL: has no scheme'),
  answer(500, null),
  { other: 'GET /navidrome/albums failed' },
  // signin.sim: the sign-in's own answers
  answer(429, 'Too many tries - wait 30 seconds and try again.', '/auth/login', null, { method: 'POST' }),
  answer(401, null, '/auth/login', null, { method: 'POST' }),
  answer(429, null, '/auth/login', null, { method: 'POST' }),
  answer(500, null, '/auth/login', null, { method: 'POST' }),
  answer(503, "deadwax can't sign anyone in just now.", '/auth/login', "Logins are on, but DEADWAX_SECRET_KEY isn't set.", { method: 'POST' }),
  answer(502, "Navidrome couldn't be reached at http://navidrome:4533", '/auth/login', null, { method: 'POST' }),
  answer(401, "That user name and password didn't work for Navidrome.", '/auth/login', null, { method: 'POST' }),
  // the edges: words that are and aren't fit, a why with no detail, a kind with plumbing, an empty detail
  answer(404, ' Not Found '),
  answer(404, ''),
  answer(404, null, '/navidrome/albums/al-1'),
  answer(503, '', '/me', 'Check DB_PATH.'),
  answer(502, null, '/navidrome/queue', 'Navidrome said: no'),
  answer(504, 'DB_PATH is slow', '/me/password', null, { method: 'POST', kind: 'timed_out' }),
  answer(504, 'It took too long, try again', '/me/password', null, { method: 'POST', kind: '' }),
  answer(409, 'Already in your library.', '/me/library/add', null, { method: 'POST' }),
  answer(409, 'answered 409', '/me/library/add', null, { method: 'POST' }),
  answer(400, 'That scope is not one deadwax knows', '/navidrome/album_index?scope=x'),
  answer(418, null, '/navidrome/x'),
  answer(503, 'MusicBrainz is busy just now', '/search_musicbrainz/release', null, { busy: true }),
  answer(503, "deadwax can't keep your library just now", '/me/library', 'deadwax said: no', { kind: 'busy' }),
  answer(500, "It's out of your library, but deadwax couldn't save that.", '/me/library/remove', null, { method: 'POST' }),
  answer(409, 'that one, by reel2reel', '/navidrome/queue/at', null, { method: 'POST' }),
  answer(409, '  padded words  ', '/navidrome/queue/at', null, { method: 'POST' }),
  { offline: 'The network connection was lost.' },
  { timeout: 'The request timed out.' },
  { other: "deadwax's answer couldn't be read (Album: no id). Is the app older or newer than the server?" },
]

/** The ways a page asks for the words (errorWords.ts ErrorOptions). */
const OPTIONS = [
  {},
  { admin: true },
  { retry: true },
  { admin: true, retry: true },
  { service: 'music' },
  { service: 'downloads', failed: "The download couldn't be started." },
  { gone: "This album isn't here any more." },
  { admin: true, gone: '' },
  { admin: true, failed: "Couldn't save.", retry: true },
  { service: 'deadwax', admin: true },
]

const errors = ERRORS.map((spec) => {
  const error = made(spec)
  return {
    error: spec,
    kind: E.errorKind(error),
    service: E.serviceOf(error),
    raw: E.rawWords(error),
    sign_in_problem: S.signInProblem(error),
    sign_in_why: S.signInWhy(error),
    unanswered: E.unansweredLine(error),
    //? one for each of OPTIONS, in its order; each way's kind is the error's (errorWords's is errorKind's), and its said
    //? line is in its notice, after the lead
    ways: OPTIONS.map((options) => {
      const words = E.errorWords(error, options)
      if (words.kind !== E.errorKind(error) || !E.noticeWords('Not saved.', error, options).startsWith(`Not saved. ${E.said(words)}`)) {
        throw new Error(`errorWords changed shape: ${JSON.stringify(spec)}`)
      }
      return { text: words.text, advice: words.advice, detail: words.detail, notice: E.noticeWords('Not saved.', error, options) }
    }),
  }
})

/* ===== the words ================================================================================= */

const PLUMBING = [
  // errors.sim's
  'DB_PATH points', 'at http://x', 'a ConnectError', '[Errno 2]', "file '/music/a/b'", 'slskd is down', 'GET /me failed', 'answered 502',
  'Navidrome said: no', 'That playlist changed in another app', "deadwax can't keep pins: its database isn't writable",
  // the edges
  null, '', 'HTTPS://X', 'hTtP://x', 'http:/x', 'ftp://x', 'DB_PATHx', 'xDB_PATH', 'Db_Path', 'A_B', 'A_', '_A_B', 'MY_VAR2 set', 'My_Var',
  'A_b', '9_A', 'NotAnError', 'Errors', 'ValueError:', 'error', 'Exceptional', 'Exception', 'xException', '_Exception', 'Errno',
  'host=1', 'ghost=1', 'a host=1', 'port=2', 'support=2', 'Traceback (most recent call last)', 'Max retries', 'max retries',
  'GET /x', 'XGET /x', 'get /x', 'POST/x', 'PATCH /', 'DELETE /a', '/a/b', ' /a/b', 'x/a/b', '(/a/b', '"/a/', "'/a/b", '/a/', '/a',
  'see /a/b', 'tab\t/a/b', 'line\n/a/b', VT + '/a/b', FF + '/a/b', NBSP + '/a/b', OGHAM + '/a/b', THIN + '/a/b', LS + '/a/b',
  PS + '/a/b', NARROW + '/a/b', MATH + '/a/b', IDEO + '/a/b', BOM + '/a/b', NEL + '/a/b', MONGOLIAN + '/a/b', ZWSP + '/a/b',
  E_ACUTE + '/a/b', '/' + E_ACUTE + '/b', '/a.b-c_d/', '/a b/c', 'SLSKD', 'Slskd broke', 'slskd_x', 'xslskd', 'slskd-x', 'subsonic',
  'SubSonic API', LONG_S + 'lskd', 'sls' + KELVIN + 'd', 'slsKd', 'answered 500', 'answered 600', 'answered 5000', 'answered 50',
  'answered  500', 'HTTP 404', 'http 404', 'HTTP 4040', 'HTTP 199', 'Navidrome said', 'Navidrome says', 'Navidrome saidx',
  'MusicBrainz said:', 'xNavidrome said', 'musicbrainz said', 'a ' + SMILE + ' /a/b',
].map((text) => ({ text, plumbing: E.plumbing(text) }))

const SENTENCES = [
  'deadwax broke', 'slskd broke', 'it broke', '  it broke  ', 'deadwaxy broke', 'deadwax_x', 'deadwax-y', 'deadwax', 'Deadwax',
  'slskd!', 'ends.', 'ends!', 'ends?', 'ends' + ELLIPSIS, 'ends.\n', 'ends. ', '', '   ', SHARP_S + ' is sharp', E_COMBINING + 'lan',
  E_ACUTE + 'lan', DZ + ' digraph', NAPOSTROPHE + ' apostrophe', DOTLESS_I + ' dotless', LIGATURE_FF + ' ligature',
  SMILE + ' smile', DESERET + ' deseret', '1 thing', '\tx', NBSP + 'x' + NBSP, NEL + 'x', BOM + 'x' + BOM, 'x' + LS, MONGOLIAN + 'x', ZWSP + 'x',
  'ends.' + NEL, 'x\r\n',
].map((text) => ({ text, sentence: E.asSentence(text) }))

const KEEPING = [
  [['intro.flac', '02 my song.flac'], "intro.flac couldn't be read as audio"],
  [['intro.flac', '02 my song.flac'], '02 my song.flac is in this edit twice.'],
  [['intro.flac', '02 my song.flac'], "title can't be edited here"],
  [['intro.flac', '02 my song.flac'], 'intro.flac could not be written: denied'],
  [['intro.flac'], '  intro.flac broke  '],
  [['', 'x'], 'y broke'],
  [[''], 'y broke'],
  [[E_ACUTE + 'tude.flac'], E_COMBINING + "tude.flac couldn't be read"],
  [[E_ACUTE + 'tude.flac'], E_ACUTE + "tude.flac couldn't be read"],
  [['a.flac'], 'a.flac'],
].map(([names, text]) => ({ names, text, sentence: E.asSentenceKeeping(names)(text) }))

const SAID = [
  ['it broke', 'Try again.'], ['', 'Try again.'], ['it broke', ''], ['', ''], ['ends.', 'x'], ['ends' + ELLIPSIS, 'x'], ['ends?', 'x'],
  ['ends. ', 'x'], ['ends;', 'x'],
].map(([text, advice]) => ({ text, advice, said: E.said({ text, advice }) }))

const SAFE = [
  [null, 'Fallback.'], ['', 'Fallback.'], ['   ', 'Fallback.'], ['fine words', 'Fallback.'], ['DB_PATH bad', 'Fallback.'],
  [' padded ', 'Fallback.'], [' at http://x ', 'Fallback.'],
].map(([text, fallback]) => {
  const safe = E.safeWords(text, fallback)
  return { text, fallback, result: safe.text, detail: safe.detail }
})

const JOBS = [
  ...Object.keys(E.JOB_ERRORS),
  '2 file(s) failed to organize', '1 file(s) failed to organize', '007 file(s) failed to organize', '0 file(s) failed to organize',
  '1 file(s) failed to organize, no track was filed', 'already in the store: all 10 track(s) were already there, nothing was filed',
  'all 3 file(s) already existed, nothing was filed', "organize failed: [Errno 13] Permission denied: '/music/Portishead/Dummy (1994)/01.flac'",
  'organize failed: [Errno 28] No space left on device', 'organize failed:x',
  ...Object.keys(E.JOB_ERRORS).slice(0, 5).map((reason) => `${reason} (3 of 10 file(s) arrived)`),
  'the peer refused to send it (1 of 1 file(s) arrived)', 'the peer refused to send it (0 of 01 file(s) arrived)',
  'something odd happened (2 of 3 file(s) arrived)', 'DB_PATH broke (2 of 3 file(s) arrived)', 'line\none (1 of 2 file(s) arrived)',
  'x (1 of 2 file(s) arrived)\n', ' the transfer failed ', '', null, '   ', 'Something the server said, plainly', 'x file(s) failed to organize',
  ' (1 of 2 file(s) arrived)', 'a (1 of 2 file(s) arrived) ', 'the transfer failed (1 of 2 file(s) arrived)' + NEL,
].map((error) => {
  const words = E.jobErrorWords(error)
  return { error, text: words.text, tell: words.tell, detail: words.detail }
})

const PINGS = []
for (const service of ['musicbrainz', 'slskd']) {
  for (const code of [null, undefined, 'CONNECTION_ERROR', '401', 502, 'WEIRD', '404', 'VALUE_ERROR', 'CONNECTING', 429]) {
    for (const error of [null, '', 'slskd answered 500']) {
      const words = E.pingWords(service, code, error)
      PINGS.push({ service, code: code === undefined || code === null ? null : String(code), error, text: words.text, line: words.line })
    }
  }
}

const REASONS = [null, '', '  ', 'Sign in to use deadwax.', ' Sign in to use deadwax. ', ' Navidrome no longer accepts it ', 'Sign in to use deadwax',
  NBSP + 'Your session has ended.' + LS].map((detail) => ({ detail, shown: S.reasonShown(detail) }))

const AFTER = [[null, 'james'], ['james', 'james'], ['james', 'ethan'], [E_ACUTE, E_COMBINING], ['', '']]
  .map(([before, now]) => ({ before, now, result: S.afterSignIn(before, now) }))

/* ===== what pages and the player say beside them, read out of their sources ======================== */

function read(file) {
  return fs.readFileSync(path.join(REPO, file), 'utf8')
}

/** An exported string constant's value, from its one line of source. */
function constant(file, name) {
  const line = read(file).split('\n').find((one) => one.startsWith(`export const ${name} = `))
  if (!line) throw new Error(`${file} has no ${name}`)
  const literal = line.slice(`export const ${name} = `.length).trim()
  if (literal.startsWith('"')) return JSON.parse(literal)
  if (literal.startsWith("'") && literal.endsWith("'")) return literal.slice(1, -1).split("\\'").join("'")
  throw new Error(`${file} ${name} isn't a plain string`)
}

/** A function's body in a source file: from its line to the first line that is only a closing brace. */
function body(file, name) {
  const lines = read(file).split('\n')
  const start = lines.findIndex((line) => line.startsWith(`function ${name}(`))
  if (start < 0) throw new Error(`${file} has no ${name}`)
  const end = lines.findIndex((line, index) => index > start && line === '}')
  return lines.slice(start, end + 1).join('\n')
}

const describeMedia = body('ui/src/player/usePlayer.ts', 'describeMediaError')
const quoted = (text) => (text.startsWith('"') ? JSON.parse(text) : text.slice(1, -1).split("\\'").join("'"))
const media = [...describeMedia.matchAll(/case (\d+):[^\n]*\n\s*return ("[^"]*"|'[^']*')/g)].map((m) => ({ code: Number(m[1]), words: quoted(m[2]) }))
const fallback = /default:\s*return ("[^"]*"|'[^']*')/.exec(describeMedia)
media.push({ code: null, words: quoted(fallback[1]) })
const skip = body('ui/src/player/usePlayer.ts', 'skipNotice')
const templates = [...skip.matchAll(/`([^`]*)`/g)].map((m) => m[1])
if (!/error\?\.code === MEDIA_ERR_DECODE/.test(skip) || templates.length !== 2) throw new Error('skipNotice changed shape - read it again')
const decodeCode = Number(/export const MEDIA_ERR_DECODE = (\d+)/.exec(read('ui/src/lib/playQueue.ts'))[1])

/* ===== written ==================================================================================== */

const fixture = {
  made_by: 'ios/scripts/export-error-words.cjs - never edit by hand: run it again',
  made_from: ['ui/src/lib/errorWords.ts', 'ui/src/lib/signIn.ts', 'ui/src/api/http.ts', 'ui/src/player/usePlayer.ts', 'ui/src/lib/playQueue.ts',
    'ui/src/player/AlbumPage.tsx', 'ui/src/app/ArtistPage.tsx', 'ui/src/app/LibrarySection.tsx'],
  constants: {
    TELL: E.TELL, OFFLINE: E.OFFLINE, OFFLINE_ADVICE: E.OFFLINE_ADVICE, OFFLINE_RETRY: E.OFFLINE_RETRY, TIMEOUT: E.TIMEOUT,
    SIGNED_OUT: E.SIGNED_OUT, NOT_ALLOWED: E.NOT_ALLOWED, GONE: E.GONE, OTHER: E.OTHER, PING_UNANSWERED: E.PING_UNANSWERED,
    PLAIN_SIGN_IN: S.PLAIN_SIGN_IN, UNREACHED: S.UNREACHED, SERVER_FAILED: S.SERVER_FAILED, FOR_WHOEVER: S.FOR_WHOEVER,
    BREAK_GLASS_USER: S.BREAK_GLASS_USER,
  },
  down: E.DOWN,
  job_errors: Object.entries(E.JOB_ERRORS).map(([reason, words]) => ({ reason, text: words.text, tell: words.tell === true })),
  ping_status: E.PING_STATUS,
  musicbrainz_lines: E.MUSICBRAINZ_LINES,
  page: {
    ALBUM_GONE: constant('ui/src/player/AlbumPage.tsx', 'ALBUM_GONE'),
    ARTIST_GONE: constant('ui/src/app/ArtistPage.tsx', 'ARTIST_GONE'),
    COULDNT_REFRESH: constant('ui/src/app/LibrarySection.tsx', 'COULDNT_REFRESH'),
  },
  media,
  options: OPTIONS,
  skipped: { decode_code: decodeCode, decode: templates[0], other: templates[1] },
  errors,
  plumbing: PLUMBING,
  as_sentence: SENTENCES,
  as_sentence_keeping: KEEPING,
  said: SAID,
  safe_words: SAFE,
  job_error_words: JOBS,
  ping_words: PINGS,
  reason_shown: REASONS,
  after_sign_in: AFTER,
}

/** JSON with each case on a line of its own, and every character outside ASCII as an escape. */
function written(value) {
  const parts = Object.entries(value).map(([key, part]) => {
    const inner = Array.isArray(part) ? `[\n${part.map((one) => '  ' + JSON.stringify(one)).join(',\n')}\n ]` : JSON.stringify(part)
    return ` ${JSON.stringify(key)}: ${inner}`
  })
  const text = `{\n${parts.join(',\n')}\n}\n`
  const backslash = String.fromCharCode(92)
  let out = ''
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i)
    out += code > 126 ? backslash + 'u' + code.toString(16).padStart(4, '0') : text[i]
  }
  return out
}

const text = written(fixture)
if (CHECK) {
  const kept = fs.existsSync(FIXTURE) ? fs.readFileSync(FIXTURE, 'utf8') : ''
  if (kept !== text) {
    console.error(`${path.relative(REPO, FIXTURE)} isn't what the TypeScript says now: run node ios/scripts/export-error-words.cjs, `
      + 'and make DeadwaxCore\'s ErrorWords.swift say the same (its tests replay the fixture).')
    process.exit(1)
  }
  console.log(`error words: ${errors.length} errors in ${OPTIONS.length} ways, ${PLUMBING.length} plumbing, ${JOBS.length} job reasons - the fixture is current`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, text)
  console.log(`wrote ${path.relative(REPO, FIXTURE)}: ${errors.length} errors in ${OPTIONS.length} ways`)
}
