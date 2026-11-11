#!/usr/bin/env node
/**
 * The iPhone app's You tab (app 0.2, Phase 1): what the web app's You answers, written as a fixture the Swift port
 * (ios/DeadwaxKit/Sources/DeadwaxCore/YouLines.swift) replays in Tests/DeadwaxCoreTests/ScreenYouTests.swift - so the
 * phone's headline, About and the words it shares with the web say what the web's say.
 *
 * You.tsx is one big component (the pings, Getting albums, Managing...), so nothing of it is compiled or run whole:
 * the few expressions the phone's You draws by - who is signed in, the headline, the line under it, the avatar's
 * letter, About's Version and Logins, whether Account is drawn, the UNVERIFIED line - are read out of its source by a
 * pattern and evaluated as written, over every kind of /me answer, failed or not, for an admin or not; and the words
 * (NO_SIGN_IN, NOT_KNOWN, lib/permissions.ts's UNVERIFIED, the section titles, the note under Normalization and the
 * footer under it) are read out the same way, JSX's text rule applied. A pattern that no longer matches stops this
 * script, naming what moved. Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/you/you.json.
 *
 * The web keeps the session's /me apart from You's own (`sessionMe()`); the phone has one answer, so `session` is
 * null in every case here.
 *
 * The file names each piece it was read from with its sha256, so ui/test/iosyou.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a \u escape), so a run on any machine writes the
 * same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-you-vectors.cjs           write the fixture
 *   node ios/scripts/export-you-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs nothing but Node: no tsc, no TMPDIR.
 */

'use strict'

const crypto = require('crypto')
const fs = require('fs'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'you', 'you.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-you-vectors.cjs'

/* ===== the sources, and pieces read out of them ===== */

const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex')
const source = (file) => fs.readFileSync(path.join(UI, 'src', file), 'utf8')
const madeFrom = {}
/** A piece read out of a source by `pattern`: its match, hashed - the script stops when it is gone. */
function piece(file, pattern, what) {
  const found = pattern.exec(source(file))
  if (!found) throw new Error(`couldn't read ${what} out of ui/src/${file} - the web app's code moved; change this script with it`)
  madeFrom[`ui/src/${file} ${what}`] = sha256(found[0])
  return found
}
/** An expression read out of a source, as a function of the names it uses. */
const expression = (text, ...names) => new Function(...names, `return (${text})`)
/** JSX's text: each line trimmed, the empty ones dropped, the rest joined by one space. */
const jsxText = (raw) => raw.split('\n').map((line) => line.trim()).filter(Boolean).join(' ')

const YOU = 'app/You.tsx'

const signedIn = piece(YOU, /\n\s*const signedIn = (.+)\n/, 'signedIn')
const headline = piece(YOU, /\n\s*const headline = (.+)\n/, 'headline')
const identity = piece(YOU, /\n\s*const identity = (.+)\n/, 'identity')
const avatar = piece(YOU, /<span class="app-avatar" aria-hidden="true">\s*\{(.+)\}\s*<\/span>/, 'the avatar')
const version = piece(YOU, /<dt class="app-row-label">Version<\/dt>\s*<dd class="[^"]*">\{(.+)\}<\/dd>/, 'Version')
const logins = piece(YOU, /\{(access\.admin) && \(\s*<div class="app-row">\s*<dt class="app-row-label">Logins<\/dt>\s*<dd class="[^"]*">\{(.+)\}<\/dd>/, 'Logins')
const account = piece(YOU, /\{(.+?) && \(\s*<section class="app-section" aria-labelledby="app-account-title">/, 'Account drawn')
const unverified = piece(YOU, /\{(.+?) && <p class="app-footnote app-you-unverified">\{UNVERIFIED\}<\/p>\}/, 'UNVERIFIED drawn')
const failedNote = piece(YOU, /\{(.+?) \? errorNote\(whoFailed[^}]*\}\) : null\}/, 'the failure under About')

const NO_SIGN_IN = expression(piece(YOU, /export const NO_SIGN_IN = ('[^'\n]*')/, 'NO_SIGN_IN')[1])()
const NOT_KNOWN = expression(piece(YOU, /export const NOT_KNOWN = ('[^'\n]*')/, 'NOT_KNOWN')[1])()
const UNVERIFIED = expression(piece('lib/permissions.ts', /export const UNVERIFIED = ("[^"\n]*")/, 'UNVERIFIED')[1])()

const titled = (id) => jsxText(piece(YOU, new RegExp(`<h2 id="app-${id}-title" class="app-section-title">([^<]*)</h2>`), `the ${id} title`)[1])
const normalizationTitle = jsxText(piece('app/NormalizationChoice.tsx',
  /<h3 id="app-normalization-title" class="app-choice-title">([^<]*)<\/h3>/, 'the title')[1])
const notes = piece(YOU, /<NormalizationChoice \/>\s*<p id="app-normalization-note"[^>]*>([^<]*)<\/p>\s*<p class="app-footnote">([^<]*)<\/p>/,
  'the notes under Normalization')

const signedInOf = expression(signedIn[1], 'who', 'session')
const headlineOf = expression(headline[1], 'signedIn')
const identityOf = expression(identity[1], 'who', 'whoFailed', 'signedIn', 'NO_SIGN_IN')
const avatarOf = expression(avatar[1], 'signedIn')
const versionOf = expression(version[1], 'who', 'whoFailed', 'NOT_KNOWN')
const loginsShownOf = expression(logins[1], 'access')
const loginsOf = expression(logins[2], 'who', 'whoFailed', 'NOT_KNOWN')
const accountOf = expression(account[1], 'who')
const unverifiedOf = expression(unverified[1], 'access')
const failedOf = expression(failedNote[1], 'whoFailed')

/* ===== the cases ===== */

const E_ACUTE = String.fromCharCode(0xe9), COMBINING_ACUTE = String.fromCharCode(0x301)
const SHARP_S = String.fromCharCode(0xdf), DZ = String.fromCharCode(0x1c6)
const on = (user, more = {}) => ({ user, admin: false, auth: 'on', version: '2.1.0', ...more })
const WHO = [
  null,
  on('ethan'),
  on('james', { admin: true }),
  { user: 'local', admin: true, auth: 'off', version: '2.1.0' },
  { user: 'local', admin: true, auth: 'off' },
  on('deadwax', { admin: true }),
  { user: 'ethan', admin: false, auth: 'on' },
  on('ethan', { version: '' }),
  on('Ethan'),
  on(''),
  on(' james'),
  on('1999'),
  on(E_ACUTE + 'mile'),
  on('e' + COMBINING_ACUTE + 'mile'),
  on(SHARP_S + 'a'),
  on(DZ + 'emal'),
  { user: 'ethan', admin: false, auth: 'proxy', version: '2.1.0' },
]

const cases = []
for (const who of WHO) {
  for (const failed of [false, true]) {
    for (const admin of [false, true]) {
      for (const unverifiedOn of [false, true]) {
        const whoFailed = failed ? new Error('GET /me failed') : null
        const access = { admin, unverified: unverifiedOn }
        const name = signedInOf(who, null)
        cases.push({
          who,
          failed,
          access,
          drawn: {
            avatar: avatarOf(name),
            name: headlineOf(name),
            identity: identityOf(who, whoFailed, name, NO_SIGN_IN),
            unverified: unverifiedOf(access) ? UNVERIFIED : null,
            account: Boolean(accountOf(who)),
            version: versionOf(who, whoFailed, NOT_KNOWN),
            logins: loginsShownOf(access) ? loginsOf(who, whoFailed, NOT_KNOWN) : null,
            failed: Boolean(failedOf(whoFailed)),
          },
        })
      }
    }
  }
}

/* ===== output: plain ASCII ===== */

const BACKSLASH = String.fromCharCode(92)
function ascii(text) {
  let out = ''
  for (let i = 0; i < text.length; i++) {
    const unit = text.charCodeAt(i)
    out += unit < 0x7f ? text[i] : BACKSLASH + 'u' + unit.toString(16).padStart(4, '0')
  }
  return out
}
const flat = (value) => ascii(JSON.stringify(value))
const fixture = {
  about: "You (app/You.tsx): the expressions the phone's You draws by, read out of the source and evaluated as written over every kind of /me answer, failed or not, for an admin or not, with an unverified session or not (the session's own /me always null: the phone keeps one answer); and the words it shares with the web.",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  words: {
    NO_SIGN_IN,
    NOT_KNOWN,
    UNVERIFIED,
    titles: { playback: titled('playback'), account: titled('account'), about: titled('about') },
    normalization: normalizationTitle,
    normalizationNote: jsxText(notes[1]),
    webFooter: jsxText(notes[2]),
  },
  cases,
}
const body = [
  '{',
  ['about', 'made_by', 'made_from', 'words'].map((key) => `  ${flat(key)}: ${flat(fixture[key])},`).join('\n'),
  '  "cases": [',
  fixture.cases.map((row) => `    ${flat(row)}`).join(',\n'),
  '  ]',
  '}',
  '',
].join('\n')

if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log("You's fixture differs from what the web app's You answers now: you/you.json.")
    console.log('Run node ios/scripts/export-you-vectors.cjs, and see what the Swift port must follow.')
    process.exit(1)
  }
  console.log(`You's fixture matches the web app's You (${cases.length} cases).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${cases.length} cases, ${Math.round(body.length / 1024)} KB`)
}
