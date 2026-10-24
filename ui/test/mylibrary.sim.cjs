/**
 * Personal libraries (2.0.0-player.51, step 5 of the multi-user plan): the words (lib/myLibrary.ts), the
 * app's store of your library (app/useMyLibrary.ts), You > Your library (app/YourLibrary.tsx) and Library
 * care > Held by nobody (app/HeldByNobody.tsx) - compiled with the repo's TypeScript and rendered by a small
 * stand-in for Preact into plain objects, with deadwax's answers faked. The delete dialog's holders line
 * and the Library tab's New mark are read off their source.
 *
 * What it pins:
 *
 *  - The words: your library's line ("12 albums · 2 waiting to be added", 2.0.5's words); a login Navidrome no longer
 *    takes said with "sign in again"; what waits grouped by why, the most first; an entry's name; who holds
 *    an album, for the delete dialog (nobody said too; nothing with logins off); the New marks by Navidrome
 *    id and by release (any case); Home's shelf - only what Navidrome has, as its albums; held by nobody's
 *    line; a flag's words.
 *  - The store: nothing asked with logins off or for the break-glass admin; asked through latestOnly (an
 *    older answer landing late draws nothing); an album opened that is new loses its mark at once and
 *    deadwax is told by its release, else - one reached by its address, only its Navidrome id known - by
 *    the store's ids; one that isn't new tells deadwax nothing.
 *  - You > Your library: nothing with logins off; the count, the login's words, what waits and why, an
 *    album an admin deleted with Get it again (its album page by the release group) and Dismiss
 *    (which asks again once deadwax has it); deadwax unable to read its database said.
 *  - Held by nobody: asked as the page shows, through latestOnly; the line, the albums (the first 20, then
 *    Show all), the flags with Add for them and Dismiss - each asking again once answered, a refusal said.
 *
 * A script for the same reason as the other sims: there is no JS test runner here.
 *
 * Run it with:  node ui/test/mylibrary.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-mylibrary-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/myLibrary.ts', 'src/app/useMyLibrary.ts', 'src/app/YourLibrary.tsx', 'src/app/HeldByNobody.tsx',
  '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - home.sim.cjs's stand-in
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
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
exports.useCallback = (f) => f
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => { const outer = current; current = root; root.cursor = 0; try { return component(props) } finally { current = outer } }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  return render
}
`)

//? deadwax, faked: every ask kept with its signal, answered when the test says
const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
write('api/me.js', `
exports.myLibrary = (signal) => globalThis.__lib.ask('library', signal)
exports.markLibrarySeen = (by) => { globalThis.__lib.seen.push(by); return Promise.resolve({ cleared: 1 }) }
exports.dismissRemoved = (albumId) => globalThis.__lib.ask('dismiss', null, albumId)
`)
write('api/library.js', `
exports.heldByNobody = (signal) => globalThis.__lib.ask('held', signal)
exports.addFlagged = (id) => globalThis.__lib.ask('add', null, id)
exports.dismissFlag = (id) => globalThis.__lib.ask('putflag', null, id)
`)
write('app/session.js', `exports.sessionMe = () => globalThis.__lib.me
//? (2.0.4) access.ts's word before /me answers - read by ErrorNote and the database lines (who runs deadwax)
exports.permissionsUntilAsked = () => new Set()
`)
write('lib/libraryEvents.js', `
exports.onAlbumsFiled = (listener) => { globalThis.__lib.filedListeners.push(listener); return () => {} }
exports.onAddedToLibrary = (listener) => { globalThis.__lib.addedListeners.push(listener); return () => {} }
exports.onRemovedFromLibrary = (listener) => { globalThis.__lib.removedListeners.push(listener); return () => {} }
`)

const L = globalThis.__lib = {
  me: null, asks: [], open: [], seen: [], filedListeners: [], addedListeners: [], removedListeners: [],
  ask(name, signal, ...args) {
    L.asks.push([name, ...args])
    let resolve, reject
    const promise = new Promise((yes, no) => { resolve = yes; reject = no })
    L.open.push({ name, signal, args, resolve, reject })
    return promise
  },
}
function answer(name, value) {
  const at = L.open.findIndex((one) => one.name === name)
  if (at < 0) throw new Error(`nothing asked of ${name}`)
  const [one] = L.open.splice(at, 1)
  if (value instanceof Error) one.reject(value)
  else one.resolve(value)
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

let failures = 0
let finished = false
process.on('exit', () => {
  if (!finished) {
    console.log('\nSTOPPED before the end - a check was left waiting')
    process.exitCode = 1
  }
})
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const W = require(path.join(OUT, 'lib/myLibrary.js'))
const store = require(path.join(OUT, 'app/useMyLibrary.js'))
const { YourLibrary } = require(path.join(OUT, 'app/YourLibrary.js'))
const { HeldByNobody, HELD_SHOWN } = require(path.join(OUT, 'app/HeldByNobody.js'))

function find(test, within) {
  const hits = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (test(node)) hits.push(node)
    visit(node.props?.children)
  }
  visit(within)
  return hits
}
function words(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const buttons = (tree) => find((node) => node.type === 'button', tree)

const entry = (id, album, more = {}) => ({ album_id: id, artist: 'Portishead', album, release_mbid: `rel-${id}`, release_group_mbid: `grp-${id}`,
  navidrome_id: null, added_at: '2026-10-15T09:00:00+00:00', how: 'grabbed', ...more })
const LIBRARY = {
  on: true, library: true, kept: true, count: 12, starred: 10, waiting: 2, incomplete: 1, login: 'ok', login_problem: null,
  waiting_albums: [
    { ...entry(3, 'Third'), problem: 'not_in_navidrome', words: "Navidrome hasn't got it yet (it may still be scanning) - deadwax asks again by itself." },
    { ...entry(4, 'Roseland NYC Live'), problem: 'no_release', words: 'It has no MusicBrainz release id, so deadwax can\'t find it in Navidrome - an admin can apply a release to it.' },
  ],
  new: [entry(1, 'Dummy', { navidrome_id: 'nd-dummy' }), entry(3, 'Third')],
  removed: [{ ...entry(9, 'Portishead'), removed_at: '2026-10-15T10:00:00+00:00' }],
}

async function run() {
  console.log('\nthe words')
  {
    check('your library\'s line', [W.libraryLine(LIBRARY), W.libraryLine({ ...LIBRARY, count: 1, waiting: 0 }), W.libraryLine({ on: true })],
      ['12 albums · 2 waiting to be added', '1 album', '0 albums'])
    check('a login Navidrome no longer takes: why, and sign in again', W.loginWords({ ...LIBRARY, login: 'dead', login_problem: 'Navidrome no longer accepts the login you signed in with - if you changed your Navidrome password, sign in with the new one.' }),
      //? (2.0.5) what the listener does, never the server's why (which names Navidrome and starring)
      "New albums can't be added to your library until you sign in again. Sign out, then sign in - with your new password if you changed it. Nothing is lost meanwhile.")
    check('...nothing while it works', [W.loginWords(LIBRARY), W.loginWords({ ...LIBRARY, login: 'none' })], [null, null])
    const many = { waiting_albums: [
      { ...entry(1, 'A'), words: 'one' }, { ...entry(2, 'B'), words: 'two' }, { ...entry(3, 'C'), words: 'two' }, { ...entry(4, 'D'), words: null }] }
    check('what waits, grouped by why, the most first (no words: waiting its turn)', W.waitingGroups(many),
      [{ words: 'two', albums: ['B by Portishead', 'C by Portishead'] }, { words: 'one', albums: ['A by Portishead'] },
        { words: 'Waiting its turn to be added.', albums: ['D by Portishead'] }])
    const sixty = W.waitingGroups({ waiting_albums: Array.from({ length: 60 }, (_, n) => ({ ...entry(n, `Album ${n}`), words: 'no id' })) })
    check('a group said: two named in full, three named, sixty - three named then "and 57 more" (review: never a paragraph of names)',
      [W.waitingText({ words: 'why', albums: ['A', 'B'] }), W.waitingText({ words: 'why', albums: ['A', 'B', 'C'] }), W.waitingText(sixty[0]), W.WAITING_NAMED],
      ['A and B: why', 'A, B and C: why', 'Album 0 by Portishead, Album 1 by Portishead, Album 2 by Portishead and 57 more: no id', 3])
    check('where focus goes when a row leaves: the row after it, else before it, else the heading (null)',
      [W.nextFocus([1, 2, 3], 1), W.nextFocus([1, 2, 3], 3), W.nextFocus([7], 7), W.nextFocus([1, 2], 9)], [2, 2, null, null])
    check('an entry\'s name', [W.entryName({ album: 'Dummy', artist: 'Portishead' }), W.entryName({ album: '', artist: '' })], ['Dummy by Portishead', 'Unknown album'])
    check('the delete dialog: who else holds it - one, two, three, nobody, and nothing with logins off',
      [W.holdersText({ holders: ['ethan'], yours: false }), W.holdersText({ holders: ['james', 'ethan'] }), W.holdersText({ holders: ['james', 'ethan', 'sam'], yours: false }),
        W.holdersText({ holders: [], yours: false }), W.holdersText({}), W.holdersText(null)],
      ["In ethan's library: deleting it takes it out, and they'll see it was removed by an admin.",
        "In james and ethan's libraries: deleting it takes it out, and they'll see it was removed by an admin.",
        "In james, ethan and sam's libraries: deleting it takes it out, and they'll see it was removed by an admin.",
        'Nobody has it in their library.', null, null])
    check('...the admin deleting it holds it too: "your library" first, and only the others told it was removed (review)',
      [W.holdersText({ holders: [], yours: true }), W.holdersText({ holders: ['ethan'], yours: true }), W.holdersText({ holders: ['ethan', 'sam'], yours: true })],
      ['In your library: deleting it takes it out.',
        "In your library and ethan's: deleting it takes it out, and ethan will see it was removed by an admin.",
        "In your library, ethan's and sam's: deleting it takes it out, and ethan and sam will see it was removed by an admin."])
    check('...deadwax couldn\'t read who holds it: said so - never "nobody" on a guess (review)',
      W.holdersText({ holders_unknown: true }), "deadwax couldn't read who has it in their library - whoever does will find it was removed by an admin.")
    const marks = W.newMarks(LIBRARY)
    check('the New marks: by Navidrome id, or by release whatever its case', [W.isNew(marks, { id: 'nd-dummy' }), W.isNew(marks, { id: 'nd-x', musicBrainzId: 'REL-3' }),
      W.isNew(marks, { id: 'nd-x', musicBrainzId: 'rel-4' }), W.isNew(W.newMarks(null), { id: 'nd-dummy' })], [true, true, false, false])
    check('Home\'s shelf: only what Navidrome has (starred, so its id is known), as its albums', W.newShelf(LIBRARY),
      [{ id: 'nd-dummy', name: 'Dummy', artist: 'Portishead', coverArt: 'nd-dummy', musicBrainzId: 'rel-1' }])
    check('held by nobody\'s line', [W.heldByNobodyLine(3), W.heldByNobodyLine(1), W.heldByNobodyLine(0)],
      ['3 albums nobody has in their library', '1 album nobody has in their library', "Every album in the collection is in somebody's library."])
    check('a flag\'s words', W.flagWords({ users: ['ethan', 'sam'], path: 'Portishead/Third (2008)' }),
      'ethan and sam asked for it. Every file was already in Portishead/Third (2008), which holds another pressing or an untagged copy - so nobody was given it.')
  }

  console.log('\nthe store (app/useMyLibrary.ts)')
  {
    L.me = null
    store.askMyLibrary()
    //? (2.0.0-player.61) the break-glass admin is `deadwax` now
    L.me = { user: 'deadwax', admin: true, auth: 'on', version: 'x' }
    store.askMyLibrary()
    check('logins off, or the break-glass admin: nothing asked', [L.asks.length, store.hasLibrary()], [0, false])
    L.me = { user: 'admin', admin: true, auth: 'on', version: 'x' }
    check('...and Navidrome\'s own `admin` signed in has a library like anyone', store.hasLibrary(), true)
    L.me = { user: 'ethan', admin: false, auth: 'on', version: 'x' }
    store.askMyLibrary()
    store.askMyLibrary()
    check('signed in through Navidrome: asked - each ask the newest, the one before called off',
      [L.asks.map((a) => a[0]), L.open[0].signal.aborted, L.open[1].signal.aborted], [['library', 'library'], true, false])
    //? the newest lands first, the older after it
    const [older, newer] = L.open.splice(0, 2)
    newer.resolve(LIBRARY)
    await settle()
    older.resolve({ ...LIBRARY, count: 99 })
    await settle()
    check('...only the newest answer kept, whatever order they land in', store.myLibraryNow().count, 12)
    check('...and a filing asks again (heard once), and an add from a store line', [L.filedListeners.length, L.addedListeners.length], [1, 1])
    L.filedListeners[0]()
    answer('library', LIBRARY)
    await settle()
    L.addedListeners[0]()
    answer('library', LIBRARY)
    await settle()
    //? (2.0.0-player.52) Remove from my library takes one out: the count moves, so it asks again too
    check('...and a Remove from an album page (heard once)', L.removedListeners.length, 1)
    const before = L.asks.length
    L.removedListeners[0]()
    check('...which asks your library again', L.asks.slice(before).map((a) => a[0]), ['library'])
    answer('library', LIBRARY)
    await settle()

    store.seenAlbum({ id: 'nd-elsewhere', musicBrainzId: 'rel-77' })
    check('an album that isn\'t new: deadwax told nothing', L.seen, [])
    store.seenAlbum({ id: 'nd-dummy', musicBrainzId: 'REL-1' })
    check('an album new in your library, opened: told by its release, its mark gone at once',
      [L.seen, store.myLibraryNow().new.map((e) => e.album_id)], [[{ release_mbid: 'rel-1' }], [3]])
    store.seenAlbum({ id: 'nd-third-has-no-release-here', musicBrainzId: '' })
    check('...one with no release to tell by: nothing (it is matched by release or by the id it was starred on)', L.seen.length, 1)
    L.me = null
    store.seenAlbum({ id: 'x', musicBrainzId: 'rel-3' })
    check('...and nothing at all with logins off', L.seen.length, 1)
    //? (review) an album reached by its address: App knows only its Navidrome id - deadwax told by the store's ids
    L.me = { user: 'ethan', admin: false, auth: 'on', version: 'x' }
    store.askMyLibrary()
    answer('library', LIBRARY)
    await settle()
    L.seen.length = 0
    store.seenAlbum({ id: 'nd-dummy' })
    check('...one opened by the Navidrome id it was starred on, no release known: told by the store\'s ids, its mark gone',
      [L.seen, store.myLibraryNow().new.map((e) => e.album_id)], [[{ album_ids: [1] }], [3]])
  }

  console.log('\nthe store, opened before deadwax first said (review)')
  {
    //? a fresh copy of the store: nothing asked yet
    for (const key of Object.keys(require.cache)) if (key.endsWith('useMyLibrary.js')) delete require.cache[key]
    const fresh = require(path.join(OUT, 'app/useMyLibrary.js'))
    L.me = { user: 'ethan', admin: false, auth: 'on', version: 'x' }
    L.seen.length = 0
    L.open.length = 0
    fresh.seenAlbum({ id: 'nd-dummy', musicBrainzId: 'rel-1' })
    check('an album opened before any answer: deadwax told nothing yet', L.seen, [])
    fresh.askMyLibrary()
    answer('library', LIBRARY)
    await settle()
    check('...and once the first answer lands it is looked at: told, and its mark gone', [L.seen, fresh.myLibraryNow().new.map((e) => e.album_id)],
      [[{ release_mbid: 'rel-1' }], [3]])
  }

  console.log('\nYou > Your library')
  {
    L.me = null
    const draw = hooks.root(YourLibrary)
    let tree = draw({ current: true })
    check('logins off: nothing', tree, null)
    L.me = { user: 'ethan', admin: false, auth: 'on', version: 'x' }
    L.asks.length = 0
    tree = draw({ current: false })
    draw.commit()
    tree = draw({ current: true })
    draw.commit()
    check('asked as You comes into view', L.asks.map((a) => a[0]), ['library'])
    answer('library', LIBRARY)
    await settle()
    const opened = []
    tree = draw({ current: true, onRequestAgain: (group) => opened.push(group) })
    check('the count, and how many are incomplete', [words(find(byClass('app-row-value'), tree)), words(find(byClass('app-row-detail'), tree)[0])],
      ['12 albums · 2 waiting to be added', '1 of them is missing some songs.'])
    //? (2.0.5 review) Amperfy named once, in the footnote - "also in your other music apps, such as Amperfy"
    const amperfy = (node) => (words(node).match(/Amperfy/g) ?? []).length
    check('Amperfy named once on the whole page, and that in the footnote', [amperfy(tree), find(byClass('app-footnote'), tree).map(amperfy).filter(Boolean)], [1, [1]])
    check('what waits, and why - each line one that breaks anywhere (a stranger\'s one-word title)', find(byClass('app-mylib-waiting'), tree).map(words),
      ["Third by Portishead: Navidrome hasn't got it yet (it may still be scanning) - deadwax asks again by itself.",
        "Roseland NYC Live by Portishead: It has no MusicBrainz release id, so deadwax can't find it in Navidrome - an admin can apply a release to it."])
    //? (2.0.5 review) Get it again only for someone who may Get: the page it opens says "Getting albums is off for you"
    //? to anyone else - so with no Get albums, only Dismiss
    check('an album an admin deleted, for someone who may not Get: said so, and only Dismiss',
      buttons(find(byClass('app-mylib-removed'), tree)[0]).map(words), ['Dismiss'])
    const access = require(path.join(OUT, 'app/access.js'))
    access.noteAccess({ ...L.me, permissions: ['request'] })
    tree = draw({ current: true, onRequestAgain: (group) => opened.push(group) })
    const removed = find(byClass('app-mylib-removed'), tree)[0]
    check('an album an admin deleted: said so, Get it again and Dismiss (2.0.5\'s words)', [words(find(byClass('app-row-label'), removed)), words(find(byClass('app-row-detail'), removed)), buttons(removed).map(words)],
      ['Portishead by Portishead', 'Removed by an admin.', ['Get it again', 'Dismiss']])
    buttons(removed)[0].props.onClick()
    check('Get it again: its album page, by the release group', opened, [{ id: 'grp-9', title: 'Portishead' }])
    L.asks.length = 0
    buttons(removed)[1].props.onClick()
    tree = draw({ current: true, onRequestAgain: () => {} })
    check('Dismiss: asked, waiting', [L.asks, words(buttons(find(byClass('app-mylib-removed'), tree)[0])[1])], [[['dismiss', 9]], 'Dismissing…'])
    answer('dismiss', { dismissed: true })
    await settle()
    check('...and your library asked again once deadwax has it', L.asks.map((a) => a[0]), ['dismiss', 'library'])
    //? the page, faked: the focus fell to it as the row left; the heading a focus target
    const focused = []
    globalThis.document = { body: { tag: 'body' } }
    globalThis.document.activeElement = globalThis.document.body
    tree = draw({ current: true })
    const headingRef = find((node) => node.type === 'h2', tree)[0].props.ref
    headingRef.current = { focus: () => focused.push('heading') }
    check('...the heading a focus target', find((node) => node.type === 'h2', tree)[0].props.tabIndex, -1)
    draw.commit()
    check('...nothing moved before the answer lands (the row is still there)', focused, [])
    answer('library', { ...LIBRARY, removed: [], login: 'dead', login_problem: 'Navidrome no longer accepts the login you signed in with.' })
    await settle()
    tree = draw({ current: true })
    draw.commit()
    check('...the last row gone: its focus to the heading, never the page - and said', [focused, words(find((node) => node.props?.['aria-live'] === 'polite', tree))],
      [['heading'], 'Portishead by Portishead dismissed'])
    delete globalThis.document
    tree = draw({ current: true })
    check('a login Navidrome no longer takes: said in red; nothing removed, no list', [words(find(byClass('app-error'), tree)).startsWith("New albums can't be added to your library until you sign in again"), find(byClass('app-mylib-removed'), tree).length],
      [true, 0])
    store.askMyLibrary()
    answer('library', { on: true, library: true, kept: false })
    await settle()
    tree = draw({ current: true })
    //? (2.0.4) to someone who doesn't run deadwax, with what they can do about it
    check('deadwax can\'t read its database: said, and to tell whoever runs deadwax', words(find(byClass('app-error'), tree)),
      "deadwax can't read its database, so it can't say what your library holds. Tell whoever runs deadwax.")
    store.askMyLibrary()
    answer('library', { on: true, library: false, kept: false })
    await settle()
    check('the break-glass admin\'s answer (no library): nothing', draw({ current: true }), null)
  }

  console.log('\nLibrary care > Held by nobody')
  {
    L.asks.length = 0
    L.open.length = 0
    const draw = hooks.root(HeldByNobody)
    let tree = draw({ live: false })
    draw.commit()
    check('not showing: nothing asked', L.asks, [])
    tree = draw({ live: true })
    draw.commit()
    check('showing: asked, saying so meanwhile', [L.asks.map((a) => a[0]), words(find(byClass('app-care-note'), tree))], [['held'], 'Asking deadwax…'])
    const albums = Array.from({ length: 23 }, (_, n) => ({ id: n + 1, path: `A/${n}`, artist: 'A', album: `Album ${n}`, edition: '', year: '', release_mbid: null, formats: [], track_count: 1 }))
    const flags = [{ id: 5, album_id: 3, artist: 'Portishead', album: 'Third', path: 'Portishead/Third (2008)', release_mbid: 'rel-3', users: ['ethan'], created_at: 'x' }]
    answer('held', { count: 23, albums, flags })
    await settle()
    tree = draw({ live: true })
    check('the line, the first 20, then Show all', [words(find(byClass('app-care-note'), tree)), find(byClass('app-care-held-path'), tree).length - 1, HELD_SHOWN,
      words(buttons(tree)[0])], ['23 albums nobody has in their library', 20, 20, 'Show all 23'])
    buttons(tree)[0].props.onClick()
    tree = draw({ live: true })
    check('...all of them, once asked - and the same button, Show fewer, so its focus stays (review)',
      [find(byClass('app-care-held-path'), tree).length - 1, words(buttons(tree)[0]), buttons(tree)[0].props['aria-expanded']], [23, 'Show fewer', true])
    const flag = find(byClass('app-care-held-actions'), tree)[0]
    check('a flag: its words, Add for them, Dismiss', [words(find(byClass('app-care-held-path'), tree).at(-1)), buttons(flag).map(words)],
      ['ethan asked for it. Every file was already in Portishead/Third (2008), which holds another pressing or an untagged copy - so nobody was given it.', ['Add for them', 'Dismiss']])
    L.asks.length = 0
    buttons(flag)[0].props.onClick()
    buttons(flag)[1].props.onClick()
    check('Add for them asks once - Dismiss waits for it', L.asks, [['add', 5]])
    answer('add', new Error('That album isn\'t in the collection any more - dismiss it.'))
    await settle()
    tree = draw({ live: true })
    check('...refused: deadwax\'s words, and the list asked again', [words(find(byClass('app-care-problem'), tree)), L.asks.map((a) => a[0])],
      ["That album isn't in the collection any more - dismiss it.", ['add', 'held']])
    answer('held', { count: 0, albums: [], flags: [] })
    await settle()
    tree = draw({ live: true })
    check('...nothing left: said - and the refusal still there to read', [words(find(byClass('app-care-note'), tree)), words(find(byClass('app-care-problem'), tree))],
      ["Every album in the collection is in somebody's library.", "That album isn't in the collection any more - dismiss it."])

    //? two flags: Add for the first; it leaves, and its focus goes to the second's first button - and is said
    const two = [flags[0], { ...flags[0], id: 6, album: 'Dummy', users: ['sam'] }]
    L.asks.length = 0
    const focused = []
    globalThis.document = { body: { tag: 'body' } }
    globalThis.document.activeElement = globalThis.document.body
    draw.commit()
    const drawFlags = hooks.root(HeldByNobody)
    tree = drawFlags({ live: true })
    drawFlags.commit()
    answer('held', { count: 0, albums: [], flags: two })
    await settle()
    tree = drawFlags({ live: true })
    const secondButton = { focus: () => focused.push('second flag') }
    const listRef = find((node) => node.type === 'ul', tree)[0].props.ref
    listRef.current = { querySelectorAll: () => [{ dataset: { flag: '6' }, querySelector: () => secondButton }] }
    buttons(find(byClass('app-care-held-actions'), tree)[0])[0].props.onClick()
    answer('add', { added: true, users: ['ethan'] })
    await settle()
    tree = drawFlags({ live: true })
    drawFlags.commit()
    check('...a flag dealt with: nothing moved until the list is read again', focused, [])
    answer('held', { count: 0, albums: [], flags: [two[1]] })
    await settle()
    tree = drawFlags({ live: true })
    drawFlags.commit()
    check('...then its focus to the flag now in its place, and who was given it said (review)', [focused, words(find((node) => node.props?.['aria-live'] === 'polite', tree))],
      [['second flag'], 'Third · Portishead: given to ethan'])
    delete globalThis.document
  }

  console.log('\nread off the source: the delete dialog names the holders, the Library marks what is new')
  {
    const dialog = fs.readFileSync(path.join(UI, 'src/components/DeleteAlbumDialog.tsx'), 'utf8')
    //? (2.0.0-player.59) the one tile, app/AlbumTile.tsx, draws the mark; the sections and the root hand it the marks
    const tile = fs.readFileSync(path.join(UI, 'src/app/AlbumTile.tsx'), 'utf8')
    const marking = ['src/app/LibrarySection.tsx', 'src/app/LibraryHome.tsx'].map((file) => fs.readFileSync(path.join(UI, file), 'utf8'))
    check('the dialog: the summary\'s holders in its words, above the warning',
      [/\{summary && holdersText\(summary\) && \(\s*<p class="text yellow delete-warning delete-holders">\{holdersText\(summary\)\}<\/p>/.test(dialog),
        dialog.indexOf('delete-holders') < dialog.indexOf('This deletes the folder')], [true, true])
    const css = fs.readFileSync(path.join(UI, '../interface/player/app.css'), 'utf8')
    check('Your library\'s album names break anywhere - the waiting lines and the removed rows (review: a one-word title pushed the page sideways, or was cut off)',
      /\.app-mylib-waiting,\s*\.app-mylib-removed \.app-row-label \{ overflow-wrap: anywhere; \}/.test(css), true)
    check('the Library tab: a tile new in your library marked New, said in full to a screen reader - the root\'s 12 too',
      [...marking.map((code) => /const mine = useMyLibrary\(\)\s*const marks = useMemo\(\(\) => newMarks\(mine\), \[mine\]\)/.test(code) && /<AlbumTile key=\{album\.id\} album=\{album\} marks=\{marks\} onOpen=\{onOpen\} \/>/.test(code)),
        /\{isNew\(marks, album\) && \(\s*<span class="pl-album-new">\s*New<span class="app-visually-hidden"> in your library<\/span>/.test(tile)],
      [true, true, true])
  }

  finished = true
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

run()
