#!/usr/bin/env node
/**
 * Server settings on the iPhone app (Phase 8, slice 8 - notes/ios-specs/phase8-managing.md 7): the settings' groups,
 * rows, drafts and one save, the organizing verdict, Re-time saved lyrics, MusicBrainz's saved answers and Connections -
 * written as a fixture the Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/ServerSettings.swift) replays in
 * Tests/DeadwaxCoreTests/ServerSettingsVectorTests.swift.
 *
 * Compiles lib/serverSettings.ts, lib/musicbrainzAnswers.ts, lib/lyrics.ts, lib/errorWords.ts, lib/permissions.ts and
 * app/access.ts with the repo's TypeScript and runs them AS THEY ARE, on inputs from the plain to the awkward: answers
 * with every kind of setting (a secret set or not, one locked, one overridden with and without the environment's
 * value, one in error), choices written in every order JSON can hold them (array-index keys come first in
 * Object.entries, whatever the order), drafts made in every order, addresses typed with spaces and typed back to what
 * is saved, groups this doesn't know. And reads out of app/ServerSettings.tsx, components/SettingsView.tsx,
 * components/RetimeLyrics.tsx, components/MusicBrainzAnswers.tsx, app/You.tsx and app/App.tsx what the pages work out
 * themselves - a row's value, placeholder, source, badges and revert; the bar's words; what a save's refusal says;
 * Re-time's running words, its note and a run stepped album by album as the module steps it; Clear's refusal, hint, label
 * and line; a Connections row from a ping's answer, Navidrome's status or a failed ask; who sees the page - each by a
 * pattern, compiled and run as written; and every sentence those say that the phone says too. A pattern that no longer
 * matches stops this script, naming what moved.
 * Writes ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/server/server-vectors.json.
 *
 * The file names each source it was made from with its sha256, so ui/test/iosserver.sim.cjs - which runs this with
 * --check - fails when one changes, in what it does or only in its text, until the fixture is written again and the
 * Swift port follows. The output is plain ASCII (anything else as a backslash-u escape), so a run on any machine writes
 * the same bytes. Never edit the fixture by hand - change the TypeScript, then run this.
 *
 *   node ios/scripts/export-server-vectors.cjs           write the fixture
 *   node ios/scripts/export-server-vectors.cjs --check   write nothing; exit 1 when the fixture differs
 *
 * Needs ui/node_modules (tsc) and a writable TMPDIR, as the sims do.
 */

'use strict'

const { execFileSync } = require('child_process')
const crypto = require('crypto')
const fs = require('fs'), os = require('os'), path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const UI = path.join(REPO, 'ui')
const FIXTURE = path.join(REPO, 'ios', 'DeadwaxKit', 'Tests', 'DeadwaxCoreTests', 'Fixtures', 'server', 'server-vectors.json')
const CHECK = process.argv.includes('--check')
const MADE_BY = 'ios/scripts/export-server-vectors.cjs'
const SOURCES = ['lib/serverSettings.ts', 'lib/musicbrainzAnswers.ts', 'lib/lyrics.ts', 'lib/errorWords.ts',
  'lib/permissions.ts']
const ACCESS = 'app/access.ts'
const PAGE = 'app/ServerSettings.tsx'
const VIEW = 'components/SettingsView.tsx'
const RETIME = 'components/RetimeLyrics.tsx'
const ANSWERS = 'components/MusicBrainzAnswers.tsx'
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

/** A sentence the component says as written, hashed with what it is - the script stops when it is gone. */
function says(file, text, what) {
  if (!source(file).includes(text)) throw new Error(`ui/src/${file} no longer says ${JSON.stringify(text)} (${what})`)
  madeFrom[`ui/src/${file} ${what}`] = sha256(text)
  return text
}

/* ===== the web's code, compiled ===== */

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-server-vectors-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  ...SOURCES.map((file) => `src/${file}`),
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node', '--lib', 'es2022,dom',
], { cwd: UI, stdio: 'inherit' })

const S = require(path.join(OUT, 'lib/serverSettings.js'))
const MB = require(path.join(OUT, 'lib/musicbrainzAnswers.js'))
const L = require(path.join(OUT, 'lib/lyrics.js'))
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

let seed = 8017
const rand = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
const pick = (list) => list[Math.floor(rand() * list.length)]
const between = (low, high) => low + Math.floor(rand() * (high - low + 1))
const chance = (p) => rand() < p

/** An error as the web meets it - its own ApiError, fetch's TypeError, a TimeoutError, or any other Error - and the
 *  spec the Swift remakes it from (screenFailure). */
function madeError(spec) {
  if ('status' in spec) {
    return new ApiError(spec.status, spec.detail ?? null, `${spec.method ?? 'PUT'} ${spec.path ?? '/settings'} failed`, false, null, spec.why ?? null, spec.path ?? '/settings')
  }
  if ('offline' in spec) return new TypeError(spec.offline)
  if ('timeout' in spec) return Object.assign(new Error(spec.timeout), { name: 'TimeoutError' })
  return new Error(spec.other)
}

/* ===== ServerSettings.tsx's own, read out of it ===== */

const saveErrorOf = compiled(['caught', 'ApiError', 'sayError'], `return ${piece(PAGE,
  /keep\(\{ saveError: (caught instanceof ApiError && caught\.status === 400 && caught\.detail \? caught\.detail : sayError\(caught, '', \{ failed: "Couldn't save the settings\." \}\)), saving: false \}\)/,
  "a save's refusal")[1]}`)
const barOf = compiled(['saveError', 'justSaved', 'dirty'], `return ${piece(PAGE,
  /\{(saveError \? `Not saved: \$\{saveError\}` : justSaved && !dirty \? 'Saved\.' : dirty \? `\$\{dirty\} unsaved change\$\{dirty === 1 \? '' : 's'\}` : '')\}/,
  "the bar's words")[1]}`)
says(PAGE, "if (!allowed || !live || Object.keys(kept.drafts).length) return", 'never read over a draft')
says(PAGE, "const updates: SettingUpdate[] = Object.entries(sent).map(([key, value]) => ({ key, value }))", 'one batch, every draft')
says(PAGE, "const left = draftsAfterSave(state.drafts, sent)\n        return { server: answer, drafts: left, justSaved: !Object.keys(left).length, saving: false }", 'after a save')
says(PAGE, "keep((state) => ({ justSaved: false, drafts: editedEnvDraft(state.drafts, key, value, settingsByKey.get(key)) }))", 'an edit')
says(PAGE, "keep((state) => ({ justSaved: false, drafts: { ...state.drafts, [key]: null } }))", 'a revert')
says(PAGE, "const discard = () => keep({ drafts: {}, saveError: null })", 'Discard')
says(PAGE, "for (const group of server?.groups ?? []) for (const setting of group.settings) map.set(setting.key, setting)", 'the committed setting, the last by its key')
says(PAGE, "const groups = (server?.groups ?? []).filter((group) => tabForGroup(group.id) === tab)", "a tab's groups")
says(PAGE, "{tab === 'library' && <OrganizingVerdict organizing={server.organizing} />}", 'the verdict')
says(PAGE, "{group.id === 'lyrics' && <RetimeLyrics unsaved={draftEnv['LYRICS_LEAD_MS'] !== undefined} />}", 'Re-time, under the lead')
says(PAGE, "<MusicBrainzAnswers key={savedAnswersKey(group)} live={live} unsaved={draftEnv[SAVED_ANSWERS_PATH] !== undefined} />", 'Clear, under its settings')
says(PAGE, "{errorNote(error, { failed: \"Couldn't read the settings.\", retry: true })}", 'a first read failed')
says(PAGE, "{sayError(error, '', { failed: \"Couldn't read the settings again just now.\" })}", 'a read again failed')
says(PAGE, "for (const listener of [...saved]) listener(Object.keys(sent))", 'a save told')
const lineFound = piece(PAGE, /<p class="app-settings-line">\n([\s\S]*?)\n\s*<\/p>/, "the page's line")[1]
const pageLine = lineFound.replace(/<\/?code>/g, '').replace(/\s+/g, ' ').trim()
const allowedOf = compiled(['perms'], `return !!(${piece(APP, /<ServerSettings allowed=\{(perms\.has\('server'\))\}/, 'who opens the page')[1]})`)
const asksNavidromeOf = compiled(['keys'],
  `return !!(${piece(APP, /if \((keys\.some\(\(key\) => key\.startsWith\('NAVIDROME_'\)\))\) navidromeAsks\.recheck\(\)/, 'a save asks Navidrome again')[1]})`)

/* ===== SettingsView.tsx's own: a row ===== */

const valueOf = compiled(['draft', 'setting'],
  `return ${piece(VIEW, /\n\s*const value = (typeof draft === 'string' \? draft : setting\.secret \? '' : \(setting\.value \?\? ''\))\n/, "a row's value")[1]}`)
const placeholderOf = compiled(['setting'],
  `return ${piece(VIEW, /placeholder=\{(setting\.secret \? \(setting\.value \? '[^']+' : '[^']+'\) : '[^']+')\}/, "a field's placeholder")[1]}`)
piece(VIEW, /const control = !setting\.editable \? \(\n\s*<span class="settings-env-locked" title=\{setting\.locked_reason \?\? undefined\}>Locked<\/span>\n\s*\) : setting\.choices \? \(/, 'the control')
const controlOf = (setting) => !setting.editable ? 'locked' : setting.choices ? 'choices' : setting.secret ? 'secret' : 'text'
says(VIEW, "{Object.entries(setting.choices).map(([choice, label]) => (", 'the choices, in order')
says(VIEW, "type={setting.secret ? 'password' : 'text'}", 'a secret, hidden')
piece(VIEW, /\{setting\.overridden && !edited \? \(\n\s*<span class="settings-env-source is-override"[^>]*>\n\s*Set here\n\s*<\/span>\n\s*\) : setting\.source \? \(\n\s*<span class="settings-env-source"[^>]*>\n\s*From \{setting\.source\}\n/, "a row's source")
const sourceOf = (setting, edited) => setting.overridden && !edited ? 'Set here' : setting.source ? `From ${setting.source}` : null
says(VIEW, '{edited ? <span class="settings-env-badge is-edited">Unsaved</span> : null}', 'Unsaved')
const attentionOf = compiled(['setting', 'edited'],
  `return !!(${piece(VIEW, /\{(setting\.status === 'error' && !edited) \? \(\n\s*<span class="settings-env-badge">Needs attention<\/span>/, 'Needs attention')[1]})`)
const lockedOf = compiled(['setting'],
  `return !!(${piece(VIEW, /\{(!setting\.editable && setting\.locked_reason) \? \(\n\s*<div class="settings-env-effect">\{setting\.locked_reason\}<\/div>/, 'why it is locked')[1]})`)
const revertShownOf = compiled(['setting', 'reverting'],
  `return !!(${piece(VIEW, /\{(setting\.overridden && setting\.editable && !reverting) \? \(\n\s*<button type="button" class="settings-env-revert"/, 'Revert, when')[1]})`)
const revertLabelOf = compiled(['setting'],
  `return \`${piece(VIEW, /\n\s*(Revert to the environment)\{setting\.env_value \? ` \(\$\{setting\.env_value\}\)` : ''\}\n/, 'Revert, its words')[1]}\${setting.env_value ? \` (\${setting.env_value})\` : ''}\``)
const willRevert = piece(VIEW, /\{reverting \? <div class="settings-env-effect">([^<]+)<\/div> : null\}/, 'a revert drafted')[1]
says(VIEW, '{note ? <div class="settings-env-detail">{note}</div> : null}', "another row's note")
const detailOf = compiled(['setting', 'edited'],
  `return !!(${piece(VIEW, /\{(setting\.detail && !edited) \? <div class="settings-env-detail">\{setting\.detail\}<\/div> : null\}/, 'what is wrong')[1]})`)
says(VIEW, 'note={retypeSecretNote(setting.key, server, draftEnv)}', 'the note, by the rule')
const verdictOf = compiled(['organizing'], `return ${piece(VIEW,
  /\{(organizing\.enabled\n\s*\? '[^']+'\n\s*: '[^']+')\}/, 'the verdict')[1]}`)
says(VIEW, '{organizing.blockers.map((blocker) => (', "the verdict's blockers")

function rowOf(setting, server, drafts) {
  const draft = drafts[setting.key]
  const edited = draft !== undefined
  const reverting = draft === null
  return {
    key: setting.key, control: controlOf(setting), value: valueOf(draft, setting), placeholder: placeholderOf(setting),
    source: sourceOf(setting, edited), unsaved: edited, attention: attentionOf(setting, edited), effect: setting.effect,
    locked: lockedOf(setting) ? setting.locked_reason : null,
    revert: revertShownOf(setting, reverting) ? revertLabelOf(setting) : null,
    reverting, note: S.retypeSecretNote(setting.key, server, drafts), detail: detailOf(setting, edited) ? setting.detail : null,
  }
}

/* ===== RetimeLyrics.tsx's own ===== */

const runningLabelOf = compiled(['run'], `return ${piece(RETIME,
  /<Loading label=\{(run\.total \? `Re-timing \$\{Math\.min\(run\.done \+ 1, run\.total\)\} of \$\{run\.total\} albums · Stop after this album` : '[^']+')\} \/>/,
  'the running words')[1]}`)
const retimeNoteOf = compiled(['unsaved', 'run', 'asSentence', 'describeRetime'], `return ${piece(RETIME,
  /<span class="settings-retime-note">\n\s*\{(unsaved\n[\s\S]*?)\}\n\s*<\/span>/, 'the note')[1]}`)
const retimeTitles = piece(RETIME, /title=\{unsaved\n\s*\? '([^']+)'\n\s*: '([^']+)'\n\s*\+ "([^"]+)"\}/, "the button's titles")
const retimeButton = piece(RETIME, /onClick=\{\(\) => void start\(\)\}\n\s*>\n\s*([^\n<]+)\n\s*<\/button>/, 'the button')[1]
const retimeReadFailed = piece(RETIME, /sayError\(caught, '', \{ failed: "([^"]+)", retry: true \}\)/, "the library's read failed")[1]
says(RETIME, '.filter((album) => album.lyrics_count > 0)', 'only albums with lyrics')
says(RETIME, 'const summary = await libraryApi.fetchLyrics(album.path, { retime: true })', 'one album at a time')
says(RETIME, 'totals.failed += album.lyrics_count', 'an album that threw, counted')
says(RETIME, 'if (stop || !ticket.current()) break', 'stopped, asked before each album')
says(RETIME, 'if (run?.running) return', 'one run at a time')
says(RETIME, 'if (!listeners.size && run && !run.running) run = null', 'said once')
says(RETIME, "if (run.running) leadMoved = true\n    else run = null", 'a new lead lets it go')
const endedOf = compiled(['leadMoved', 'last'],
  `return ${piece(RETIME, /const ended = \(last: RetimeRun\): RetimeRun \| null => \((leadMoved \? null : last)\)/, 'how it ended, or nothing')[1]}`)

/* ===== MusicBrainzAnswers.tsx's own ===== */

const emptyOf = compiled(['stats'], `return !!(${piece(ANSWERS, /\n\s*const empty = (!stats \|\| stats\.answers === 0)\n/, 'nothing to clear')[1]})`)
const refusedOf = compiled(['clearing', 'unsaved', 'empty'],
  `return !!(${piece(ANSWERS, /\n\s*const refused = (clearing \|\| unsaved \|\| empty)\n/, 'Clear refused')[1]})`)
const clearTitleOf = compiled(['unsaved', 'clearing', 'empty'], `return ${piece(ANSWERS,
  /title=\{(unsaved\n[\s\S]*?MusicBrainz again\.")\}/, "Clear's title")[1]}`)
const clearLabelOf = compiled(['clearing'], `return ${piece(ANSWERS,
  /\n\s*\{(clearing \? '[^']+' : "[^"]+")\}\n\s*<\/button>/, "Clear's words")[1]}`)
const answersNoteOf = compiled(['unsaved', 'error', 'stats', 'describeSavedAnswers', 'cleared'], `return ${piece(ANSWERS,
  /<span class="settings-answers-note" role="status">\n\s*\{(unsaved\n[\s\S]*?)\}\n\s*<\/span>/, 'the line')[1]}`)
const answersReadFailed = piece(ANSWERS, /sayError\(reason, '', \{ failed: "(Couldn't read [^"]+)" \}\)/, 'a read failed')[1]
const answersClearFailed = piece(ANSWERS, /sayError\(reason, '', \{ failed: "(Couldn't clear [^"]+)" \}\)/, 'a clear failed')[1]
says(ANSWERS, 'if (!live || clearing) return', 'read as it shows, never while it clears')
says(ANSWERS, 'if (refused) return', 'Clear refused on its press')

/* ===== You.tsx's own: Connections ===== */

const services = compiled([], `return ${piece(YOU, /const SERVICES = (\[\n[\s\S]*?\]) as const/, 'the three rows')[1]}`)()
const pending = compiled([], `return ${piece(YOU, /const PENDING: CheckState = (\{ state: 'pending', text: '[^']+' \})/, 'checking')[1]}`)()
const fromPingOf = compiled(['service', 'answer', 'pingWords'],
  piece(YOU, /function fromPing\(service: 'musicbrainz' \| 'slskd', answer: PingAnswer\): CheckState \{\n([\s\S]*?)\n\}\n/, 'a ping as a row')[1])
const fromNavidromeOf = compiled(['status'],
  piece(YOU, /function fromNavidrome\(status: NavidromeStatus\): CheckState \{\n([\s\S]*?)\n\}\n/, "Navidrome's status as a row")[1])
const failedOf = compiled(['PING_UNANSWERED', 'unansweredLine', 'reason'], `return ${piece(YOU,
  /settle\(service, (\{ state: 'failed', text: PING_UNANSWERED, detail: unansweredLine\(reason\) \})\)/, 'an ask that failed')[1]}`)
const connectionsTitle = piece(YOU, /<h2 id="app-connections-title" class="app-section-title">\n\s*([^\n<]+)\n/, 'the title')[1]
const checkAgain = piece(YOU, /onClick=\{checkAll\} disabled=\{!checks\}>\n\s*([^\n<]+)\n/, 'Check again')[1]
says(YOU, '{runsDeadwax && (', 'for whoever runs deadwax')
says(YOU, 'const runsDeadwax = seesDetail(access)', 'who runs deadwax')
//? access.ts's own (it holds Preact's hooks too, so it is read, not compiled whole)
const seesDetailOf = compiled(['access'], piece(ACCESS,
  /export function seesDetail\(access: Pick<Access, 'admin' \| 'permissions'>\): boolean \{\n\s*(return access\.admin \|\| access\.permissions\.has\('server'\))\n\}/,
  'who runs deadwax')[1])

const words = {
  title: piece(PAGE, /<h1 class="pl-large-title">([^<]+)<\/h1>/, 'the title')[1],
  pageLine,
  reading: piece(PAGE, /<div class="pl-spinner" aria-label="([^"]+)" \/>/, 'reading')[1],
  readFailed: "Couldn't read the settings.",
  rereadFailed: "Couldn't read the settings again just now.",
  saveFailed: "Couldn't save the settings.",
  tryAgain: piece(PAGE, /onClick=\{\(\) => !loading && read\(\)\}>\n\s*([^\n<]+)\n/, 'Try again')[1],
  discard: piece(PAGE, /onClick=\{\(\) => !saving && discard\(\)\}>\n\s*([^\n<]+)\n/, 'Discard')[1],
  saving: piece(PAGE, /\{saving \? '([^']+)' : '([^']+)'\}/, 'Save')[1],
  save: piece(PAGE, /\{saving \? '([^']+)' : '([^']+)'\}/, 'Save')[2],
  attentionTitle: piece(PAGE, /<span class="app-settings-mark is-attention" title="([^"]+)" \/>/, "a tab's attention mark")[1],
  unsavedTitle: piece(PAGE, /<span class="app-settings-mark" title="([^"]+)" \/>/, "a tab's unsaved mark")[1],
  tabs: S.SERVER_TABS,
  locked: 'Locked',
  unsaved: 'Unsaved',
  needsAttention: 'Needs attention',
  setHere: 'Set here',
  revert: revertLabelOf({ env_value: null }),
  willRevert,
  organizingOn: verdictOf({ enabled: true }),
  organizingOff: verdictOf({ enabled: false }),
  savedAnswersGroup: MB.SAVED_ANSWERS_GROUP,
  savedAnswersPath: MB.SAVED_ANSWERS_PATH,
  //? Re-time saved lyrics
  retimeButton,
  retimeReading: runningLabelOf({ total: 0, done: 0 }),
  retimeSaveFirstHint: retimeTitles[1],
  retimeHint: retimeTitles[2] + retimeTitles[3],
  retimeReadFailed,
  retimeSaveFirst: retimeNoteOf(true, null, E.asSentence, L.describeRetime),
  retimePrompt: retimeNoteOf(false, null, E.asSentence, L.describeRetime),
  //? MusicBrainz's saved answers
  clear: clearLabelOf(false),
  clearing: clearLabelOf(true),
  answersReading: answersNoteOf(false, null, null, MB.describeSavedAnswers, false),
  answersSaveFirst: answersNoteOf(true, null, null, MB.describeSavedAnswers, false),
  answersReadFailed,
  answersClearFailed,
  clearSaveFirstHint: clearTitleOf(true, false, false),
  clearClearingHint: clearTitleOf(false, true, false),
  clearEmptyHint: clearTitleOf(false, false, true),
  clearHint: clearTitleOf(false, false, false),
  //? Connections
  connections: connectionsTitle,
  checkAgain,
  services,
  pending,
  connected: fromPingOf('slskd', { status: 'ok' }, E.pingWords).text,
  pingUnanswered: E.PING_UNANSWERED,
}

/* ===== the cases ===== */

const CHOICES = {
  SEARCH_COUNTRY: [['on', 'Only peers in your country'], ['off', 'Anywhere']],
  AUTO_RETRY: [['off', 'Off'], ['on', 'Move to the next source']],
  FETCH_LYRICS: [['on', 'Fetch them'], ['off', 'Never']],
  COVER_ART_SIZE: [['full', 'Full size'], ['1200', '1200 px'], ['250', '250 px'], ['500', '500 px']],
}
const GROUPS = [
  ['connections', 'Connections', 'Where deadwax finds slskd, MusicBrainz and Navidrome.', ['SLSKD_URL', 'SLSKD_APIKEY', 'MUSICBRAINZ_EMAIL', 'NAVIDROME_URL', 'NAVIDROME_USER', 'NAVIDROME_PASSWORD', 'FANART_API_KEY']],
  ['musicbrainz-cache', "MusicBrainz's saved answers", 'Kept on disk.', ['MUSICBRAINZ_CACHE_PATH', 'MUSICBRAINZ_CACHE_MB']],
  ['paths', 'Paths', '', ['LIBRARY_PATH', 'SLSKD_DOWNLOAD_PATH', 'DB_PATH']],
  ['organizing', 'Organizing', 'How a download is filed.', ['ALBUM_FOLDER_TEMPLATE']],
  ['soulseek', 'Soulseek searches', '', ['SEARCH_COUNTRY', 'SLSKD_SEARCH_TIMEOUT']],
  ['downloads', 'When a download fails', '', ['AUTO_RETRY']],
  ['cover-art', 'Cover art', '', ['COVER_ART_SIZE']],
  ['lyrics', 'Lyrics', 'From LRCLIB.', ['FETCH_LYRICS', 'LYRICS_LEAD_MS']],
  ['logins', 'Logins', 'Read only.', ['AUTH_MODE', 'DEADWAX_ADMIN_PASSWORD']],
  ['experiments', 'Something new', 'A group this doesn\'t know.', ['NEW_THING']],
]
const SECRETS = new Set(['SLSKD_APIKEY', 'NAVIDROME_PASSWORD', 'FANART_API_KEY', 'DEADWAX_ADMIN_PASSWORD'])
const LOCKED = { DB_PATH: 'The database the overrides live in - it can only be set in the environment.', AUTH_MODE: 'Set in compose: it decides who signs in.' }
const VALUES = {
  SLSKD_URL: ['http://slskd:5030', 'http://192.168.1.20:5030', '', ' http://slskd:5030 '],
  NAVIDROME_URL: ['http://navidrome:4533', 'http://192.168.1.20:4533', '', 'http://navidrome:4533 '],
  NAVIDROME_USER: ['james', ''],
  MUSICBRAINZ_EMAIL: ['me@example.com', ''],
  MUSICBRAINZ_CACHE_PATH: ['/config/musicbrainz.db', '/data/mb.db'],
  MUSICBRAINZ_CACHE_MB: ['256', '0', '1024'],
  LIBRARY_PATH: ['/music', '/mnt/Björk', ''],
  SLSKD_DOWNLOAD_PATH: ['/downloads', ''],
  DB_PATH: ['/config/deadwax.db'],
  ALBUM_FOLDER_TEMPLATE: ['{artist}/{album} ({year})', '{album}'],
  SEARCH_COUNTRY: ['on', 'off', 'sometimes', ''],
  SLSKD_SEARCH_TIMEOUT: ['30', '60'],
  AUTO_RETRY: ['off', 'on'],
  COVER_ART_SIZE: ['1200', 'full', '250', '640'],
  FETCH_LYRICS: ['on', 'off'],
  LYRICS_LEAD_MS: ['0', '250', '-150'],
  AUTH_MODE: ['on', 'off'],
  NEW_THING: ['yes', ''],
}
const DETAILS = ['not a directory', "slskd answered 401: the API key isn't right", 'Can\'t write here: Björk', 'unset - organizing needs it']

function settingOf(key) {
  const secret = SECRETS.has(key)
  const locked = key in LOCKED
  const overridden = !locked && chance(0.3)
  const status = chance(0.15) ? 'error' : chance(0.2) ? 'unset' : 'ok'
  const value = secret ? (chance(0.6) ? 'set' : null) : chance(0.1) ? null : pick(VALUES[key] ?? ['x'])
  const setting = {
    key, value, source: pick([null, 'the container environment', '.env', '']), status,
    detail: status === 'ok' ? (chance(0.1) ? '' : null) : pick([...DETAILS, null]),
    effect: `What ${key} does.`, required: chance(0.3), secret, editable: !locked && !(chance(0.05)),
    locked_reason: locked ? LOCKED[key] : chance(0.05) ? 'Only an admin can change this.' : null,
    overridden, env_value: secret ? null : overridden ? pick([...(VALUES[key] ?? ['y']), null, '']) : null,
    choices: null,
  }
  if (secret) setting.env_set = chance(0.6)
  if (CHOICES[key]) setting.choices = Object.fromEntries(chance(0.5) ? CHOICES[key] : [...CHOICES[key]].reverse())
  return setting
}

function answerOf() {
  const groups = GROUPS.filter(() => chance(0.85)).map(([id, label, note, keys]) => ({ id, label, note, settings: keys.filter(() => chance(0.9)).map(settingOf) }))
  const blockers = chance(0.3) ? pick([['LIBRARY_PATH is not set'], ['SLSKD_DOWNLOAD_PATH is not set', 'the two folders overlap']]) : []
  return { version: '2.1.33', editable: false, groups, organizing: { enabled: blockers.length === 0 ? !chance(0.1) : false, blockers } }
}

/** Drafts as the web's object holds them, made in a random order - as pairs, so the order is kept. */
function draftsFor(answer) {
  const keys = answer.groups.flatMap((group) => group.settings.map((setting) => setting.key))
  const drafts = {}
  const count = pick([0, 0, 1, 2, 3, 5])
  for (let n = 0; n < count; n++) {
    const key = chance(0.1) ? 'NOT_A_SETTING' : chance(0.5) ? pick(['NAVIDROME_URL', 'NAVIDROME_PASSWORD', 'SLSKD_URL', 'SLSKD_APIKEY', 'LYRICS_LEAD_MS', 'MUSICBRAINZ_CACHE_PATH']) : pick(keys.length ? keys : ['X'])
    drafts[key] = chance(0.25) ? null : pick([...(VALUES[key] ?? ['']), 'typed', '', '  ', 'hunter2'])
  }
  return drafts
}
const pairs = (object) => Object.entries(object)

const answers = []
for (let n = 0; n < 40; n++) answers.push(answerOf())
//? choices in every order JSON can hold them: array-index keys first, ascending, then the rest as written
const orderBodies = []
for (const written of [
  [['full', 'Full size'], ['1200', '1200 px'], ['250', '250 px'], ['500', '500 px']],
  [['off', 'Never'], ['on', 'Fetch them']],
  [['b', 'B'], ['10', 'ten'], ['a', 'A'], ['2', 'two'], ['01', 'oh-one'], ['-1', 'minus one'], ['1.5', 'one and a half'], ['4294967295', 'too big'], ['4294967294', 'last index'], ['0', 'zero']],
  [['x', 'first'], ['y', 'second'], ['x', 'again']],
  [],
]) {
  const body = `{"version":"2.1.33","editable":false,"groups":[{"id":"cover-art","label":"Cover art","note":"","settings":[{"key":"COVER_ART_SIZE","value":"1200","source":null,"status":"ok","detail":null,"effect":"e","required":false,"secret":false,"editable":true,"locked_reason":null,"overridden":false,"env_value":null,"choices":{${written.map(([k, v]) => `${JSON.stringify(k)}:${JSON.stringify(v)}`).join(',')}}}]}],"organizing":{"enabled":true,"blockers":[]}}`
  const parsed = JSON.parse(body)
  orderBodies.push({ body, choices: Object.entries(parsed.groups[0].settings[0].choices) })
}

const pages = answers.map((answer, index) => {
  const drafts = draftsFor(answer)
  const settings = answer.groups.flatMap((group) => group.settings)
  return {
    answer: index, drafts: pairs(drafts), marks: S.tabMarks(answer, drafts),
    rows: settings.map((setting) => rowOf(setting, answer, drafts)),
    groups: answer.groups.map((group) => ({ id: group.id, tab: S.tabForGroup(group.id) })),
    savedKeys: answer.groups.map((group) => MB.savedAnswersKey(group)),
    verdict: verdictOf(answer.organizing),
  }
})
pages.push({ answer: null, drafts: [['LIBRARY_PATH', '/x'], ['NOT_A_SETTING', null]], marks: S.tabMarks(null, { LIBRARY_PATH: '/x', NOT_A_SETTING: null }), rows: [], groups: [], savedKeys: [], verdict: null })

const groupTabs = ['connections', 'logins', 'musicbrainz-cache', 'downloads', 'soulseek', 'paths', 'organizing', 'cover-art', 'lyrics', '', 'experiments', 'Connections', 'soulseek ', 'Downloads']
  .map((id) => ({ id, tab: S.tabForGroup(id) }))

//? the secret's note, under drafts made to reach every branch
const retype = []
const ADDRESSES = ['http://navidrome:4533', ' http://navidrome:4533 ', 'http://other:4533', '', '  ', null]
for (let n = 0; n < 160; n++) {
  const answer = answers[n % answers.length]
  const [secret, address] = pick([['NAVIDROME_PASSWORD', 'NAVIDROME_URL'], ['SLSKD_APIKEY', 'SLSKD_URL']])
  const drafts = {}
  if (chance(0.3)) drafts.LYRICS_LEAD_MS = '100'
  const typed = pick([...ADDRESSES, undefined])
  if (typed !== undefined) drafts[address] = typed
  const secretTyped = pick([undefined, undefined, null, '', ' ', 'hunter2'])
  if (secretTyped !== undefined) drafts[secret] = secretTyped
  for (const key of [secret, 'LIBRARY_PATH']) retype.push({ answer: n % answers.length, drafts: pairs(drafts), key, note: S.retypeSecretNote(key, answer, drafts) })
}
//? an answer whose address is overridden, the environment's given: a revert against it, both ways
for (const [overridden, envValue, value] of [[true, 'http://env:4533', 'http://here:4533'], [true, null, 'http://here:4533'], [false, null, 'http://env:4533'], [true, ' http://env:4533', 'http://env:4533 ']]) {
  for (const envSet of [true, false, undefined]) {
    const answer = { groups: [{ id: 'connections', settings: [
      { key: 'NAVIDROME_URL', value, overridden, env_value: envValue, secret: false },
      { key: 'NAVIDROME_PASSWORD', value: 'set', secret: true, ...(envSet === undefined ? {} : { env_set: envSet }) },
    ] }], organizing: { enabled: true, blockers: [] } }
    answers.push(answer)
    const index = answers.length - 1
    for (const url of [undefined, null, 'http://env:4533', 'http://elsewhere:4533', '', ' http://env:4533 ']) {
      const drafts = { NAVIDROME_PASSWORD: null }
      if (url !== undefined) drafts.NAVIDROME_URL = url
      retype.push({ answer: index, drafts: pairs(drafts), key: 'NAVIDROME_PASSWORD', note: S.retypeSecretNote('NAVIDROME_PASSWORD', answer, drafts) })
    }
  }
}

//? an edit: a value typed back to the saved one is no change (but a secret's), and the order kept
const edited = []
for (let n = 0; n < 60; n++) {
  const current = {}
  for (const key of ['A', 'B', 'C', 'SECRET', 'D'].filter(() => chance(0.4))) current[key] = chance(0.2) ? null : pick(['1', '2', ''])
  const key = pick(['A', 'B', 'C', 'SECRET', 'D', 'E'])
  const value = pick(['1', '2', '', ' 1'])
  const committed = chance(0.15) ? undefined : { key, value: pick(['1', '2', '', null]), secret: key === 'SECRET' }
  edited.push({ current: pairs(current), key, value, committed: committed ?? null, result: pairs(S.editedEnvDraft(current, key, value, committed)) })
}
//? after a save: only what was sent, as it was sent, goes
const afterSave = []
for (let n = 0; n < 50; n++) {
  const sent = {}, current = {}
  for (const key of ['A', 'B', 'C', 'D'].filter(() => chance(0.5))) sent[key] = chance(0.2) ? null : pick(['1', '2', ''])
  for (const key of ['A', 'B', 'C', 'D', 'E'].filter(() => chance(0.5))) current[key] = key in sent && chance(0.6) ? sent[key] : chance(0.2) ? null : pick(['1', '2', '', '3'])
  afterSave.push({ current: pairs(current), sent: pairs(sent), left: pairs(S.draftsAfterSave(current, sent)) })
}

const bars = []
for (const saveError of [null, 'LIBRARY_PATH: not a directory', "deadwax didn't answer."]) {
  for (const justSaved of [false, true]) for (const dirty of [0, 1, 2, 7]) bars.push({ saveError, justSaved, dirty, text: barOf(saveError, justSaved, dirty) })
}

const ERRORS = [
  { status: 400, detail: 'LIBRARY_PATH: not a directory; SLSKD_URL: not an address' },
  { status: 400, detail: null },
  { status: 400, detail: '' },
  { status: 409, detail: 'Something else is saving.' },
  { status: 422, detail: 'body: Field required' },
  { status: 500, detail: null },
  { status: 503, detail: "the database isn't available, so settings can't be saved. Check DB_PATH points at a writable volume." },
  { status: 502, detail: null },
  { offline: 'Failed to fetch' },
  { offline: 'Load failed' },
  { timeout: 'signal timed out' },
  { other: 'Unexpected token < in JSON at position 0' },
]
const saveErrors = [], readErrors = []
for (const error of ERRORS) {
  for (const admin of [false, true]) {
    const sayError = (caught, lead, options) => E.noticeWords(lead, caught, { ...options, admin })
    saveErrors.push({ error, admin, said: saveErrorOf(madeError(error), ApiError, sayError) })
    const read = { ...error, method: 'GET', path: '/settings' }
    readErrors.push({ error: read, admin,
      first: E.noticeWords('', madeError(read), { failed: words.readFailed, retry: true, admin }),
      again: E.noticeWords('', madeError(read), { failed: words.rereadFailed, admin }) })
  }
}

const navidromeKeys = [[], ['NAVIDROME_URL'], ['LIBRARY_PATH', 'NAVIDROME_PASSWORD'], ['navidrome_url'], ['NAVIDROME'], ['NAVIDROME_'], [' NAVIDROME_URL'], ['SLSKD_URL', 'LYRICS_LEAD_MS']]
  .map((keys) => ({ keys, asks: asksNavidromeOf(keys) }))

//? MusicBrainz's saved answers: the size, the line, Clear
const bytes = [0, 1, 1023, 1024, 1536, 10239, 1048575, 1048576, 1572864, 5767168, 1073741824, 268435456]
  .map((count) => ({ bytes: count, words: MB.describeBytes(count) }))
const STATS = []
for (const problem of [null, '', "can't open /config/mb.db: Permission denied"]) {
  for (const enabled of [true, false]) {
    for (const [answers_, bytes_] of [[0, 0], [0, 12288], [1, 4096], [1234, 1572864], [1000000, 1073741824]]) {
      for (const limit of [256, 0.5]) STATS.push({ enabled, path: '/config/mb.db', bytes: bytes_, answers: answers_, limit_mb: limit, problem })
    }
  }
}
const saved = []
for (const stats of STATS) for (const cleared of [false, true]) saved.push({ stats, cleared, words: MB.describeSavedAnswers(stats, cleared) })
const clears = []
for (const stats of [null, STATS[0], STATS[6]]) {
  for (const clearing of [false, true]) for (const unsaved of [false, true]) for (const error of [null, "Couldn't clear MusicBrainz's saved answers."]) {
    for (const cleared of [false, true]) {
      const empty = emptyOf(stats)
      clears.push({ stats, clearing, unsaved, error, cleared, empty, refused: refusedOf(clearing, unsaved, empty),
        hint: clearTitleOf(unsaved, clearing, empty), label: clearLabelOf(clearing),
        note: answersNoteOf(unsaved, error, stats, MB.describeSavedAnswers, cleared) })
    }
  }
}

//? Re-time: its sentence, its running words, its note - and runs stepped album by album as the module steps them
const retimes = []
for (const totals of [
  { retimed: 0, unchanged: 0, custom: 0, failed: 0 }, { retimed: 1, unchanged: 0, custom: 0, failed: 0 },
  { retimed: 29, unchanged: 3, custom: 1, failed: 2 }, { retimed: 0, unchanged: 12, custom: 0, failed: 0 },
  { retimed: 2, unchanged: 0, custom: 5, failed: 0 }, { retimed: 0, unchanged: 0, custom: 0, failed: 14 },
]) retimes.push({ totals, words: L.describeRetime(totals) })
const labels = []
for (const [done, total] of [[0, 0], [0, 1], [0, 60], [13, 60], [59, 60], [60, 60]]) labels.push({ done, total, label: runningLabelOf({ done, total }) })
const notes = []
for (const unsaved of [false, true]) {
  for (const run of [null, { retimed: 0, unchanged: 0, custom: 0, failed: 0, total: 0, done: 0, running: true },
    { retimed: 3, unchanged: 1, custom: 0, failed: 0, total: 4, done: 4, running: false },
    { retimed: 3, unchanged: 1, custom: 2, failed: 1, total: 60, done: 14, running: false },
    { retimed: 0, unchanged: 0, custom: 0, failed: 0, total: 0, done: 0, running: false, error: "Couldn't read the library." }]) {
    notes.push({ unsaved, run, note: retimeNoteOf(unsaved, run, E.asSentence, L.describeRetime) })
  }
}
const runs = []
for (let n = 0; n < 30; n++) {
  const library = []
  for (let a = between(0, 9); a > 0; a--) library.push({ path: `Artist ${a}/Album ${a}`, lyrics_count: pick([0, 0, 1, 5, 12]) })
  const albums = library.filter((album) => album.lyrics_count > 0)
  const steps = albums.map((album) => chance(0.15) ? 'threw'
    : { retimed: between(0, album.lyrics_count), unchanged: between(0, 2), custom: between(0, 1), failed: between(0, 1) })
  const stopBefore = chance(0.3) ? between(0, albums.length) : null
  const leadMoved = chance(0.15)
  //? the module's loop, as it is: stop asked before each album, a throw counting every lyric of it failed
  const totals = { retimed: 0, unchanged: 0, custom: 0, failed: 0 }
  let done = 0
  let stop = false
  for (const album of albums) {
    if (stopBefore === done) stop = true
    if (stop) break
    const step = steps[done]
    if (step === 'threw') totals.failed += album.lyrics_count
    else for (const key of Object.keys(totals)) totals[key] += step[key]
    done += 1
  }
  const last = endedOf(leadMoved, { ...totals, total: albums.length, done, running: false })
  runs.push({ library, steps, stopBefore, leadMoved, run: last, note: retimeNoteOf(false, last, E.asSentence, L.describeRetime) })
}

//? Connections: a ping's answer, Navidrome's status, an ask that failed
const pings = []
for (const service of ['musicbrainz', 'slskd']) {
  for (const answer of [
    { status: 'ok' }, { status: 'OK' }, { status: 'Ok', code: 'X' }, {},
    { status: 'failed', code: 'VALUE_ERROR', error: 'No contact is set.' },
    { status: 'failed', code: 'UNKNOWN_HTTP_ERROR', error: null },
    { status: 'failed', code: 401, error: "slskd answered 401: the API key isn't right." },
    { status: 'failed', code: 409, error: '' },
    { status: 'failed', code: 'NOT_LOGGED_IN', error: 'slskd is not logged in to Soulseek.' },
    { status: 'failed', code: 'CONNECTION_ERROR', error: "Couldn't reach slskd at http://slskd:5030." },
    { status: 'failed', code: null, error: null },
    { status: 'failed' },
    { status: 'down', code: 'TIMEOUT', error: 'MusicBrainz took too long.' },
  ]) pings.push({ service, answer, check: fromPingOf(service, answer, E.pingWords) })
}
const navidrome = []
for (const status of [
  { configured: true, ok: true, server: 'Navidrome 0.64.2', problem: null },
  { configured: true, ok: true, server: '', problem: null },
  { configured: true, ok: true, server: null, problem: null },
  { configured: true, ok: false, server: null, problem: "Navidrome answered 40: Wrong username or password" },
  { configured: true, ok: false, server: null, problem: '' },
  { configured: false, ok: false, server: null, problem: 'NAVIDROME_URL is not set.' },
  { configured: false, ok: false, server: null, problem: null },
]) navidrome.push({ status, check: fromNavidromeOf(status) })
const unanswered = []
for (const error of ERRORS.filter((one) => !('status' in one) || one.status >= 500)) {
  const spec = { ...error, method: 'GET', path: '/search_musicbrainz/ping' }
  unanswered.push({ error: spec, check: failedOf(E.PING_UNANSWERED, E.unansweredLine, madeError(spec)) })
}

//? who sees the page, and Connections on it: every set of permissions, and an admin
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
  about: "Server settings (lib/serverSettings.ts, lib/musicbrainzAnswers.ts, lib/lyrics.ts, lib/errorWords.ts, lib/permissions.ts and app/access.ts run as they are; app/ServerSettings.tsx's page, components/SettingsView.tsx's rows, components/RetimeLyrics.tsx's run, components/MusicBrainzAnswers.tsx's Clear, app/You.tsx's Connections and app/App.tsx's own, read out of their source). Each answer is a body as deadwax sends it.",
  made_by: MADE_BY,
  made_from: Object.fromEntries(Object.keys(madeFrom).sort().map((key) => [key, madeFrom[key]])),
  words,
  answers: answers.map((answer) => JSON.stringify(answer)),
  orders: orderBodies,
  groupTabs,
  pages,
  retype,
  edited,
  afterSave,
  bars,
  saveErrors,
  readErrors,
  navidromeKeys,
  bytes,
  saved,
  clears,
  retimes,
  labels,
  notes,
  runs,
  pings,
  navidrome,
  unanswered,
  permissions,
}
const LISTED = new Set(['answers', 'orders', 'groupTabs', 'pages', 'retype', 'edited', 'afterSave', 'bars', 'saveErrors', 'readErrors',
  'navidromeKeys', 'bytes', 'saved', 'clears', 'retimes', 'labels', 'notes', 'runs', 'pings', 'navidrome', 'unanswered', 'permissions'])
const body = [
  '{',
  Object.entries(fixture).map(([key, value]) => LISTED.has(key)
    ? `  ${flat(key)}: [\n${value.map((row) => `    ${flat(row)}`).join(',\n')}\n  ]`
    : `  ${flat(key)}: ${flat(value)}`).join(',\n'),
  '}',
  '',
].join('\n')
const counted = `${answers.length} answers, ${pages.length} pages, ${retype.length} notes, ${runs.length} runs, ${pings.length} pings`
if (CHECK) {
  if (!fs.existsSync(FIXTURE) || fs.readFileSync(FIXTURE, 'utf8') !== body) {
    console.log(`Server settings' fixture differs from what the web app's TypeScript answers now: ${path.relative(REPO, FIXTURE)}.`)
    console.log(`Run node ${MADE_BY}, and see what the Swift port must follow.`)
    process.exit(1)
  }
  console.log(`Server settings' fixture matches the web app's TypeScript (${counted}).`)
} else {
  fs.mkdirSync(path.dirname(FIXTURE), { recursive: true })
  fs.writeFileSync(FIXTURE, body)
  console.log(`Wrote ${path.relative(REPO, FIXTURE)}: ${counted}, ${Math.round(body.length / 1024)} KB`)
}
