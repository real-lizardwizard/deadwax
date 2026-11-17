#!/usr/bin/env node
/**
 * The iPhone app's Manage section (app 0.13, Phase 7 - notes/ios-specs/phase7-managing.md): which of deadwax's
 * managing tools the web app offers for which permissions - written as a fixture the Swift port
 * (ios/DeadwaxKit/Sources/DeadwaxCore/Managing.swift) replays in Tests/DeadwaxCoreTests/ManagingVectorTests.swift, so
 * the phone's Settings > Manage lists exactly the web's rows. (Until Phase 8's slice 12 it also made the address each
 * opened at in the web app; every row is the app's own page now, and nothing in the app opens the web app.)
 *
 * Compiles, as export-gate-vectors.cjs does, lib/permissions.ts, lib/ownPassword.ts and app/access.ts with the repo's
 * TypeScript (Preact stubbed: access.ts imports its hooks), and runs them AS THEY ARE:
 * - `managing` for every one of the 64 sets of permissions, logins on and off, and `albumEdit` and (Phase 8, slice 5)
 *   `artistManaging` for each;
 * - a run of /deadwax/me answers through `accessOf`, then You's own `managing` expression (read out of You.tsx and
 *   evaluated as written), `albumEdit`, `seesDetail` and `changeOffered`.
 * And reads You.tsx's Manage section out of its source: its title, and its rows in order, each with the part of
 * `managing` that draws it and its label. And App.tsx's album page Edit chip, which the phone follows (after review):
 * its `onEdit` rule and App's `perms`, evaluated as written for every set and answer. A pattern that no longer matches
 * stops this script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/managing/managing-vectors.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/iosmanaging.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a \u escape), so a run on any machine writes the
 * same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-managing-vectors.cjs           write the fixture
 *   node ios/scripts/export-managing-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'managing', 'managing-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-managing-vectors.cjs'
const SOURCES = ['lib/permissions.ts', 'lib/ownPassword.ts', 'app/access.ts']
const YOU = 'app/You.tsx'
const APP = 'app/App.tsx'

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
/** JSX's text: each line trimmed, the empty ones dropped, the rest joined by one space. */
const jsxText = (raw) => raw.split('\n').map((line) => line.trim()).filter(Boolean).join(' ')

/* ===== the web's code, compiled ===== */

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-managing-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
exports.useState = (v) => [typeof v === 'function' ? v() : v, () => {}]
exports.useEffect = () => {}
`)

const P = require(path.join(OUT, 'lib/permissions.js'))
const O = require(path.join(OUT, 'lib/ownPassword.js'))
const A = require(path.join(OUT, 'app/access.js'))

/* ===== You's Manage section, read out of its source ===== */

const sectionAt = piece(YOU, /\{managing\.any && \(\s*<section class="app-section" aria-labelledby="app-managing-title">([\s\S]*?)<\/section>\s*\)\}/,
  'the Manage section')
const title = jsxText(piece(YOU, /<h2 id="app-managing-title" class="app-section-title">([^<]*)<\/h2>/, 'the Manage title')[1])
const rows = []
for (const found of sectionAt[1].matchAll(/\{managing\.(\w+) && \(\s*<button[\s\S]*?<span class="app-row-label">([^<]*)<\/span>/g)) {
  rows.push({ part: found[1], label: jsxText(found[2]) })
}
if (rows.length < 5) throw new Error(`read ${rows.length} rows out of You's Manage section - the web app's code moved`)
const managingCall = piece(YOU, /\n\s*const managing = (managingOf\(.+\))\n/, "You's managing")[1]
const managingOf = new Function('managingOf', 'access', `return (${managingCall})`)
const youManaging = (access) => managingOf(P.managing, access)
const PARTS = ['queue', 'care', 'people', 'settings', 'log']
for (const row of rows) {
  if (!PARTS.includes(row.part)) throw new Error(`You's Manage section has a row for managing.${row.part}, which the port doesn't know`)
}

/* ===== App's own, read out of its source ===== */

//? the album page's Edit chip: App hands AlbumPage `onEdit` by this rule over its `perms` - the phone's Edit an album
//? row and the album's Edit album follow it. Exactly one such onEdit, or the script can't say which is drawn.
const chipRule = /onEdit=\{(albumEdit\(perms\)\.\w+) \? toggleEdit : undefined\}/
if ([...source(APP).matchAll(new RegExp(chipRule.source, 'g'))].length !== 1) {
  throw new Error("App.tsx doesn't hand AlbumPage its Edit by one albumEdit rule any more - the web app's code moved")
}
const chipCall = piece(APP, chipRule, "the album page's Edit")[1]
const permsCall = piece(APP, /\n\s*const perms = (.+)\n/, "App's perms")[1]
const chip = new Function('albumEdit', 'perms', `return (${chipCall})`)
const permsOf = new Function('access', `return (${permsCall})`)
const albumPage = (permissions) => chip(P.albumEdit, permissions) === true

/* ===== the cases ===== */

const setOf = (mask) => new Set(P.PERMISSIONS.filter((_, bit) => mask & (1 << bit)))
const sorted = (set) => P.PERMISSIONS.filter((name) => set.has(name))
const partsOf = (managing) => Object.fromEntries([...PARTS, 'any'].map((key) => [key, managing[key]]))

const sets = []
for (let mask = 0; mask < 1 << P.PERMISSIONS.length; mask++) {
  const permissions = setOf(mask)
  sets.push({
    permissions: sorted(permissions),
    on: partsOf(P.managing(permissions, true)),
    off: partsOf(P.managing(permissions, false)),
    albumEdit: P.albumEdit(permissions),
    albumPage: albumPage(permissions),
    artistManaging: P.artistManaging(permissions),
  })
}

const on = (user, more = {}) => ({ user, admin: false, auth: 'on', ...more })
const ME = [
  { user: 'local', admin: true, auth: 'off' },
  { user: 'local', admin: true, auth: 'off', permissions: [] },
  { user: 'local', admin: false, auth: 'off', permissions: ['request'] },
  on('james', { admin: true, permissions: [...P.PERMISSIONS] }),
  on('admin', { admin: true }),
  on('deadwax', { admin: true, permissions: [...P.PERMISSIONS] }),
  on('ethan', { permissions: ['request'] }),
  on('ethan', { permissions: [] }),
  on('ethan'),
  on('ethan', { permissions: ['edit'] }),
  on('ethan', { permissions: ['library'] }),
  on('ethan', { permissions: ['request', 'edit', 'library'] }),
  on('ethan', { permissions: ['downloads'] }),
  on('sam', { permissions: ['request', 'server'] }),
  on('sam', { permissions: ['server'], permissions_unverified: true }),
  on('ethan', { permissions: ['people'] }),
  on('ethan', { permissions: ['request', 'everything', 'Server', 'edit '] }),
  on('Deadwax', { permissions: ['request'] }),
  on('', { permissions: ['request', 'edit'] }),
  { user: 'ethan', admin: false, auth: 'proxy', permissions: ['library', 'server', 'people'] },
]
const me = ME.map((answer) => {
  const access = A.accessOf(answer)
  return {
    me: answer,
    access: { permissions: sorted(access.permissions), on: access.on, admin: access.admin, unverified: access.unverified },
    managing: partsOf(youManaging(access)),
    albumEdit: P.albumEdit(access.permissions),
    albumPage: albumPage(permsOf(access)),
    seesDetail: A.seesDetail(access),
    changeOffered: O.changeOffered(answer),
  }
})

fs.rmSync(OUT, { recursive: true, force: true })

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
  about: "Manage (app/You.tsx, app/App.tsx, lib/permissions.ts, lib/ownPassword.ts, app/access.ts): which managing tools the web app offers for which permissions - run as they are; You's Manage section and App's album page Edit rule read out of their source.",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  words: { title, rows, CHANGE_TITLE: O.CHANGE_TITLE, LABELS: P.LABELS, PERMISSIONS: P.PERMISSIONS },
  me,
  sets,
}
const listed = new Set(['me', 'sets'])
const body = [
  '{',
  Object.entries(fixture).map(([key, value]) => listed.has(key)
    ? `  ${flat(key)}: [\n${value.map((row) => `    ${flat(row)}`).join(',\n')}\n  ]`
    : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
  '}',
  '',
].join('\n')

if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log(`Manage's fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
    console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
    process.exit(1)
  }
  console.log(`Manage's fixture matches the web app's TypeScript (${sets.length} sets, ${me.length} answers, ${rows.length} rows).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${sets.length} sets, ${me.length} answers, ${rows.length} rows, ${Math.round(body.length / 1024)} KB`)
}
