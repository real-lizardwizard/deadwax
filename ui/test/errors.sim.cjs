/**
 * Errors and connections in a listener's words (2.0.4, UX batch 1): lib/errorWords.ts - the classes and their
 * sentences - and what draws through it: app/ErrorNote.tsx's lines, app/sayError.ts's one-line words, the sign-in's
 * (lib/signIn.ts), the Navidrome gate (app/NeedsNavidrome.tsx) and a download's reasons (lib/requestsView.ts) -
 * compiled with the repo's TypeScript and run with a small stand-in for Preact (JSX as plain objects).
 *
 * What it pins:
 *
 *  - THE CLASSES: fetch's own failure in every browser's words is offline; 408/504 a timeout; a 502/503 with no
 *    words fit for anyone unreachable, said by whose answer it was (the route: the Navidrome routes the music
 *    server's, the downloads' and slskd's the downloads', anything else deadwax's); 404 not found (the caller's
 *    sentence, else deadwax's words, never FastAPI's bare "Not Found"); 401/403 not allowed; a 4xx - or deadwax's
 *    own 5xx - in words fit for anyone refused, its words as written; deadwax's split answer (src/auth.py Explained)
 *    refused, its `why` the detail; anything else other. Each class's sentence and what to do.
 *  - WHO READS IT: a listener never gets the error's own words, and is told to tell whoever runs deadwax where only
 *    they can fix it; whoever runs deadwax gets the error's own words as the detail, and is never told to tell
 *    themselves.
 *  - THE SCAN: every raw error deadwax and the browser are known to produce - a traceback's last line out of slskd,
 *    Navidrome's address, a setting's name, an errno, http.ts's "GET /x failed", fetch's words - put through every
 *    way the app says an error, for a listener: no line holds plumbing, nor the raw words.
 *  - A DOWNLOAD'S REASONS: every string the server writes into a job's `error` - read out of src/store.py,
 *    src/poller.py and src/routes/download.py, so a new one trips this - has a sentence of its own, none of them
 *    plumbing; the job's own words kept as the detail.
 *  - THE PAGES: the listener files hold no catch that keeps an error's raw words (`x instanceof Error ? x.message`,
 *    `String(caught)`) outside a console line; the Navidrome gate tells a listener what is wrong without Navidrome's
 *    address or a setting, with no Set up Navidrome; an admin keeps them.
 *
 * Run it with:  node ui/test/errors.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const SRC = path.join(UI, 'src')
const REPO = path.resolve(UI, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-errors-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/errorWords.ts', 'src/lib/signIn.ts', 'src/app/ErrorNote.tsx', 'src/app/sayError.ts', 'src/app/NeedsNavidrome.tsx',
  'src/lib/requestsView.ts', 'src/app/access.ts', 'src/lib/navidromeCheck.ts',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
exports.useState = (v) => [typeof v === 'function' ? v() : v, () => {}]
exports.useEffect = () => {}
`)

const E = require(path.join(OUT, 'lib/errorWords.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))
const SignIn = require(path.join(OUT, 'lib/signIn.js'))
const Note = require(path.join(OUT, 'app/ErrorNote.js'))
const { sayError } = require(path.join(OUT, 'app/sayError.js'))
const Gate = require(path.join(OUT, 'app/NeedsNavidrome.js'))
const V = require(path.join(OUT, 'lib/requestsView.js'))
const Access = require(path.join(OUT, 'app/access.js'))
const NC = require(path.join(OUT, 'lib/navidromeCheck.js'))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
function text(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(text).join('')
  return text(node.props?.children)
}
function find(test, node, hits = []) {
  if (!node || typeof node !== 'object') return hits
  if (Array.isArray(node)) { node.forEach((one) => find(test, one, hits)); return hits }
  if (test(node)) hits.push(node)
  find(test, node.props?.children, hits)
  return hits
}

//? an answer as api/http.ts throws it: its status, deadwax's words, the route, and deadwax's split `why`
const answer = (status, detail, route = '/library/x', why = null) => new ApiError(status, detail, `GET ${route} failed`, false, null, why, route)
const LISTENER = { admin: false }
const ADMIN = { admin: true }
const KEEPS = 'if it keeps happening, tell whoever runs deadwax.'

console.log('\nthe classes')
{
  const kinds = [
    ['Chrome, offline', new TypeError('Failed to fetch')],
    ['Safari, offline', new TypeError('Load failed')],
    ['Firefox, offline', new TypeError('NetworkError when attempting to fetch resource.')],
    ['a 504', answer(504, null)],
    ['a 408', answer(408, null)],
    ['a TimeoutError', Object.assign(new Error('signal timed out'), { name: 'TimeoutError' })],
    ['Navidrome unreached', answer(502, "Navidrome couldn't be reached at http://navidrome:4533: All connection attempts failed", '/navidrome/artists')],
    ['Navidrome not set up', answer(503, "Navidrome isn't set up - fill in NAVIDROME_URL, NAVIDROME_USER and NAVIDROME_PASSWORD in Server settings (Connections)", '/navidrome/albums')],
    ['a 404', answer(404, 'Not Found')],
    ['a 401', answer(401, 'Sign in to use deadwax.')],
    ['a 403', answer(403, "That needs Edit albums, which an admin hasn't given you. You're signed in as ethan.")],
    ['a 409 in words', answer(409, 'Home holds up to 50 pins - unpin one first', '/me/pins')],
    ['a 503 in deadwax\'s words', answer(503, "deadwax can't keep pins: its database isn't writable", '/me/pins')],
    ['deadwax\'s split answer', answer(503, "deadwax can't read its database just now, so it can't check who you are.", '/me', 'Check DB_PATH points at a writable volume.')],
    ['a 500', answer(500, "Error searching slskd: HTTPConnectionPool(host='127.0.0.1', port=5030): Max retries exceeded", '/download/find_candidates')],
    ['a 422 with plumbing', answer(422, 'LIBRARY_PATH: not a folder')],
    ['the page\'s own error', new SyntaxError('Unexpected token < in JSON at position 0')],
    ['a TypeError of the page\'s own', new TypeError("Cannot read properties of undefined (reading 'id')")],
  ]
  check('each one\'s class', kinds.map(([label, error]) => [label, E.errorKind(error)]), [
    ['Chrome, offline', 'offline'], ['Safari, offline', 'offline'], ['Firefox, offline', 'offline'],
    ['a 504', 'timeout'], ['a 408', 'timeout'], ['a TimeoutError', 'timeout'],
    ['Navidrome unreached', 'unreachable'], ['Navidrome not set up', 'unreachable'],
    ['a 404', 'not-found'], ['a 401', 'not-allowed'], ['a 403', 'not-allowed'],
    ['a 409 in words', 'refused'], ['a 503 in deadwax\'s words', 'refused'], ['deadwax\'s split answer', 'refused'],
    ['a 500', 'other'], ['a 422 with plumbing', 'other'], ['the page\'s own error', 'other'], ['a TypeError of the page\'s own', 'other'],
  ])
  check('whose answer: the route', [E.serviceOf(answer(502, null, '/navidrome/x')), E.serviceOf(answer(502, null, '/download/jobs')), E.serviceOf(answer(502, null, '/monitor_slskd/ping')),
    E.serviceOf(answer(502, null, '/me/pins')), E.serviceOf(new TypeError('Failed to fetch'))], ['music', 'downloads', 'downloads', 'deadwax', 'deadwax'])

  const words = (error, options) => E.errorWords(error, options)
  check('offline: can\'t connect, and to check the connection - for anyone', [words(new TypeError('Load failed'), LISTENER), words(new TypeError('Load failed'), ADMIN)],
    [{ kind: 'offline', text: "Can't connect to deadwax.", advice: 'Check your connection, then try again.', detail: null },
      { kind: 'offline', text: "Can't connect to deadwax.", advice: 'Check your connection, then try again.', detail: 'Load failed' }])
  check('a timeout', E.said(words(answer(504, null), LISTENER)), 'That took too long. Try again.')
  const unreached = answer(502, "Navidrome couldn't be reached at http://navidrome:4533: All connection attempts failed", '/navidrome/artists')
  check('unreachable, the music server\'s: a listener told to try in a minute, and to tell if it keeps on', words(unreached, LISTENER),
    { kind: 'unreachable', text: "Can't reach the music server right now.", advice: `Try again in a minute - ${KEEPS}`, detail: null })
  check('...whoever runs deadwax: Navidrome\'s own words as the detail, never told to tell themselves', words(unreached, ADMIN),
    { kind: 'unreachable', text: "Can't reach the music server right now.", advice: 'Try again in a minute.', detail: "Navidrome couldn't be reached at http://navidrome:4533: All connection attempts failed" })
  check('...the downloads\', and deadwax\'s', [words(answer(502, "slskd isn't logged in to Soulseek", '/download/find_candidates'), LISTENER).text, words(answer(503, null, '/me'), LISTENER).text],
    ["Downloads aren't working right now.", "deadwax can't do that right now."])
  check('...a caller\'s own sentence for what didn\'t work', words(answer(502, 'slskd refused the download (500)', '/download/enqueue'), { failed: "The download couldn't be started." }).text,
    "The download couldn't be started.")
  check('not found: the caller\'s sentence, else deadwax\'s words, else ours - never "Not Found"',
    [words(answer(404, 'Navidrome has nothing by that id', '/navidrome/albums/x'), { gone: 'This album isn\'t here any more.' }).text,
      words(answer(404, "That playlist isn't on Navidrome any more - deleted in another app, maybe.", '/navidrome/playlists/x')).text, words(answer(404, 'Not Found')).text],
    ["This album isn't here any more.", "That playlist isn't on Navidrome any more - deleted in another app, maybe.", "It isn't there any more."])
  check('not allowed: a 401 is a sign-in ended; a 403 deadwax\'s words, or ours for plumbing',
    [words(answer(401, 'x')).text, words(answer(403, "That needs Edit albums, which an admin hasn't given you.")).text, words(answer(403, 'DEADWAX_ADMINS')).text],
    ["Your sign-in has ended - sign in again.", "That needs Edit albums, which an admin hasn't given you.", "You don't have permission for that."])
  check('refused: deadwax\'s words as written - a name in them never re-cased', words(answer(409, 'reel2reel refused', '/download/retry')).text, 'reel2reel refused')
  check('...deadwax\'s own 5xx in words: to a listener, to tell if it keeps on; to whoever runs it, nothing more',
    [E.said(words(answer(503, "deadwax can't keep pins: its database isn't writable", '/me/pins'), LISTENER)), E.said(words(answer(503, "deadwax can't keep pins: its database isn't writable", '/me/pins'), ADMIN))],
    ["deadwax can't keep pins: its database isn't writable. If it keeps happening, tell whoever runs deadwax.", "deadwax can't keep pins: its database isn't writable"])
  const split = answer(503, "deadwax can't read its database just now, so it can't check who you are.", '/me', 'deadwax can\'t read its database, so nothing is let in until it can. Check DB_PATH points at a writable volume.')
  check('deadwax\'s split 503: a listener its sentence and to tell whoever runs deadwax; they its why', [E.said(words(split, LISTENER)), words(split, ADMIN).detail],
    ["deadwax can't read its database just now, so it can't check who you are. Tell whoever runs deadwax.", "deadwax can't read its database, so nothing is let in until it can. Check DB_PATH points at a writable volume."])
  check('...a split 502 (the songs saved, the rest not): its sentence, nothing to tell', E.said(words(answer(502, "The songs were saved, but Navidrome didn't take the name, description or sharing.", '/navidrome/playlists/x', 'Navidrome said: locked'), LISTENER)),
    "The songs were saved, but Navidrome didn't take the name, description or sharing.")
  check('other: something went wrong, try again - and to tell if it keeps on', [E.said(words(new SyntaxError('Unexpected token <'), LISTENER)), E.said(words(new SyntaxError('Unexpected token <'), ADMIN))],
    [`Something went wrong. Try again - ${KEEPS}`, 'Something went wrong. Try again.'])
  check('a sentence and its advice joined with a full stop where the words left none', E.said({ text: 'it broke', advice: 'Try again.' }), 'it broke. Try again.')
  check('deadwax and slskd never capitalised at a sentence\'s start', [E.asSentence('deadwax broke'), E.asSentence('slskd broke'), E.asSentence('it broke')], ['deadwax broke.', 'slskd broke.', 'It broke.'])
  check('one line for a store: lead, sentence, advice - and the detail in brackets for whoever runs deadwax',
    [E.noticeWords("Couldn't get your pins.", new TypeError('Failed to fetch'), LISTENER), E.noticeWords("Couldn't get your pins.", new TypeError('Failed to fetch'), ADMIN)],
    ["Couldn't get your pins. Can't connect to deadwax. Check your connection, then try again.",
      "Couldn't get your pins. Can't connect to deadwax. Check your connection, then try again. (Failed to fetch)"])

  //? (review) a refusal deadwax named a kind of (People's, Change password's Refused: {detail, kind}) is its own words
  //? whatever its status - a timeout or a 500 among them, whose words say what to do when "Try again" would be wrong
  const named = (status, detail, kind) => new ApiError(status, detail, 'POST /me/password failed', false, kind, null, '/me/password')
  const TIMED_OUT = "Navidrome didn't answer in time, so deadwax can't tell whether your password changed. If it did, deadwax asks you to sign in again within a few minutes - with the new one; if not, try again."
  const NOT_KEPT = "Navidrome changed your password, but deadwax couldn't keep the new one - sign out and sign in again with the new password."
  check('a named refusal: its own words, whatever its status - never "That took too long" or "Something went wrong"',
    [E.errorKind(named(504, TIMED_OUT, 'timed_out')), E.errorWords(named(504, TIMED_OUT, 'timed_out'), LISTENER).text,
      E.errorWords(named(500, NOT_KEPT, 'not_kept'), LISTENER).text, E.errorKind(named(409, 'Navidrome says that isn\'t your current password - nothing changed.', 'wrong_current'))],
    ['refused', TIMED_OUT, NOT_KEPT, 'refused'])
  check('...but not when its words hold plumbing, nor for a 401 (the sign-in comes up over it)',
    [E.errorKind(named(502, "Navidrome answered in a way deadwax doesn't know (RemoteProtocolError)", 'unknown_shape')), E.errorKind(named(401, 'x', 'gone'))],
    ['unreachable', 'not-allowed'])

  //? (review) beside a Try again the page draws itself: the advice leaves trying again to it - said once
  const retry = (error, options = LISTENER) => E.said(E.errorWords(error, { ...options, retry: true }))
  check('retry: no "try again" in the advice, the tell kept for a listener', [
    retry(new TypeError('Load failed')), retry(answer(504, null)), retry(unreached), retry(unreached, ADMIN),
    retry(new SyntaxError('x')), retry(new SyntaxError('x'), ADMIN), retry(answer(409, 'Home holds up to 50 pins - unpin one first', '/me/pins')),
  ], [
    "Can't connect to deadwax. Check your connection.", 'That took too long.', `Can't reach the music server right now. If it keeps happening, tell whoever runs deadwax.`,
    "Can't reach the music server right now.", 'Something went wrong. If it keeps happening, tell whoever runs deadwax.', 'Something went wrong.',
    'Home holds up to 50 pins - unpin one first',
  ])
}

console.log('\nwho reads it: an admin, or someone with Settings and the log, gets the detail (app/access.ts seesDetail)')
{
  check('an admin, Settings and the log, anyone else', [Access.seesDetail({ admin: true, permissions: new Set() }), Access.seesDetail({ admin: false, permissions: new Set(['server']) }),
    Access.seesDetail({ admin: false, permissions: new Set(['request', 'edit', 'library']) })], [true, true, false])
  Access.noteAccess({ auth: 'on', user: 'ethan', admin: false, permissions: ['request'] })
  const listenerLine = Note.errorNote(answer(500, "Error searching slskd: HTTPConnectionPool(host='127.0.0.1', port=5030)", '/download/find_candidates'), { class: 'x' })
  check('errorNote, a listener: the sentence alone, in the page\'s own <p>', [listenerLine.type, listenerLine.props.class, text(listenerLine), find((n) => n.props?.class === 'app-error-detail', listenerLine).length],
    ['p', 'x', `Something went wrong. Try again - ${KEEPS}`, 0])
  check('sayError, a listener: no brackets', sayError(new TypeError('Failed to fetch'), 'Not saved.'), "Not saved. Can't connect to deadwax. Check your connection, then try again.")
  Access.noteAccess({ auth: 'on', user: 'sam', admin: false, permissions: ['request', 'server'] })
  const runsLine = Note.errorNote(answer(500, "Error searching slskd: HTTPConnectionPool(host='127.0.0.1', port=5030)", '/download/find_candidates'), { as: 'span' })
  check('...someone with Settings and the log: the detail under it, smaller', [runsLine.type, find((n) => n.props?.class === 'app-error-detail', runsLine).map(text)],
    ['span', ["Error searching slskd: HTTPConnectionPool(host='127.0.0.1', port=5030)"]])
  check('errorLine: words worked out elsewhere, the detail only when there is one', [text(Note.errorLine('Cancelled.', null)), find((n) => n.props?.class === 'app-error-detail', Note.errorLine('a', 'b')).length],
    ['Cancelled.', 1])
  Access.forgetAccess()
}

//? every raw error the app is known to meet, as the browser and deadwax produce them
const RAW = [
  new TypeError('Failed to fetch'),
  new TypeError('Load failed'),
  answer(500, "Error searching slskd: HTTPConnectionPool(host='127.0.0.1', port=4559): Max retries exceeded with url: /api/v0/searches (Caused by NewConnectionError('<urllib3.connection.HTTPConnection object at 0x7f>: Failed to establish a new connection: [Errno 111] Connection refused'))", '/download/find_candidates'),
  answer(502, "slskd is not connected to the Soulseek network, so it cannot search", '/download/find_candidates'),
  answer(502, "couldn't reach slskd to queue it: HTTPConnectionPool(host='slskd', port=5030)", '/download/enqueue'),
  answer(502, "Navidrome couldn't be reached at http://127.0.0.1:4558: All connection attempts failed", '/navidrome/albums'),
  answer(503, "Navidrome isn't set up - fill in NAVIDROME_URL, NAVIDROME_USER and NAVIDROME_PASSWORD in Server settings (Connections)", '/navidrome/albums'),
  answer(502, "the answer wasn't a Subsonic one - is NAVIDROME_URL the address of Navidrome itself?", '/navidrome/albums'),
  answer(502, 'Navidrome refused the login - check NAVIDROME_USER and NAVIDROME_PASSWORD', '/navidrome/albums'),
  answer(502, 'Navidrome said: database is locked', '/navidrome/albums'),
  answer(502, 'Navidrome answered 500', '/navidrome/albums'),
  answer(500, "Error queueing download: [Errno 13] Permission denied: '/downloads/x'", '/download/enqueue'),
  answer(503, "NAVIDROME_URL is unusable (it has a user name or password in it), so deadwax sends nothing to it - fix it in Server settings (Connections), or in your compose file", '/navidrome/x'),
  answer(503, 'Logins are on, but DEADWAX_SECRET_KEY isn\'t set, so deadwax can\'t sign anyone in.', '/me'),
  answer(422, 'SLSKD_URL: has no scheme'),
  answer(404, 'Not Found'),
  answer(500, null),
  answer(502, null),
  new SyntaxError('Unexpected token < in JSON at position 0'),
  new Error('GET /navidrome/albums failed'),
]
const rawOf = (error) => (error instanceof ApiError ? error.detail || error.message : error.message)

console.log('\nthe scan: no listener line holds plumbing or the raw words')
{
  const ways = [
    ['errorWords', (error) => E.said(E.errorWords(error, LISTENER))],
    ['...as the music server\'s', (error) => E.said(E.errorWords(error, { ...LISTENER, service: 'music' }))],
    ['...as the downloads\'', (error) => E.said(E.errorWords(error, { ...LISTENER, service: 'downloads', failed: "The download couldn't be started." }))],
    ['...with a gone', (error) => E.said(E.errorWords(error, { ...LISTENER, gone: "This album isn't here any more." }))],
    ['noticeWords', (error) => E.noticeWords('Not saved.', error, LISTENER)],
    ['the sign-in screen', (error) => SignIn.signInProblem(error)],
  ]
  const leaks = []
  for (const [way, say] of ways) {
    for (const error of RAW) {
      const line = say(error)
      const raw = rawOf(error)
      //? fetch's own words are left out too; the bare "Not Found" is ours to replace
      if (E.plumbing(line) || (raw && raw.length > 12 && line.includes(raw)) || /Failed to fetch|Load failed/.test(line)) leaks.push([way, raw, line])
    }
  }
  check('every raw error, every way it is said, for a listener: nothing leaks', leaks, [])
  check('...and the detail is null for a listener every time', RAW.filter((error) => E.errorWords(error, LISTENER).detail !== null).length, 0)
  check('...whoever runs deadwax gets the raw words every time they differ', RAW.filter((error) => {
    const words = E.errorWords(error, ADMIN)
    return words.detail === null && E.rawWords(error) !== words.text
  }).map(rawOf), [])
  check('plumbing knows each kind: a setting, an address, an exception, an errno, a path, slskd, http.ts\'s fallback, a status',
    ['DB_PATH points', 'at http://x', 'a ConnectError', '[Errno 2]', "file '/music/a/b'", 'slskd is down', 'GET /me failed', 'answered 502', 'Navidrome said: no',
      'That playlist changed in another app', "deadwax can't keep pins: its database isn't writable"].map(E.plumbing),
    [true, true, true, true, true, true, true, true, true, false, false])
}

console.log('\na download\'s reasons: every one the server writes, in a listener\'s words')
{
  const read = (file) => fs.readFileSync(path.join(REPO, file), 'utf8')
  const store = read('src/store.py'), poller = read('src/poller.py'), download = read('src/routes/download.py')
  const block = /TRANSFER_FAILURE_REASONS = \{([\s\S]*?)\n\}/.exec(store)[1]
  const transfer = [...block.matchAll(/"[A-Za-z]+":\s*"([^"]+)"/g)].map((m) => m[1])
  const constant = (name) => new RegExp(`^${name} = "(.+)"$`, 'm').exec(poller)?.[1]
  const literals = [
    ...[...poller.matchAll(/_fail\(slskd_client, store, job, "([^"]+)"\)/g)].map((m) => m[1]),
    ...[...poller.matchAll(/update_status\([^)]*?"(?:complete|failed|cancelled)", "([^"]+)"\)/g)].map((m) => m[1]),
    ...[...download.matchAll(/update_status\([^)]*?"(?:complete|failed|cancelled)", "([^"]+)"\)/g)].map((m) => m[1]),
    /failure_reason"\) or "([^"]+)"/.exec(poller)[1],
  ]
  check('the names the formatted ones are made of are still what this sim builds them from',
    [constant('FAILED_TO_ORGANIZE'), constant('NO_TRACK_FILED'), constant('ALREADY_THERE'), constant('NOTHING_FILED'), constant('ORGANIZE_FAILED')],
    ['file(s) failed to organize', 'no track was filed', 'already in the store', 'nothing was filed', 'organize failed:'])
  const every = [
    ...transfer, ...literals, constant('NOTHING_ORGANIZED'), constant('INTERRUPTED_FILING'),
    '2 file(s) failed to organize', '1 file(s) failed to organize, no track was filed',
    'already in the store: all 10 track(s) were already there, nothing was filed', 'all 3 file(s) already existed, nothing was filed',
    "organize failed: [Errno 13] Permission denied: '/music/Portishead/Dummy (1994)/01.flac'",
    ...transfer.map((reason) => `${reason} (3 of 10 file(s) arrived)`),
  ]
  check('the server writes these (read out of the Python)', [transfer.length >= 4, literals.length >= 4, every.every(Boolean)], [true, true, true])
  const said = every.map((raw) => [raw, V.retryProblemWords && E.jobErrorWords(raw)])
  check('...each has a sentence of its own - never its raw words, never plumbing', said.filter(([raw, words]) => words.text === raw || E.plumbing(words.text) || !words.text).map(([raw]) => raw), [])
  check('...and keeps its own words for whoever runs deadwax', said.filter(([raw, words]) => words.detail !== raw).map(([raw]) => raw), [])
  check('the words themselves', [
    E.jobErrorWords('the peer refused to send it').text, E.jobErrorWords('the peer stopped responding (3 of 10 file(s) arrived)').text,
    E.jobErrorWords('no transfers reported by slskd').text, E.jobErrorWords('nothing could be organized, check SLSKD_DOWNLOAD_PATH'),
    E.jobErrorWords("organize failed: [Errno 28] No space left on device").text, E.jobErrorWords('1 file(s) failed to organize').text,
  ], [
    'The person sharing it refused to send it.', 'The person sharing it stopped responding. 3 of 10 files arrived.',
    'deadwax lost track of this download - the person sharing it may have gone offline, or downloads stopped working for a while.',
    { text: "It downloaded, but deadwax couldn't find its files to add them to your library.", tell: true, detail: 'nothing could be organized, check SLSKD_DOWNLOAD_PATH' },
    "It downloaded, but couldn't be added to your library.", "1 file couldn't be added to your library.",
  ])
  //? (review) every one pinned whole - its words and whether a listener is told to tell whoever runs deadwax - so a
  //? change to either trips here, and troubleshooting.md (which quotes each) is updated with it
  const NOT_RUN = "deadwax lost track of this download - the person sharing it may have gone offline, or downloads stopped working for a while."
  check('the whole table: each reason\'s words and its tell', Object.fromEntries(Object.entries(E.JOB_ERRORS).map(([raw, words]) => [raw, [words.text, words.tell === true]])), {
    'the peer refused to send it': ['The person sharing it refused to send it.', false],
    'the peer stopped responding': ['The person sharing it stopped responding.', false],
    'the transfer errored': ['The download broke off.', false],
    'the transfer was cancelled': ['The download was cancelled before it finished.', false],
    'the transfer failed': ["The download didn't finish.", false],
    'no transfers reported by slskd': [NOT_RUN, false],
    'cancelled from deadwax': ['Cancelled.', false],
    'dry run - not organized': ['Downloaded, but not added to your library: deadwax is set to try filing without moving anything.', true],
    'nothing could be organized, check SLSKD_DOWNLOAD_PATH': ["It downloaded, but deadwax couldn't find its files to add them to your library.", true],
    "deadwax stopped while filing this - check the library and slskd's folder": ['deadwax stopped while it was adding this to your library.', true],
  })
  check('...the table holds every fixed string the server writes, and nothing it doesn\'t', [...new Set(every.filter((raw) => !/\d/.test(raw)).filter((raw) => !raw.startsWith('organize failed:')))].sort(),
    Object.keys(E.JOB_ERRORS).sort())
  const whole = (raw) => { const words = E.jobErrorWords(raw); return [words.text, words.tell] }
  check('...and the formatted ones, whole', [
    whole("organize failed: [Errno 28] No space left on device"), whole('2 file(s) failed to organize'), whole('1 file(s) failed to organize'),
    whole('3 file(s) failed to organize, no track was filed'), whole('all 3 file(s) already existed, nothing was filed'),
    whole('already in the store: all 10 track(s) were already there, nothing was filed'), whole('the peer stopped responding (1 of 1 file(s) arrived)'),
    whole("dry run - not organized (3 of 10 file(s) arrived)"), whole("couldn't reach slskd to queue it: HTTPConnectionPool(host='x')"),
  ], [
    ["It downloaded, but couldn't be added to your library.", true], ["2 files couldn't be added to your library.", true], ["1 file couldn't be added to your library.", true],
    ['It downloaded, but none of its songs could be added to your library.', true], ['Its files were already in the collection, so nothing was added.', false],
    ['Every song was already in the collection, so nothing was added.', false], ['The person sharing it stopped responding. 1 of 1 file arrived.', false],
    ['Downloaded, but not added to your library: deadwax is set to try filing without moving anything. 3 of 10 files arrived.', true], ["It stopped, and deadwax couldn't say why.", true],
  ])
  check('words the server writes that are fit to be read pass as written; plumbing never',
    [E.jobErrorWords('reel2reel went offline after 4 of 10 files').text, E.jobErrorWords("couldn't reach slskd to queue it: HTTPConnectionPool(host='x')").text],
    ['reel2reel went offline after 4 of 10 files', "It stopped, and deadwax couldn't say why."])
  check('a retry\'s problem: the route\'s words as written, slskd\'s in a listener\'s, plumbing replaced',
    [V.retryProblemWords('no other peers to try - search again for more'), V.retryProblemWords('slskd is still stopping the last attempt - try again in a moment'),
      V.retryProblemWords("slskd couldn't queue it: bob is offline"), V.retryProblemWords({ text: "That didn't work.", detail: 'x' })],
    [{ text: 'no other peers to try - search again for more', detail: null }, { text: 'The last try is still stopping - try again in a moment.', detail: 'slskd is still stopping the last attempt - try again in a moment' },
      { text: V.RETRY_FAILED, detail: "slskd couldn't queue it: bob is offline" }, { text: "That didn't work.", detail: 'x' }])
}

console.log('\nYou -> Connections: a word for each code, never the code; the sentence under it')
{
  check('slskd\'s: the server\'s sentence under a word',
    [E.pingWords('slskd', 'CONNECTION_ERROR', "deadwax can't reach slskd at its address - check slskd is running, and SLSKD_URL in Server settings (Connections)."),
      E.pingWords('slskd', 401, 'x'), E.pingWords('slskd', 'NOT_LOGGED_IN', 'slskd is not logged in'), E.pingWords('slskd', 'SOMETHING_NEW', null)],
    [{ text: "Can't reach it", line: "deadwax can't reach slskd at its address - check slskd is running, and SLSKD_URL in Server settings (Connections)." },
      { text: 'Key refused', line: 'x' }, { text: 'Not on Soulseek', line: 'slskd is not logged in' }, { text: 'Not connected', line: null }])
  check('MusicBrainz\'s: its sentence from here, never the log\'s line',
    [E.pingWords('musicbrainz', 'MAX_RETRIES_EXCEEDED', 'Failed to get valid response from MusicBrainz after retries'), E.pingWords('musicbrainz', 'VALUE_ERROR', 'x').line],
    [{ text: 'No answer', line: "MusicBrainz didn't answer after a few tries - it often goes away for a few minutes." }, 'No contact is set for MusicBrainz - set MUSICBRAINZ_EMAIL in Server settings (Connections).'])
  check('every code a ping answers with has a word: slskd\'s (src/api/slskd_endpoint.py) and MusicBrainz\'s', (() => {
    const slskd = fs.readFileSync(path.join(REPO, 'src/api/slskd_endpoint.py'), 'utf8')
    const mb = fs.readFileSync(path.join(REPO, 'src/api/musicbrainz_endpoint.py'), 'utf8')
    const both = slskd + mb
    const codes = new Set([...both.matchAll(/"code": (?:"([A-Z_]+)"|(\d+))/g), ...both.matchAll(/\["code"\] =\s*(?:"([A-Z_]+)"|(\d+))/g), ...slskd.matchAll(/code, note, advice = "([A-Z_]+)"|code = "([A-Z_]+)"/g)]
      .map((m) => m[1] ?? m[2]).filter(Boolean))
    codes.delete('connected')
    //? the sim reads enough of them to mean something
    return [codes.size >= 15, codes.has('MAX_RETRIES_EXCEEDED'), [...codes].filter((code) => !(code in E.PING_STATUS))]
  })(), [true, true, []])
}

//? (review) async from here: the Navidrome check answers on a later tick
;(async () => {
console.log('\nthe Navidrome gate')
{
  const DOWN = { ok: false, configured: true, problem: "Navidrome couldn't be reached at http://navidrome:4533: All connection attempts failed" }
  const UNSET = { ok: false, configured: false, problem: "Navidrome isn't set up - fill in NAVIDROME_URL, NAVIDROME_USER and NAVIDROME_PASSWORD in Server settings (Connections)" }
  const gate = (status) => Gate.NeedsNavidrome({ status, onRetry() {}, children: 'LIBRARY' })
  const say = (tree) => [text(find((n) => n.props?.class === 'app-needs-title', tree)[0]), find((n) => n.props?.class === 'app-needs-text', tree).map(text),
    find((n) => n.type === 'button', tree).map(text)]
  Access.noteAccess({ auth: 'on', user: 'ethan', admin: false, permissions: ['request'] })
  check('a listener, Navidrome down: their music unavailable, what to do, Try again - no address, no setting', say(gate(DOWN)),
    [Gate.MUSIC_UNAVAILABLE, [Gate.MUSIC_UNREACHED], ['Try again']])
  check('...not set up: not yet, and to tell whoever runs deadwax - no Set up Navidrome', say(gate(UNSET)), [Gate.MUSIC_NOT_YET, [Gate.MUSIC_UNSET], []])
  //? (review) deadwax ITSELF not answering the check (fetch's TypeError: off the network, the VPN off, deadwax restarting)
  //? isn't the music server: the listener is told to check their connection, never to tell whoever runs deadwax
  {
    let status = null
    const asks = NC.navidromeChecks(() => Promise.reject(new TypeError('Failed to fetch')), (next) => { status = next(status) })
    asks.check()
    await new Promise((resolve) => setTimeout(resolve, 0))
    check('...deadwax unreachable (the check\'s TypeError): their music unavailable, check your connection, Try again', say(gate(status)),
      [Gate.MUSIC_UNAVAILABLE, ["Can't connect to deadwax. Check your connection."], ['Try again']])
    let other = null
    const answered = NC.navidromeChecks(() => Promise.reject(answer(502, null, '/navidrome/status')), (next) => { other = next(other) })
    answered.check()
    await new Promise((resolve) => setTimeout(resolve, 0))
    check('...deadwax answered, Navidrome didn\'t: the music server\'s sentence still', [other.offline, say(gate(other))[1]], [undefined, [Gate.MUSIC_UNREACHED]])
  }
  check('...and none of it plumbing', [Gate.MUSIC_UNAVAILABLE, Gate.MUSIC_UNREACHED, Gate.MUSIC_NOT_YET, Gate.MUSIC_UNSET].filter(E.plumbing), [])
  Access.noteAccess({ auth: 'on', user: 'sam', admin: false, permissions: ['request', 'server'] })
  check('someone with Settings and the log: Navidrome\'s words, but no Set up Navidrome - its rows are an admin\'s', say(gate(UNSET)),
    ['Connect Navidrome', [UNSET.problem, `${Gate.NAVIDROME_REQUIRED} ${Gate.ADMIN_SETS_UP}`], []])
  Access.forgetAccess()
  check('an admin (logins off): Navidrome\'s own words, and Set up Navidrome', say(gate(UNSET)),
    ['Connect Navidrome', [UNSET.problem, `${Gate.NAVIDROME_REQUIRED} Set it up in deadwax's settings (Connections), then come back.`], ['Set up Navidrome']])
  check('...reached: what it guards', gate({ ok: true, configured: true, problem: null }).props.children, 'LIBRARY')
}

console.log('\nthe pages: no catch keeps an error\'s raw words for the screen')
{
  const LISTENER_FILES = [
    'app/App.tsx', 'app/Home.tsx', 'app/LibraryHome.tsx', 'app/LibrarySection.tsx', 'app/LibraryViews.tsx', 'app/usePaged.ts',
    'player/AlbumPage.tsx', 'app/ArtistPage.tsx', 'app/Search.tsx', 'app/ReleaseGroupPage.tsx', 'app/Sources.tsx',
    'hooks/useCandidateSearch.ts', 'app/Requests.tsx', 'app/JobCard.tsx', 'hooks/useDownloadJobs.ts', 'app/usePins.ts', 'app/Pinned.tsx',
    'app/usePlaylists.ts', 'app/PlaylistPage.tsx', 'app/PlaylistPicker.tsx', 'app/PlaylistsPage.tsx', 'app/NewPlaylistForm.tsx',
    'app/StoreState.tsx', 'app/YourLibrary.tsx', 'app/You.tsx', 'app/useGetSettings.ts', 'app/ChangePassword.tsx', 'app/NeedsNavidrome.tsx',
    'app/SignIn.tsx', 'app/signInGate.tsx', 'app/Arriving.tsx',
  ]
  //? (review) every way of putting a caught error's own words back on the screen: the instanceof test, String() of it,
  //? `(x as Error).message`, any `.message` of a caught/reason/error/e, and the error interpolated into a sentence
  const CAUGHT = '(?:reason|caught|error|err|e|failure|problem|refused)'
  const RAW_KEPT = new RegExp([
    String.raw`\b\w+ instanceof Error \? \w+\.message\b`,
    String.raw`String\(${CAUGHT}\)`,
    String.raw`as Error\)\.message\b`,
    String.raw`\b${CAUGHT}\??\.message\b`,
    String.raw`\$\{${CAUGHT}(?:\.message)?\}`,
  ].join('|'))
  check('the scan knows each way', ['x instanceof Error ? x.message : ""', 'String(caught)', '{(error as Error).message}', '{reason.message}', '{error?.message}',
    '`Couldn\'t pin ${name}: ${reason}`', '`${error}`', '{errorNote(error)}', "setProblem(sayError(reason))", '`${count} files`'].map((line) => RAW_KEPT.test(line)),
    [true, true, true, true, true, true, true, false, false, false])
  const kept = []
  for (const file of LISTENER_FILES) {
    fs.readFileSync(path.join(SRC, file), 'utf8').split('\n').forEach((line, at) => {
      if (RAW_KEPT.test(line) && !/console\./.test(line)) kept.push(`${file}:${at + 1}`)
    })
  }
  check('every listener page and store: errors said through lib/errorWords.ts, never their own words', kept, [])
  //? (review) a Done row that can't open, when deadwax itself didn't answer the check: not the music server's sentence
  const app = fs.readFileSync(path.join(SRC, 'app/App.tsx'), 'utf8')
  check('App: a Done row\'s can\'t-open line says deadwax wasn\'t reached when it wasn\'t (offline), before the music server\'s',
    /: status\.offline \? CANT_OPEN_OFFLINE\s*: !status\.ok \? CANT_OPEN_DOWN/.test(app), true)
  const you = fs.readFileSync(path.join(SRC, 'app/You.tsx'), 'utf8')
  check('You -> Connections only for whoever runs deadwax, and its pings asked only for them',
    [/\{runsDeadwax && \(\s*<section class="app-section" aria-labelledby="app-connections-title">/.test(you), /if \(!seesDetail\(accessNow\(\)\)\) \{\s*setChecks\(null\)\s*return\s*\}/.test(you)], [true, true])
  check('...each row a word for its code (pingWords), never the code', [/pingWords\(service, answer\.code, answer\.error\)/.test(you), /text: code \|\|/.test(you)], [true, false])
}

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})()
