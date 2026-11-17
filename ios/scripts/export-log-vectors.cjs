#!/usr/bin/env node
/**
 * The event log on the iPhone app (Phase 8, slice 9 - notes/ios-specs/phase8-managing.md 8): the lines joined from the
 * history and the stream, the gap a history not read leaves and the next fills, Clear, a line's level and time, the
 * stream's words and where it is asked from - written as a fixture the Swift port
 * (ios/DeadwaxKit/Sources/DeadwaxCore/EventLog.swift, EventStream.swift) replays in
 * Tests/DeadwaxCoreTests/EventLogVectorTests.swift.
 *
 * Compiles lib/eventLog.ts, api/logs.ts, lib/errorWords.ts and lib/permissions.ts with the repo's TypeScript and runs
 * them AS THEY ARE, on inputs from the plain to the awkward: a deadwax logging, restarting and logging again, read by a
 * page whose history reads sometimes fail, whose stream drops and is asked again from the number held (or, as the
 * browser's EventSource asks, from the number it first asked from), and whose Clear comes at any moment; lines of an
 * older deadwax with no number, fields of the wrong type, more lines than are kept; times in four time zones, across
 * their clocks' changes, before 1970 and at the end of what a Date can hold. And reads out of app/EventLog.tsx,
 * lib/appRoutes.ts, app/App.tsx and app/access.ts what the page works out itself - a line's key, the empty words, the
 * history's failure, the stream's address from what is held, who opens the page - each by a pattern, compiled and run
 * as written; and every sentence the page says that the phone says too. A pattern that no longer matches stops this
 * script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/log/log-vectors.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/ioslog.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a backslash-u escape), so a run on any machine writes
 * the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-log-vectors.cjs           write the fixture
 *   node ios/scripts/export-log-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'log', 'log-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-log-vectors.cjs'
const SOURCES = ['lib/eventLog.ts', 'api/logs.ts', 'lib/errorWords.ts', 'lib/permissions.ts']
const PAGE = 'app/EventLog.tsx'
const ROUTES = 'lib/appRoutes.ts'
const APP = 'app/App.tsx'
const ACCESS = 'app/access.ts'

const sha256 = (body) => crypto.createHash('sha256').update(body).digest('hex')
const source = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')
const madeFrom = Object.fromEntries(SOURCES.map((file) => [`ui/src/${file}`, sha256(source(file))]))

/** A piece read out of a source by `pattern`: its match, hashed - the script stops when it is gone. */
function piece(file, pattern, what) {
  const found = pattern.exec(source(file))
  if (!found) throw new Error(`couldn't read ${what} out of ui/src/${file} - the web app's code moved; change this script with it`)
  madeFrom[`ui/src/${file} ${what}`] = sha256(found[0])
  return found
}

/** A sentence the component says as written, hashed with what it is - the script stops when it is gone. */
function says(file, text, what) {
  if (!source(file).includes(text)) throw new Error(`ui/src/${file} no longer says ${JSON.stringify(text)} (${what})`)
  madeFrom[`ui/src/${file} ${what}`] = sha256(text)
  return text
}

/* ===== the web's code, compiled ===== */

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-log-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const L = require(path.join(OUT, 'lib/eventLog.js'))
const A = require(path.join(OUT, 'api/logs.js'))
const E = require(path.join(OUT, 'lib/errorWords.js'))
const P = require(path.join(OUT, 'lib/permissions.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))
const ts = require(path.join(UI, 'node_modules/typescript'))
fs.rmSync(OUT, { recursive: true, force: true })

/** A TypeScript expression or body, its types stripped by TypeScript itself, as a function of `names`. */
function compiled(names, body) {
  const js = ts.transpileModule(`module.exports = function (${names.join(', ')}) {\n${body}\n}`, {
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS },
  }).outputText
  const module = { exports: null }
  new Function('module', 'exports', js)(module, module.exports)
  return module.exports
}

let seed = 9370
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/** An error as the web meets it - its own ApiError, fetch's TypeError, a TimeoutError, or any other Error - and the
 *  spec the Swift remakes it from (screenFailure). */
function madeError(spec) {
  if ('status' in spec) {
    return new ApiError(spec.status, spec.detail ?? null, `GET /interface_logs/recent failed`, false, null, spec.why ?? null, '/interface_logs/recent')
  }
  if ('offline' in spec) return new TypeError(spec.offline)
  if ('timeout' in spec) return Object.assign(new Error(spec.timeout), { name: 'TimeoutError' })
  return new Error(spec.other)
}

/* ===== EventLog.tsx's own, read out of it ===== */

const keyOf = compiled(['line', 'index'], `return ${piece(PAGE,
  /<li key=\{(line\.seq !== undefined \? `\$\{line\.boot \?\? ''\}:\$\{line\.seq\}` : `n\$\{index\}`)\}/, "a line's key")[1]}`)
const emptyOf = compiled(['log', 'EMPTY_WORDS'], `return ${piece(PAGE,
  /<p class="app-log-empty">\{(log\.cleared \? EMPTY_WORDS\.cleared : EMPTY_WORDS\.never)\}<\/p>/, 'the empty words')[1]}`)
const failedFound = piece(PAGE, /setHistoryFailed\((sayError\(reason, '', \{ failed: "([^"]+)", retry: true \}\))\)/, "the history's failure")
const historyFailedOf = compiled(['reason', 'sayError'], `return ${failedFound[1]}`)
const streamUrlOf = compiled(['logStreamUrl', 'last', 'boot'], `return ${piece(PAGE,
  /new EventSource\((logStreamUrl\(boot \? last : null, boot\))\)/, "the stream's address")[1]}`)
says(PAGE, 'const { last, boot } = kept', 'asked from what is held')
says(PAGE, "made.onopen = () => {\n        if (!closed) setStream('live')", 'Live once it opens')
says(PAGE, "setStream('lost')", 'lost, one line')
says(PAGE, 'if (made.readyState !== EventSource.CLOSED || retry) return', 'a stream the browser gave up on')
says(PAGE, 'retry = setTimeout(() => {\n          retry = null\n          connect()\n        }, STREAM_RETRY_MS)', 'asked again by hand, the history first')
says(PAGE, 'line = JSON.parse(String(event.data)) as LogLine', "a message's line")
says(PAGE, 'join((state) => joinLine(state, line))', 'a line joined')
says(PAGE, 'join((state) => joinHistory(state, recent))\n          open()', 'the history, then the stream')
says(PAGE, "if (!ticket.current() || closed || isAbort(reason)) return", 'a history called off says nothing')
says(PAGE, 'if (!allowed || !live) return', 'held only while it shows')
says(PAGE, 'if (log.lines.length) join(clearLog)', 'Clear, with lines')
says(PAGE, "aria-disabled={log.lines.length ? undefined : 'true'}", 'Clear, off with none')
says(PAGE, '<p class="app-placeholder-text">{MANAGING_ADMINS_ONLY}</p>', 'not allowed')
says(ROUTES, 'export const MANAGING_ADMINS_ONLY = NO_PERMISSION', 'not allowed, in words')
const allowedOf = compiled(['perms'], `return !!(${piece(APP, /<EventLog allowed=\{(perms\.has\('server'\))\}/, 'who opens the page')[1]})`)
//? access.ts's own (it holds Preact's hooks too, so it is read, not compiled whole)
const seesDetailOf = compiled(['access'], piece(ACCESS,
  /export function seesDetail\(access: Pick<Access, 'admin' \| 'permissions'>\): boolean \{\n\s*(return access\.admin \|\| access\.permissions\.has\('server'\))\n\}/,
  'who runs deadwax')[1])

const words = {
  title: piece(PAGE, /<h1 class="pl-large-title">([^<]+)<\/h1>/, 'the title')[1],
  pageLine: piece(PAGE, /<p class="app-log-line">\n\s*([^\n<]+)\n\s*<\/p>/, "the page's line")[1],
  listLabel: piece(PAGE, /<ol class="app-log-list" aria-label="([^"]+)">/, "the list's label")[1],
  clear: piece(PAGE, /if \(log\.lines\.length\) join\(clearLog\)\n\s*\}\}\n\s*>\n\s*([^\n<]+)\n\s*<\/button>/, 'Clear')[1],
  historyFailed: failedFound[2],
  emptyNever: L.EMPTY_WORDS.never,
  emptyCleared: L.EMPTY_WORDS.cleared,
  connecting: L.STREAM_WORDS.connecting,
  live: L.STREAM_WORDS.live,
  lost: L.STREAM_WORDS.lost,
  noPermission: P.NO_PERMISSION,
  kept: L.LOG_KEPT,
  retryMs: L.STREAM_RETRY_MS,
}

/* ===== a line's level ===== */

const levels = ['INFO', 'WARNING', 'ERROR', 'CRITICAL', 'DEBUG', 'WARN', 'warn', 'Warning', 'error', 'Critical', '', ' ERROR',
  'ERROR ', 'FATAL', 'NOTICE', 'information', 'ERRORS', 'warnings', 'ß', 'ﬀ', 'İ', 'ı', 'ǅ', 'erroR', 'cRiTiCaL']
  .map((type) => ({ type, level: L.levelOf(type) }))

/* ===== a line's time, on four clocks ===== */

//? process.env.TZ assigned at run time is read again by Node's Date (Node 13 on)
const ZONES = ['UTC', 'Europe/London', 'America/St_Johns', 'Asia/Kathmandu']
const MOMENTS = [0, 0.0009, 0.001, 0.9999, 1, 1.5, 59.999, 60, 86399.999, 86400, -0.0005, -0.001, -1, -1.5, -86400.5,
  1763300000, 1763300000.123, 1763300000.9995, 1774746000 - 0.001, 1774746000, 1774749599.999, 1774749600,
  1792890000 - 1, 1792890000, 1792893600, 1772420400, 1773550800, 1793682000 - 1, 1793682000, 2147483647, 2147483648,
  -2147483648, 4102444800, 1e9, 1234567890.5, 951782400, 978307199.999]
const FAR = [8.64e12, -8.64e12, 8.64e12 + 0.001, 8.64e12 + 1, -8.64e12 - 1, 1e13, -1e13, 1e300, -1e300, 2.5e11]
const times = []
for (const zone of ZONES) {
  process.env.TZ = zone
  for (const time of MOMENTS) times.push({ zone, time, said: L.lineTime({ event_type: 'INFO', event_content: '', time }) })
}
process.env.TZ = 'UTC'
for (const time of FAR) times.push({ zone: 'UTC', time, said: L.lineTime({ event_type: 'INFO', event_content: '', time }) })
for (let n = 0; n < 40; n++) {
  const zone = pick(ZONES)
  process.env.TZ = zone
  const time = between(0, 2000000000) + between(0, 999) / 1000
  times.push({ zone, time, said: L.lineTime({ event_type: 'INFO', event_content: '', time }) })
}
process.env.TZ = 'UTC'
//? no time, or one of another type: nothing (the run's lines carry these too)
const untimed = [null, 'NaN', '12:00:00', true, [1], { at: 1 }].map((time) => ({ time, said: L.lineTime({ event_type: 'INFO', event_content: '', ...(time === null ? {} : { time }) }) }))

/* ===== the page's runs: a deadwax logging, the history, the stream, Clear ===== */

const SOURCES_SAID = ['src.routes.download', 'src.poller', 'src.organizer', 'src.api.slskd_endpoint', 'src.main', 'uvicorn.error']
const WORDS_SAID = ['Searching Soulseek for "Kid A"', 'download 41 finished', 'Filed 12 tracks into Radiohead/Kid A (2000)',
  'slskd answered 409: not logged in to Soulseek', 'MusicBrainz is busy - trying again', '<b>not markup</b> & "quotes"',
  'Sigur Rós - ( )', '日本語のタイトル', 'emoji 🎛️ and a tab\tin it', 'a line\nthat breaks', '']
const TYPES_SAID = ['INFO', 'INFO', 'INFO', 'WARNING', 'ERROR', 'CRITICAL', 'DEBUG']

/** A deadwax: its runs, each named and numbered from 1, and the last 500 lines meant for the page (src/logger.py). */
function server(boot) {
  return { boot, seq: 0, kept: [], clock: 1763300000 + between(0, 100000) }
}

function logged(deadwax) {
  deadwax.seq += 1
  deadwax.clock += between(0, 4000) / 1000
  const line = { event_type: pick(TYPES_SAID), event_content: pick(WORDS_SAID), seq: deadwax.seq, time: deadwax.clock, boot: deadwax.boot }
  if (chance(0.8)) line.src = pick(SOURCES_SAID)
  deadwax.kept.push(line)
  if (deadwax.kept.length > L.LOG_KEPT) deadwax.kept.shift()
  return line
}

/** `GET /recent`'s body: `{lines, last, boot}` - the lines as kept carry their own boot (SSEHandler adds it). */
function recent(deadwax, { bare = false } = {}) {
  const lines = deadwax.kept.map((line) => {
    if (!bare) return line
    const { boot: _boot, ...rest } = line
    return rest
  })
  return { lines, last: deadwax.seq, boot: deadwax.boot }
}

/** What the stream sends first: the kept lines after `after` of run `boot` - every one, for another run's. */
function replay(deadwax, after, boot) {
  if (after === null || boot === null) return []
  if (boot !== deadwax.boot) return deadwax.kept.slice()
  return deadwax.kept.filter((line) => line.seq > after)
}

const runs = []

/** A run of ops on a page, each applied with the web's own functions and its state after it written down. */
function run(name, ops) {
  let state = L.emptyLog()
  const steps = []
  for (const op of ops) {
    if (op.line !== undefined) state = L.joinLine(state, JSON.parse(op.line))
    else if (op.history !== undefined) state = L.joinHistory(state, JSON.parse(op.history))
    else if (op.clear) state = L.clearLog(state)
    steps.push({
      ...op,
      after: {
        boot: state.boot, last: state.last, gap: state.gap, cleared: state.cleared, count: state.lines.length,
        top: state.lines.slice(0, 2).map((line) => JSON.stringify(line)),
        empty: emptyOf(state, L.EMPTY_WORDS),
        url: streamUrlOf(A.logStreamUrl, state.last, state.boot),
      },
    })
  }
  runs.push({
    name,
    steps,
    lines: state.lines.map((line) => JSON.stringify(line)),
    keys: state.lines.map((line, index) => keyOf(line, index)),
  })
}

const lineOp = (line) => ({ line: JSON.stringify(line) })
const historyOp = (body) => ({ history: JSON.stringify(body) })

//? the plain: the history, then the stream from where it ends - its replay and a reconnect sending lines again
{
  const d = server('a1b2c3d4e5f6')
  for (let i = 0; i < 6; i++) logged(d)
  const ops = [historyOp(recent(d))]
  const held = d.seq
  for (let i = 0; i < 3; i++) ops.push(lineOp(logged(d)))
  //? EventSource asking again from the number it first asked from: the three again, then what is new
  for (const line of replay(d, held, d.boot)) ops.push(lineOp(line))
  ops.push(lineOp(logged(d)))
  run('the history, then the stream, a reconnect replaying', ops)
}
//? the history failed: the stream from now leaves a gap, the next history fills it under the run's lines
{
  const d = server('0f0f0f0f0f0f')
  for (let i = 0; i < 8; i++) logged(d)
  const ops = []
  for (let i = 0; i < 3; i++) ops.push(lineOp(logged(d)))
  ops.push(historyOp(recent(d)))
  ops.push(lineOp(logged(d)))
  run('a history not read, a gap, filled', ops)
}
//? a gap and an older run under it: filled between them
{
  const old = server('aaaaaaaaaaaa')
  for (let i = 0; i < 4; i++) logged(old)
  const ops = [historyOp(recent(old))]
  const d = server('bbbbbbbbbbbb')
  for (let i = 0; i < 5; i++) logged(d)
  //? deadwax restarted while the stream was down: the stream from now of the new run
  for (let i = 0; i < 2; i++) ops.push(lineOp(logged(d)))
  ops.push(historyOp(recent(d)))
  run('a gap over an older run, filled between them', ops)
}
//? deadwax restarted: the stream asked with the old run's number gets every kept line of the new one
{
  const old = server('111111111111')
  for (let i = 0; i < 5; i++) logged(old)
  const ops = [historyOp(recent(old))]
  const d = server('222222222222')
  for (let i = 0; i < 4; i++) logged(d)
  for (const line of replay(d, old.seq, old.boot)) ops.push(lineOp(line))
  ops.push(historyOp(recent(d)))
  run('a restart, the stream asked with the old number', ops)
}
//? a restart with nothing logged yet: the history of another run is that run's from now
{
  const old = server('333333333333')
  for (let i = 0; i < 3; i++) logged(old)
  const d = server('444444444444')
  run('a restart, nothing logged yet', [historyOp(recent(old)), historyOp(recent(d)), lineOp(logged(d))])
}
//? the first line deadwax logged, with no history: no gap
{
  const d = server('555555555555')
  run('the first line, no history', [lineOp(logged(d)), lineOp(logged(d)), historyOp(recent(d))])
}
//? Clear: emptied, the number kept - nothing cleared comes back, the lines since do
{
  const d = server('666666666666')
  for (let i = 0; i < 5; i++) logged(d)
  const ops = [historyOp(recent(d)), { clear: true }, historyOp(recent(d))]
  ops.push(lineOp(logged(d)))
  ops.push({ clear: true }, { clear: true })
  ops.push(historyOp(recent(d)))
  ops.push(lineOp(logged(d)))
  run('Clear, then the history and the lines since', ops)
}
//? Clear over a gap: the gap goes, nothing older comes back
{
  const d = server('777777777777')
  for (let i = 0; i < 6; i++) logged(d)
  run('Clear over a gap', [lineOp(logged(d)), { clear: true }, historyOp(recent(d)), lineOp(logged(d))])
}
//? more than are kept: the oldest go
{
  const d = server('888888888888')
  const ops = []
  for (let i = 0; i < 520; i++) ops.push(lineOp(logged(d)))
  ops.push(historyOp(recent(d)))
  run('more lines than are kept', ops)
}
//? a history of 500 joined over a page holding a few
{
  const d = server('999999999999')
  const ops = [lineOp(logged(d))]
  for (let i = 0; i < 700; i++) logged(d)
  ops.push(historyOp(recent(d)))
  run('a full history over a few lines', ops)
}
//? a history whose lines carry no boot of their own: the history's
{
  const d = server('abcabcabcabc')
  for (let i = 0; i < 4; i++) logged(d)
  run('a history with bare lines', [lineOp(logged(d)), historyOp(recent(d, { bare: true })), lineOp(logged(d))])
}
//? an older deadwax: no numbers, no boot - every line taken
{
  const ops = []
  for (let i = 0; i < 6; i++) ops.push(lineOp({ event_type: pick(TYPES_SAID), event_content: `old ${i}`, src: pick(SOURCES_SAID) }))
  ops.push(lineOp({ event_type: 'INFO', event_content: 'old again' }))
  ops.push(historyOp({ lines: [{ event_type: 'INFO', event_content: 'kept, unnumbered' }], last: 0, boot: '' }))
  run('an older deadwax, nothing numbered', ops)
}
//? fields of the wrong type, read loosely: a number that isn't one is none
{
  const ops = [
    historyOp({ lines: [{ event_type: 'INFO', event_content: 'one', seq: 1, time: 1763300000, boot: 'cdcdcdcdcdcd' }], last: 1, boot: 'cdcdcdcdcdcd' }),
    lineOp({ event_type: 'INFO', event_content: 'seq as words', seq: '2', time: 1763300001, boot: 'cdcdcdcdcdcd' }),
    lineOp({ event_type: 'WARNING', event_content: 'time as words', seq: 2, time: 'soon', boot: 'cdcdcdcdcdcd' }),
    lineOp({ event_type: 'ERROR', event_content: 'src as a number', seq: 3, time: 1763300003, boot: 'cdcdcdcdcdcd', src: 7 }),
    lineOp({ event_type: 'INFO', event_content: 'again', seq: 3, time: 1763300004, boot: 'cdcdcdcdcdcd' }),
    lineOp({ event_type: 'INFO', event_content: 'lower', seq: 1, time: 1763300005, boot: 'cdcdcdcdcdcd' }),
    lineOp({ event_type: 'INFO', event_content: 'no boot, this run', seq: 4, time: 1763300006 }),
    lineOp({ event_type: 'INFO', event_content: 'no boot, again', seq: 4, time: 1763300007 }),
    lineOp({ event_type: 'INFO', event_content: 'a big number', seq: 9007199254740991, time: 1763300008, boot: 'cdcdcdcdcdcd' }),
  ]
  run('fields of the wrong type', ops)
}
//? at random: a deadwax logging and restarting, a page reading the history (or failing to), the stream dropping and
//? asked again - from the number held, or (EventSource's way) from the number it first asked from - and Clear
for (let n = 0; n < 24; n++) {
  let d = server(crypto.createHash('sha256').update(`run ${n}`).digest('hex').slice(0, 12))
  let state = L.emptyLog()
  const ops = []
  const apply = (op) => {
    ops.push(op)
    if (op.line !== undefined) state = L.joinLine(state, JSON.parse(op.line))
    else if (op.history !== undefined) state = L.joinHistory(state, JSON.parse(op.history))
    else if (op.clear) state = L.clearLog(state)
  }
  for (let i = 0; i < between(0, 30); i++) logged(d)
  let asked = null
  const connect = () => {
    if (chance(0.75)) apply(historyOp(recent(d, { bare: chance(0.2) })))
    asked = { after: state.boot ? state.last : null, boot: state.boot }
    for (const line of replay(d, asked.after, asked.boot)) apply(lineOp(line))
  }
  connect()
  for (let step = 0; step < between(10, 60); step++) {
    const roll = rand()
    if (roll < 0.55) apply(lineOp(logged(d)))
    else if (roll < 0.62) { for (let i = 0; i < between(1, 40); i++) logged(d) } // logged while the stream was down
    else if (roll < 0.70) connect()
    else if (roll < 0.76) { for (const line of replay(d, asked.after, asked.boot)) apply(lineOp(line)) } // EventSource's own
    else if (roll < 0.80) apply({ clear: true })
    else if (roll < 0.84) { d = server(crypto.createHash('sha256').update(`run ${n} ${step}`).digest('hex').slice(0, 12)); for (let i = 0; i < between(0, 8); i++) logged(d) }
    else if (roll < 0.88) apply(historyOp(recent(d)))
    else { for (let i = 0; i < between(1, 3); i++) apply(lineOp(logged(d))) }
  }
  run(`at random ${n}`, ops)
}

/* ===== the history's failure, in words ===== */

const ERRORS = [
  { status: 403, detail: "That needs Settings and the log, which an admin hasn't given you." },
  { status: 401, detail: 'Not signed in.' },
  { status: 404, detail: 'Not Found' },
  { status: 429, detail: 'Too many requests.' },
  { status: 500, detail: null },
  { status: 502, detail: null },
  { status: 503, detail: "the database isn't available.", why: 'DB_PATH points at a folder that is not writable.' },
  { status: 504, detail: 'Gateway Timeout' },
  { offline: 'Failed to fetch' },
  { offline: 'Load failed' },
  { timeout: 'signal timed out' },
  { other: 'Unexpected token < in JSON at position 0' },
]
const historyErrors = []
for (const error of ERRORS) {
  for (const admin of [false, true]) {
    const sayError = (caught, lead, options) => E.noticeWords(lead, caught, { ...options, admin })
    historyErrors.push({ error, admin, said: historyFailedOf(madeError(error), sayError) })
  }
}

/* ===== the stream's address, from what is held ===== */

const addresses = []
for (const [last, boot] of [[0, null], [5, null], [0, ''], [0, 'a1b2c3d4e5f6'], [7, 'a1b2c3d4e5f6'], [500, 'ffffffffffff'],
  [123456, '0123456789ab'], [3, 'with space'], [4, 'a+b&c=d/e?f#g'], [9, 'Rosé']]) {
  const url = streamUrlOf(A.logStreamUrl, last, boot)
  const at = url.indexOf('?')
  const query = at < 0 ? [] : [...new URLSearchParams(url.slice(at + 1)).entries()]
  addresses.push({ last, boot, url, path: at < 0 ? url : url.slice(0, at), query })
}

/* ===== who opens the page ===== */

const permissions = []
for (let bits = 0; bits < 64; bits++) {
  const list = P.PERMISSIONS.filter((_, at) => bits & (1 << at))
  const perms = new Set(list)
  permissions.push({ permissions: list, admin: false, allowed: allowedOf(perms), seesDetail: seesDetailOf({ admin: false, permissions: perms }) })
}
permissions.push({ permissions: [...P.PERMISSIONS], admin: true, allowed: allowedOf(new Set(P.PERMISSIONS)), seesDetail: seesDetailOf({ admin: true, permissions: new Set(P.PERMISSIONS) }) })

/* ===== output: plain ASCII ===== */

const BACKSLASH = String.fromCharCode(92)
function ascii(json) {
  let out = ''
  for (let i = 0; i < json.length; i++) {
    const unit = json.charCodeAt(i)
    out += unit < 0x7f ? json[i] : BACKSLASH + 'u' + unit.toString(16).padStart(4, '0')
  }
  return out
}
const flat = (value) => ascii(JSON.stringify(value))

const fixture = {
  about: "The event log (lib/eventLog.ts, api/logs.ts, lib/errorWords.ts and lib/permissions.ts run as they are; app/EventLog.tsx's page, lib/appRoutes.ts's words, app/App.tsx's and app/access.ts's own, read out of their source). Each line and history is a body as deadwax sends it; a run's `after` is the web's state after its op.",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  words,
  levels,
  times,
  untimed,
  runs,
  historyErrors,
  addresses,
  permissions,
}
const LISTED = new Set(['levels', 'times', 'untimed', 'runs', 'historyErrors', 'addresses', 'permissions'])
const body = [
  '{',
  Object.entries(fixture).map(([key, value]) => LISTED.has(key)
    ? `  ${flat(key)}: [\n${value.map((row) => `    ${flat(row)}`).join(',\n')}\n  ]`
    : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
  '}',
  '',
].join('\n')
const steps = runs.reduce((sum, one) => sum + one.steps.length, 0)
const counted = `${runs.length} runs of ${steps} steps, ${times.length} times, ${historyErrors.length} failures, ${permissions.length} permission sets`
if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log(`The event log's fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
    console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
    process.exit(1)
  }
  console.log(`The event log's fixture matches the web app's TypeScript (${counted}).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${counted}, ${Math.round(body.length / 1024)} KB`)
}
