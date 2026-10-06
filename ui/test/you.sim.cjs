/**
 * The app's You tab (app/You.tsx, 2.0.0-player.9), the component itself, compiled with the repo's
 * TypeScript and rendered by a small stand-in for Preact into plain objects, with deadwax's
 * answers faked.
 *
 * What it pins:
 *
 *  - Nothing is asked until You first shows (the MusicBrainz ping is a real request to a
 *    rate-limited service), then the pings and /deadwax/me together.
 *  - "Check again" asks /deadwax/me again, not only the pings. deadwax restarting under Komodo
 *    while You first opened used to leave Version and Logins at "unknown" until the app was
 *    killed - the latch CLAUDE.md warns about. A failure clears as the new ask begins; a failed
 *    ask after a good one keeps the version, and says it failed.
 *  - The identity line says only what deadwax has said: not "Logins are off" when it hasn't
 *    answered.
 *  - Each connection row is a live region of its own, read whole, so VoiceOver hears "slskd,
 *    NOT_LOGGED_IN", not a bare word with no service - and the list itself is not one.
 *  - The link to the main page opens beside the app.
 *  - On a desktop (2.0.0-player.25), "Albums that need a look" in Managing, with its count (none
 *    drawn while it isn't known), above that link and going to the queue's page; on a phone no row.
 *  - Playback holds Gapless, then "Now Playing opens as" (2.0.0-player.11), then Maximum quality:
 *    Gapless is handed the player itself - the object whose setGapless its tap calls - the look
 *    the setting App keeps and App's way to change it, and the notes say where the button that
 *    switches looks is, where the settings are kept and when each applies, with no pointer to the
 *    now-playing screen.
 *  - Getting albums (2.0.0-player.15) comes first, as the board has it: "When I tap Get" and
 *    "Quality floor" (app/GettingChoices.tsx), handed the server's settings (app/useGetSettings.ts,
 *    asked each time You's tab is opened and again on "Check again") and the way to change them;
 *    nothing can be chosen, or reads as chosen, until deadwax has answered; the words are the
 *    board's; the note says the two are kept for you on deadwax, not on the device; a database that
 *    can't keep them, and a save that failed, are said - the latter in a live region always there.
 *    The store itself (app/useGetSettings.ts, the real one, against a faked deadwax): one ask at a
 *    time, the defaults until it answers; a user nothing was ever saved for (`seeded` false), on a
 *    database that can keep it, seeded once from this browser's main-page preferences - only what
 *    differs from the defaults, an empty save when nothing does - never when seeded or nothing can
 *    be kept; an answer in hand asked AGAIN (a change made on another device arrives), standing
 *    meanwhile, and a read never putting back a choice still being saved; a choice shown at once,
 *    saved behind it, and put back - saying so - when deadwax won't keep it, to what the server
 *    holds; saves one at a time, in the order chosen, so an answer for an older choice never shows
 *    over a newer one, and a refused older choice goes back without taking a newer one with it.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/you.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-you-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/You.tsx', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor, as Preact's are - the same stand-in as
//? settings.sim.cjs. Effects run after a render whose deps changed.
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => {
    const outer = current; current = root; root.cursor = 0
    try { return component(props) } finally { current = outer }
  }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  return render
}
`)

/* ===== deadwax, faked: each answer is what the test says next ===== */

const asked = { me: 0, musicbrainz: 0, slskd: 0, navidrome: 0 }
const meAnswers = []
fs.writeFileSync(path.join(OUT, 'api/me.js'), `
exports.me = () => globalThis.__you.me()
`)
fs.writeFileSync(path.join(OUT, 'api/connections.js'), `
exports.pingMusicBrainz = () => globalThis.__you.ping('musicbrainz')
exports.pingSlskd = () => globalThis.__you.ping('slskd')
`)
fs.writeFileSync(path.join(OUT, 'player/api.js'), `
exports.navidromeStatus = () => globalThis.__you.ping('navidrome')
`)
fs.writeFileSync(path.join(OUT, 'app/useGetSettings.js'), `
exports.useGetSettings = (ask) => { globalThis.__you.gettingAsked.push(ask); return globalThis.__you.getting }
exports.askGetSettings = () => { globalThis.__you.gettingAsks += 1; return Promise.resolve() }
exports.chooseGetSettings = (values) => { globalThis.__you.chosen.push(values); return Promise.resolve() }
`)
fs.writeFileSync(path.join(OUT, 'app/context.js'), `
exports.usePlayerState = () => globalThis.__you.player
exports.usePlayerActions = () => ({ setMaxRate() {} })
`)
const ANSWERS = {
  musicbrainz: { status: 'ok' },
  slskd: { status: 'failed', code: 'NOT_LOGGED_IN', error: 'slskd is not logged in to Soulseek' },
  navidrome: { configured: true, ok: true, server: 'Navidrome 0.64.2', problem: null },
}
globalThis.__you = {
  player: { maxRate: '48000', gapless: false, setGapless() {} },
  //? Getting albums: what the store says, what it was asked, and what was chosen
  getting: { settings: { get_mode: 'sources', quality_floor: 'lossless' }, canSave: true, problem: null },
  gettingAsked: [],
  gettingAsks: 0,
  chosen: [],
  me() {
    asked.me += 1
    const next = meAnswers.shift()
    return next ? next() : new Promise(() => {})
  },
  ping(service) {
    asked[service] += 1
    return Promise.resolve(ANSWERS[service])
  },
}
const ME = { user: 'local', admin: true, auth: 'off', version: '2.0.0-player.9' }
//? "Now Playing opens as", as App hands it to You: the setting, and the way to change it
const chosenLooks = []
const chosenWindDowns = []
const LOOK = { opensAs: 'turntable', onOpensAs: (look) => chosenLooks.push(look), windDown: true, onWindDown: (on) => chosenWindDowns.push(on) }
const answersWith = (value) => () => Promise.resolve(value)
const failsWith = (words) => () => Promise.reject(new Error(words))

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/* ===== rendering ===== */

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { You } = require(path.join(OUT, 'app/You.js'))

const render = hooks.root(You)
let tree = null
const draw = (props) => {
  tree = render(props)
  render.commit()
  return tree
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

//? every node of the tree drawn last that passes `test` (no default for the node: an undefined
//? child would take it, and walk the whole tree again)
function find(test) {
  const hits = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (test(node)) hits.push(node)
    visit(node.props?.children)
  }
  visit(tree)
  return hits
}
function text(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(text).join('')
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''  // a component, not drawn here
  return text(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
//? About's rows, as label -> value: each a <div class="app-row"> holding a <dt> and a <dd>
const about = () => Object.fromEntries(find((node) => node.type === 'div' && node.props?.class === 'app-row')
  .map((row) => [text(row.props.children[0]), text(row.props.children[1])]))
const identity = () => find(byClass('app-identity-sub')).map(text)
const failure = () => find(byClass('app-error')).map(text)
const checkAgain = () => find((node) => node.type === 'button' && text(node) === 'Check again')[0]

async function main() {
  console.log('\nnothing is asked until You first shows')
  draw({ shown: false, current: false, ...LOOK })
  await settle()
  check('hidden, never opened: no ping, no /me', asked, { me: 0, musicbrainz: 0, slskd: 0, navidrome: 0 })

  console.log('\n/deadwax/me asked with the pings, and asked again')
  meAnswers.push(failsWith('deadwax is restarting'))
  draw({ shown: true, current: true, ...LOOK })
  check('shown: /me and the three pings, once each', asked, { me: 1, musicbrainz: 1, slskd: 1, navidrome: 1 })
  await settle()
  draw({ shown: true, current: true, ...LOOK })
  check('/me failed: the version and logins say they are not known', about(), { Version: 'unknown', Logins: 'unknown' })
  check('...the failure is said', failure(), ["deadwax didn't answer: deadwax is restarting"])
  check('...and the identity line claims nothing', identity(), [])
  check('drawn again, nothing is asked again by itself', asked.me, 1)

  meAnswers.push(answersWith(ME))
  checkAgain().props.onClick()
  check('"Check again" asks /me again, with the pings', asked, { me: 2, musicbrainz: 2, slskd: 2, navidrome: 2 })
  draw({ shown: true, current: true, ...LOOK })
  check('...the old failure cleared as the ask begins', [failure(), about().Version], [[], '…'])
  await settle()
  draw({ shown: true, current: true, ...LOOK })
  check('deadwax back: the version and logins, and nothing failed', [about(), failure()], [{ Version: '2.0.0-player.9', Logins: 'Off' }, []])
  check('...and the identity line says what deadwax said', identity(), ['Logins are off'])

  meAnswers.push(failsWith('no answer'))
  checkAgain().props.onClick()
  await settle()
  draw({ shown: true, current: true, ...LOOK })
  check('a failed ask after a good one keeps the version, and says it failed', [about().Version, failure()], ['2.0.0-player.9', ["deadwax didn't answer: no answer"]])

  console.log('\neach connection row is read whole')
  const list = find((node) => node.type === 'ul' && byClass('app-group')(node))[0]
  const rows = find((node) => node.type === 'li' && byClass('app-status-row')(node))
  check('the list itself is no live region', list?.props['aria-live'] ?? null, null)
  check('every row is one, polite and atomic', rows.map((row) => [row.props['aria-live'], row.props['aria-atomic']]), [['polite', 'true'], ['polite', 'true'], ['polite', 'true']])
  check('...holding its service with its answer', rows.map(text), [
    'MusicBrainzConnected',
    'slskdNOT_LOGGED_INslskd is not logged in to Soulseek',
    'NavidromeNavidrome 0.64.2',
  ])

  console.log('\nPlayback: Gapless, then Now Playing opens as, then Pause winds the record down, then Maximum quality')
  const named = (name) => find((node) => typeof node.type === 'function' && node.type.name === name)
  const playback = find((node) => node.type === 'section' && node.props?.['aria-labelledby'] === 'app-playback-title')[0]
  const inPlayback = []
  const notes = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (typeof node.type === 'function') inPlayback.push(node.type.name)
    if (node.type === 'p' && byClass('app-footnote')(node)) notes.push(text(node))
    visit(node.props?.children)
  }
  visit(playback)
  check('all four in the Playback section: Gapless, then Now Playing opens as, then Pause winds the record down - beside it - then Maximum quality',
    inPlayback, ['GaplessChoice', 'LookChoice', 'WindDownChoice', 'QualityChoice'])
  check('Gapless is handed the player itself', named('GaplessChoice')[0]?.props.player === globalThis.__you.player, true)
  const look = named('LookChoice')[0]
  look?.props.onChange('cover')
  check('Now Playing opens as is handed App\'s setting, and App\'s way to change it', [look?.props.look, chosenLooks], ['turntable', ['cover']])
  const winds = named('WindDownChoice')[0]
  winds?.props.onChange(false)
  check('Pause winds the record down is handed App\'s setting, and App\'s way to change it', [winds?.props.on, chosenWindDowns], [true, [false]])
  check('the notes: what Gapless does, where the button is, what winding down does, and where all four are kept', notes, [
    'An experiment: it shortens the pause between songs, and FLAC songs played one after another can join in one stream, with none at all.',
    'The button at the top right of Now Playing switches between them until it closes.',
    "The turntable only: pausing from it slows the record's sound to a stop over about a second, as a real deck does. Off, it stops at once. The cover's pause is always instant.",
    'All four are kept on this device. Maximum quality is used from the next song.',
  ])
  check('...the wind-down\'s note is what its checkbox is described by: the one note by that id',
    find((node) => node.props?.id === 'app-wind-down-note').map(text).length, 1)
  check('...the first is what the checkbox is described by', find((node) => node.props?.id === 'app-gapless-note').map(text).length, 1)
  check('...the second what the looks are: the one note by that id, the button\'s',
    find((node) => node.props?.id === 'app-look-note').map(text), ['The button at the top right of Now Playing switches between them until it closes.'])

  console.log('\nGetting albums: first, kept on deadwax, chosen only once deadwax has answered')
  {
    const sections = find((node) => node.type === 'section' && byClass('app-section')(node)).map((node) => node.props['aria-labelledby'])
    check('the first section, before Playback, as the board has it', sections.slice(0, 2), ['app-getting-title', 'app-playback-title'])
    check('the settings asked with You: not while it was never shown, then once it is', [globalThis.__you.gettingAsked[0], globalThis.__you.gettingAsked.at(-1)], [false, true])
    const asksBefore = globalThis.__you.gettingAsks
    checkAgain().props.onClick()
    check('"Check again" asks for them again too', globalThis.__you.gettingAsks, asksBefore + 1)
    draw({ shown: true, current: false, ...LOOK })
    draw({ shown: true, current: true, ...LOOK })
    check('...and the tab opened again asks again - a change made on another device shows', globalThis.__you.gettingAsked.slice(-2), [false, true])
    const choices = named('GettingChoices')[0]
    check('GettingChoices is handed the server\'s settings', choices?.props.settings, { get_mode: 'sources', quality_floor: 'lossless' })
    choices?.props.onChoose({ get_mode: 'pick' })
    check('...and a choice goes to the store, which saves it on deadwax', globalThis.__you.chosen, [{ get_mode: 'pick' }])
    check('the note says what picking does, what the floor does, and where both are kept',
      find((node) => node.props?.id === 'app-get-note').map(text),
      ['With “Pick the best source for me”, Get takes the best match that passes your quality floor, and shows you the sources when nothing matches well. The floor is also what the sources start filtered by. Both are kept for you on deadwax, not on this device.'])
    check('nothing failed, nothing said', failure().filter((line) => !line.startsWith("deadwax didn't answer")), [])
    //? the connection rows are live regions too, but list items; this one is the section's own div
    const problemRegion = () => find((node) => node.type === 'div' && node.props?.['aria-live'] === 'polite' && node.props?.['aria-atomic'] === 'true')
    check('a save\'s failure has a live region always in the page, empty while nothing failed', [problemRegion().length, text(problemRegion()[0])], [1, ''])
    globalThis.__you.getting = { settings: null, canSave: false, problem: 'Not saved: the database is locked' }
    draw({ shown: true, current: true, ...LOOK })
    check('a database that can\'t keep them, and a save that failed, are said', failure().filter((line) => !line.startsWith("deadwax didn't answer")),
      ["deadwax can't keep these: its database isn't writable.", 'Not saved: the database is locked'])
    check('...the failure inside that region, so VoiceOver hears why the choice went back', text(problemRegion()[0]), 'Not saved: the database is locked')
    globalThis.__you.getting = { settings: { get_mode: 'sources', quality_floor: 'lossless' }, canSave: true, problem: null }
    draw({ shown: true, current: true, ...LOOK })

    //? the two radio groups, drawn: GettingChoices is a leaf, and its groups are components of their own
    const { GettingChoices } = require(path.join(OUT, 'app/GettingChoices.js'))
    const picks = []
    const groupsOf = (settings) => {
      const drawn = GettingChoices({ settings, onChoose: (values) => picks.push(values) })
      return drawn.props.children.map((group) => group.type(group.props))
    }
    const radios = (group) => {
      const found = []
      const visit = (node) => {
        if (!node || typeof node !== 'object') return
        if (Array.isArray(node)) { node.forEach(visit); return }
        if (node.props?.role === 'radio') found.push(node)
        visit(node.props?.children)
      }
      visit(group)
      return found
    }
    const groupOf = (group) => group.props.children.find((child) => child?.props?.role === 'radiogroup')
    const [mode, floor] = groupsOf({ get_mode: 'pick', quality_floor: 'lossless' })
    check('the titles and the words, as the board has them',
      [text(mode.props.children[0]), radios(mode).map((radio) => text(radio)), text(floor.props.children[0]), radios(floor).map((radio) => text(radio))],
      ['When I tap Get', ['Show me the sources', 'Pick the best source for me'], 'Quality floor', ['Any', '320 kbps', 'Lossless', '24-bit']])
    check('the chosen ones checked, and the only tab stops', [radios(mode).map((r) => [r.props['aria-checked'], r.props.tabIndex]), radios(floor).map((r) => [r.props['aria-checked'], r.props.tabIndex])],
      [[[false, -1], [true, 0]], [[false, -1], [false, -1], [true, 0], [false, -1]]])
    radios(mode)[0].props.onClick()
    groupOf(floor).props.onKeyDown({ key: 'ArrowDown', preventDefault() {}, currentTarget: { querySelector: () => null } })
    check('a tap picks; an arrow moves the choice round the group', picks, [{ get_mode: 'sources' }, { quality_floor: '24bit' }])
    const [waitingMode, waitingFloor] = groupsOf(null)
    radios(waitingMode)[1].props.onClick()
    groupOf(waitingFloor).props.onKeyDown({ key: 'ArrowDown', preventDefault() {}, currentTarget: { querySelector: () => null } })
    check('before deadwax has answered: nothing checked, busy, the first a tab stop, and nothing can be chosen',
      [radios(waitingMode).map((r) => r.props['aria-checked']), groupOf(waitingMode).props['aria-busy'], radios(waitingFloor).map((r) => r.props.tabIndex), picks.length],
      [[false, false], true, [0, -1, -1, -1], 2])
    check('both groups are described by the section\'s note', [groupOf(mode).props['aria-describedby'], groupOf(floor).props['aria-describedby']], ['app-get-note', 'app-get-note'])
  }

  console.log('\nthe store of Getting albums (app/useGetSettings.ts, the real one)')
  {
    const OUT2 = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-getting-'))
    execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
      'src/app/useGetSettings.ts', '--rootDir', 'src', '--outDir', OUT2,
      '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
      '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
    ], { cwd: UI, stdio: 'inherit' })
    fs.mkdirSync(path.join(OUT2, 'node_modules/preact'), { recursive: true })
    fs.writeFileSync(path.join(OUT2, 'node_modules/preact/hooks.js'), 'exports.useState = () => [0, () => {}]\nexports.useEffect = () => {}\n')
    fs.writeFileSync(path.join(OUT2, 'api/me.js'), `
exports.getPreferences = () => globalThis.__getting.get()
exports.putPreferences = (values) => globalThis.__getting.put(values)
`)
    fs.writeFileSync(path.join(OUT2, 'state/persisted.js'), `
exports.readPreferences = () => globalThis.__getting.preferences
`)
    //? deadwax, faked: what it stores (and whether anything was ever saved), each GET and PUT. With
    //? `hold`, a PUT waits for the test to let it in: it is taken - and answered - when released
    const server = { stored: {}, seeded: false, canSave: true, refuse: false, hold: false, gets: 0, puts: [], held: [] }
    const answerOf = () => ({ get_mode: server.stored.get_mode ?? 'sources', quality_floor: server.stored.quality_floor ?? 'any', stored: Object.keys(server.stored).sort(),
      seeded: server.seeded, can_save: server.canSave })
    const take = (values) => {
      if (!server.canSave || server.refuse) throw new Error("deadwax can't keep preferences: its database isn't writable")
      Object.assign(server.stored, values)
      server.seeded = true
      return answerOf()
    }
    globalThis.__getting = {
      preferences: { candidateMinBitrate: 0, candidateMinBitDepth: 24 },
      get() { server.gets += 1; return Promise.resolve(answerOf()) },
      put(values) {
        server.puts.push(values)
        if (server.hold) {
          return new Promise((resolve, reject) => server.held.push({ values, let: (refuse) => {
            try { if (refuse) throw new Error('the database is locked'); resolve(take(values)) } catch (error) { reject(error) }
          } }))
        }
        try { return Promise.resolve(take(values)) } catch (error) { return Promise.reject(error) }
      },
    }
    const G = require(path.join(OUT2, 'app/useGetSettings.js'))
    const fresh = (stored = {}, seeded = Object.keys(stored).length > 0) => { G.forgetGetSettings(); server.stored = { ...stored }; server.seeded = seeded; server.puts = []; server.gets = 0 }
    const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

    check('before deadwax answers: the defaults - a Get shows the sources', G.getSettingsNow(), { get_mode: 'sources', quality_floor: 'any' })
    const one = G.askGetSettings()
    const two = G.askGetSettings()
    await settle()
    check('one ask at a time', [one === two, server.gets], [true, 1])
    await one
    check('a first read of a user nothing was saved for carries the main page\'s floor over (bit depth 24: 24-bit) - and only that, never "When I tap Get"',
      [server.puts, G.getSettingsNow()], [[{ quality_floor: '24bit' }], { get_mode: 'sources', quality_floor: '24bit' }])
    await G.askGetSettings()
    check('an answer in hand is asked again - a change made on another device must arrive - and seeds nothing more', [server.gets, server.puts.length], [2, 1])

    fresh()
    globalThis.__getting.preferences = { candidateMinBitrate: 0, candidateMinBitDepth: 0 }
    await G.askGetSettings()
    check('nothing to carry over: an empty save - no default stored as if chosen - which still marks the user seeded',
      [server.puts, server.stored, server.seeded], [[{}], {}, true])
    G.forgetGetSettings()
    globalThis.__getting.preferences = { candidateMinBitrate: 0, candidateMinBitDepth: 24 }
    await G.askGetSettings()
    check('...so the next page seeds nothing, whatever its main page says now', [server.puts.length, G.getSettingsNow().quality_floor], [1, 'any'])

    fresh({ quality_floor: '24bit' })
    globalThis.__getting.preferences = { candidateMinBitrate: 320, candidateMinBitDepth: 0 }
    await G.askGetSettings()
    check('a read with something stored seeds nothing - the server\'s are the settings', [server.puts.length, G.getSettingsNow().quality_floor], [0, '24bit'])

    fresh()
    server.canSave = false
    await G.askGetSettings()
    check('a database that can\'t keep them is never seeded', server.puts.length, 0)
    server.canSave = true

    console.log('\n  asked again: what another device changed arrives, and never over a choice being saved')
    fresh({ get_mode: 'sources', quality_floor: 'lossless' })
    await G.askGetSettings()
    server.stored.get_mode = 'pick'  // chosen on the desktop meanwhile
    check('...an answer in hand stands while the next is asked', [G.useGetSettings(false).settings?.get_mode, (G.askGetSettings(), G.getSettingsNow().get_mode)], ['sources', 'sources'])
    await G.askGetSettings()
    check('...then the server\'s word: picked on another device, picked here', G.getSettingsNow().get_mode, 'pick')
    server.hold = true
    const saving = G.chooseGetSettings({ get_mode: 'sources' })
    const reading = G.askGetSettings()
    await settle()
    check('a read asked while a choice is being saved waits its turn - the choice shows meanwhile', [server.gets, G.getSettingsNow().get_mode], [2, 'sources'])
    server.held.shift().let()
    await saving
    await reading
    check('...and, sent after the save, never puts the old value back', [server.gets, G.getSettingsNow().get_mode, server.stored.get_mode], [3, 'sources', 'sources'])
    server.hold = false

    console.log('\n  a choice: at once, saved behind it, put back when it isn\'t kept')
    fresh({ get_mode: 'sources', quality_floor: 'lossless' })
    await G.askGetSettings()
    const choosing = G.chooseGetSettings({ get_mode: 'pick' })
    check('a choice shows at once', G.getSettingsNow().get_mode, 'pick')
    await choosing
    check('...and is saved behind it', [server.puts.at(-1), server.stored.get_mode], [{ get_mode: 'pick' }, 'pick'])
    server.refuse = true
    await G.chooseGetSettings({ quality_floor: '320' })
    check('one deadwax won\'t keep goes back to what the server holds, and says so',
      [G.getSettingsNow().quality_floor, G.useGetSettings(false).problem], ['lossless', "Not saved: deadwax can't keep preferences: its database isn't writable"])
    server.refuse = false
    await G.chooseGetSettings({ quality_floor: '24bit' })
    check('...said until the next choice, which clears it', G.useGetSettings(false).problem, null)

    console.log('\n  quick choices: one save at a time, in the order chosen - newest wins (review)')
    fresh({ get_mode: 'sources', quality_floor: 'any' })
    await G.askGetSettings()
    server.hold = true
    const first = G.chooseGetSettings({ quality_floor: '320' })
    const second = G.chooseGetSettings({ quality_floor: 'lossless' })
    const third = G.chooseGetSettings({ quality_floor: '24bit' })
    await settle()
    check('three arrows at once: one save out, the others waiting - and the newest shows', [server.puts.length, G.getSettingsNow().quality_floor], [1, '24bit'])
    server.held.shift().let()
    await first
    check('the first answered: the newest still shows - an older answer never puts back an older choice', [server.puts.length, G.getSettingsNow().quality_floor], [2, '24bit'])
    server.held.shift().let()
    await second
    server.held.shift().let()
    await third
    check('...and the server ends where the screen does, having taken them in order', [server.stored.quality_floor, G.getSettingsNow().quality_floor, server.puts.map((put) => put.quality_floor)],
      ['24bit', '24bit', ['320', 'lossless', '24bit']])

    fresh({ get_mode: 'sources', quality_floor: 'any' })
    await G.askGetSettings()
    const mode = G.chooseGetSettings({ get_mode: 'pick' })
    const floor = G.chooseGetSettings({ quality_floor: 'lossless' })
    await settle()
    server.held.shift().let(true)
    await mode
    check('an older choice refused goes back - to the server\'s, saying so - and the newer one still shows',
      [G.getSettingsNow(), G.useGetSettings(false).problem], [{ get_mode: 'sources', quality_floor: 'lossless' }, 'Not saved: the database is locked'])
    server.held.shift().let()
    await floor
    check('...the newer one saved, and what was refused said still', [G.getSettingsNow(), server.stored, G.useGetSettings(false).problem],
      [{ get_mode: 'sources', quality_floor: 'lossless' }, { get_mode: 'sources', quality_floor: 'lossless' }, 'Not saved: the database is locked'])

    fresh({ get_mode: 'sources', quality_floor: 'any' })
    await G.askGetSettings()
    const kept = G.chooseGetSettings({ quality_floor: '320' })
    const refused = G.chooseGetSettings({ quality_floor: 'lossless' })
    await settle()
    server.held.shift().let()
    await kept
    server.held.shift().let(true)
    await refused
    check('the newest refused goes back to what the server holds - the older choice it kept - not to what showed before it',
      G.getSettingsNow().quality_floor, '320')
    server.hold = false
  }

  console.log('\nthe main page opens beside the app')
  const link = find((node) => node.type === 'a')[0]
  check('the Managing row links to / in a new tab, rel="noopener"', [link?.props.href, link?.props.target, link?.props.rel], ['/', '_blank', 'noopener'])

  console.log('\nNeeds a look (2.0.0-player.25): a desktop\'s row in Managing, never a phone\'s')
  {
    const row = () => find(byClass('app-queue-link-row'))[0]
    //? the nodes under one node that pass `test`
    const within = (node, test) => {
      const hits = []
      const visit = (at) => {
        if (!at || typeof at !== 'object') return
        if (Array.isArray(at)) { at.forEach(visit); return }
        if (test(at)) hits.push(at)
        visit(at.props?.children)
      }
      visit(node)
      return hits
    }
    const footnotes = () => find(byClass('app-footnote')).map(text)
    draw({ shown: true, current: true, ...LOOK })
    check('a phone: no row, and Managing\'s words as they were', [row(), footnotes().some((words) => words.includes('Server settings, albums that need a look, the log and editing an album'))], [undefined, true])
    const opened = []
    draw({ shown: true, current: true, ...LOOK, desktop: true, needsLook: 3, onNeedsLook: () => opened.push(true) })
    const order = find(byClass('app-link-row')).map(text)
    //? (2.0.0-player.33) Server settings and Log between it and the link to the main page
    check('a desktop: "Albums that need a look" with its count, above the link to the main page',
      [text(within(row(), byClass('app-row-label'))[0]), text(within(row(), byClass('app-queue-badge'))[0]), row().props['aria-label'], order[0].startsWith('Albums that need a look'), order[3]],
      ['Albums that need a look', '3', 'Albums that need a look, 3 albums', true, 'Open the main page'])
    row().props.onClick()
    check('...a tap goes to its page', opened, [true])
    check('...and the main page\'s footnote no longer says the queue is there', footnotes().some((words) => words.includes('albums that need a look')), false)
    draw({ shown: true, current: true, ...LOOK, desktop: true, needsLook: null, onNeedsLook: () => {} })
    check('the count not known: no badge drawn over it, the plain name read', [within(row(), byClass('app-queue-badge')).length, row().props['aria-label']], [0, undefined])
  }

  console.log('\nServer settings and Log (2.0.0-player.33): a desktop\'s rows in Managing, never a phone\'s')
  {
    const rows = () => find(byClass('app-link-row')).map(text)
    const footnotes = () => find(byClass('app-footnote')).map(text)
    draw({ shown: true, current: true, ...LOOK })
    check('a phone: neither row - only the link to the main page', rows(), ['Open the main page'])
    const opened = []
    draw({ shown: true, current: true, ...LOOK, desktop: true, needsLook: 2, onNeedsLook: () => {}, onManaging: (kind) => opened.push(kind) })
    check('a desktop: under "Albums that need a look", Server settings then Log, then the main page', rows().map((words) => words.replace(/\d+$/, '')),
      ['Albums that need a look', 'Server settings', 'Log', 'Open the main page'])
    const button = (words) => find((node) => node.type === 'button' && text(node) === words)[0]
    button('Server settings').props.onClick()
    button('Log').props.onClick()
    check('...each opening its page', opened, ['settings', 'log'])
    check('...and the footnote no longer says settings and the log are on the main page', footnotes().some((words) => /settings|the log/i.test(words)), false)
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main()
