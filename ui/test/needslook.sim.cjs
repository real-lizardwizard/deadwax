/**
 * Needs a look (2.0.0-player.25) - the review queue in the app, on a desktop: the pure rules in
 * lib/needsLook.ts, and the page itself (app/NeedsALook.tsx), compiled with the repo's TypeScript and
 * rendered by the small stand-in for Preact the other page sims use (group.sim, artist.sim).
 *
 * What it pins:
 *
 *  - THE LIST is metadataQueue.ts's queueAlbums - the same function and order as the main page (new
 *    imports first, worst first, then alphabetical) - and the facets: All N, Newly added N only when
 *    there is one, one chip per kind of issue with albums, the most first. A facet that has emptied
 *    shows All. The page's All count is summaryTotal, which is what the badge's route counts (the
 *    Python side: tests/test_queue_summary.py).
 *  - THE SESSION: begun at the clicked row with the list as shown; nothing moves while it lasts - a
 *    fixed, ignored or deleted album stays in its row saying which, a renamed one followed by path;
 *    stepping away from an album marks it reviewed (never one deleted), and asks the count again;
 *    an album gone when stepped to ends it; it ends as the panel closes or the facet changes, its
 *    rows held until a fresh scan lands, the list then worked out again.
 *  - THE PAGE: the spinner, the problem, a failed read with Try again, "Nothing needs a look", the
 *    quiet "Checking the library…" in a line that is always there, the selected row (Explorer's look
 *    and aria-current), what the panel is asked for (the folder, the queue's place, read again only
 *    for a session's first album), its own count standing in for the server's only while it shows
 *    with a real scan and no session - and on a phone a note, with nothing asked.
 *  - AFTER REVIEW: the ending's scan asked only once the album left has been noted reviewed (go()'s
 *    ending too); its rows held, aria-disabled and refusing a click, until no read is still out (a
 *    superseded read answering doesn't end it); the chips held for the session and its ending; a facet
 *    not reset on a SAVED scan; disc_label before the edition; a failed cover's plain tile; Try again
 *    aria-disabled and refused while a read is out; a write about a path two rows share (merged disc
 *    folders) the current row's.
 *  - THE COUNT'S STORE: the real app/useQueueSummary.ts against a faked deadwax - one request out and
 *    exactly one more, a failure keeping the last number (null with none), the page's count first.
 *
 * Run it with:  node ui/test/needslook.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

/* ===== the pure rules ===== */

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-needslook-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/needsLook.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })
const N = require(path.join(OUT, 'lib/needsLook.js'))
const Q = require(path.join(OUT, 'lib/metadataQueue.js'))

const TYPES = {
  no_release: { label: 'no release', hint: 'Not matched to a MusicBrainz release.', severity: 3 },
  no_art: { label: 'no cover', hint: 'No cover art saved with the album.', severity: 1 },
  misfiled: { label: 'folder off-convention', hint: 'The folder is not named as deadwax would.', severity: 2 },
}
const album = (path, more = {}) => ({
  path, artist: path.split('/')[0], album: path.split('/')[1], edition: '', art: 'file', art_mtime: 1,
  issues: [], ignored_issues: [], needs_attention: false, severity: 0, imported: false, reviewed: false, ...more,
})
const issues = (codes, more = {}) => ({ issues: codes, needs_attention: codes.length > 0, severity: Math.max(0, ...codes.map((c) => TYPES[c].severity)), ...more })

const RIP = album('Old Rips/Third rip', issues(['no_release', 'misfiled', 'no_art'], { art: '' }))
const COVERLESS = album('Portishead/Dummy (1994)', issues(['no_art'], { art: '' }))
const IGNORED = album('Bootlegs/Live 1998', { ...issues(['no_release']), ignored_issues: ['no_release'], needs_attention: false, severity: 0 })
const NEW_CLEAN = album('Tame Impala/Currents (2015)', { imported: true })
const NEW_BROKEN = album('Ye/BULLY (2025)', { ...issues(['misfiled']), imported: true })
const SEEN = album('Ye/Donda (2021)', { imported: true, reviewed: true })
const CLEAN = album('Pink Floyd/Wish You Were Here (1975)')
const LIBRARY = [CLEAN, RIP, COVERLESS, IGNORED, NEW_CLEAN, NEW_BROKEN, SEEN]
const paths = (albums) => albums.map((one) => one.path)

console.log('\nthe list and its facets')
{
  check('the list is queueAlbums: new imports first, then worst first, then alphabetical',
    paths(N.facetAlbums(LIBRARY, null)), paths(Q.queueAlbums(LIBRARY, null)))
  check('...which is: the two new imports, the rip, the coverless album', paths(N.facetAlbums(LIBRARY, null)),
    ['Ye/BULLY (2025)', 'Tame Impala/Currents (2015)', 'Old Rips/Third rip', 'Portishead/Dummy (1994)'])
  const chips = N.facets(LIBRARY, TYPES)
  check('the chips: All, Newly added, then each issue with albums - the most first, then by label',
    chips.map((chip) => [chip.id, chip.label, chip.count]),
    [[null, 'All', 4], ['new', 'Newly added', 2], ['misfiled', 'folder off-convention', 2], ['no_art', 'no cover', 2], ['no_release', 'no release', 1]])
  check('...each issue chip carrying its hint, for its title', chips.slice(2).map((chip) => chip.hint), [TYPES.misfiled.hint, TYPES.no_art.hint, TYPES.no_release.hint])
  check('Newly added only when there is one', N.facets([RIP, COVERLESS], TYPES).map((chip) => chip.id), [null, 'no_art', 'misfiled', 'no_release'])
  check('an ignored issue is not a chip, nor counted', N.facets([IGNORED], TYPES), [{ id: null, label: 'All', count: 0 }])
  check('Newly added lists the new imports, in the list\'s order', paths(N.facetAlbums(LIBRARY, N.NEW_FACET)), ['Ye/BULLY (2025)', 'Tame Impala/Currents (2015)'])
  check('an issue lists the albums with it outstanding, as queueAlbums does', paths(N.facetAlbums(LIBRARY, 'no_art')), paths(Q.queueAlbums(LIBRARY, 'no_art')))
  check('the page\'s All count is the badge\'s count over the same albums', [N.summaryTotal(LIBRARY), chips[0].count, Q.queueAlbums(LIBRARY, null).length], [4, 4, 4])
  check('a facet with albums shows; one that has emptied, or was never there, falls back to All',
    [N.facetShown(chips, 'no_art'), N.facetShown(N.facets([RIP], TYPES), 'new'), N.facetShown(chips, 'nonsense'), N.facetShown(chips, null)],
    ['no_art', null, null, null])
  check('a count for VoiceOver', [N.needsLookLabel('Needs a look', 3), N.needsLookLabel('Needs a look', 1), N.needsLookLabel('Needs a look', 0), N.needsLookLabel('Needs a look', null)],
    ['Needs a look, 3 albums', 'Needs a look, 1 album', 'Needs a look', 'Needs a look'])
}

console.log('\nthe session')
{
  const list = N.facetAlbums(LIBRARY, null)
  const begun = N.startSession(list, RIP.path, null)
  check('begun on the clicked row, the list as shown, in its order', [begun.index, begun.rows.map((row) => row.path), begun.facet],
    [2, paths(list), null])
  check('a row not listed begins nothing', N.startSession(list, CLEAN.path, null), null)

  const fixed = { ...RIP, issues: [], needs_attention: false, severity: 0, release_mbid: 'x' }
  const ignored = { ...RIP, ignored_issues: ['no_release', 'misfiled', 'no_art'], needs_attention: false }
  const half = { ...RIP, issues: ['no_art'] }
  check('a mark: every issue gone is Fixed; gone with some accepted, Ignored; something left, none',
    [N.markFor(RIP, fixed), N.markFor(RIP, ignored), N.markFor(RIP, half)], ['fixed', 'ignored', null])
  check('...and a clean new import had nothing to fix: no mark', N.markFor(NEW_CLEAN, { ...NEW_CLEAN, reviewed: true }), null)

  const renamed = { ...fixed, path: 'Portishead/Third (2008)' }
  const after = N.rowChanged(begun, { from: RIP.path, album: renamed, deleted: false })
  check('a write: the row followed to its new path, marked, in its place - nothing else moved',
    [after.rows.map((row) => row.path), after.rows[2].mark, after.rows[2].listed.path, after.index],
    [['Ye/BULLY (2025)', 'Tame Impala/Currents (2015)', 'Portishead/Third (2008)', 'Portishead/Dummy (1994)'], 'fixed', RIP.path, 2])
  check('...a delete marks it Deleted', N.rowChanged(begun, { from: COVERLESS.path, album: null, deleted: true }).rows[3].mark, 'deleted')
  check('...a write to an album not in the session changes nothing', N.rowChanged(begun, { from: 'Elsewhere/X', album: CLEAN, deleted: false }), begun)

  const there = () => true
  check('stepping to the row it is on, or past either end: nothing', [N.stepTarget(begun, 2, there), N.stepTarget(begun, -1, there), N.stepTarget(begun, 4, there)].map((t) => t.kind), ['stay', 'stay', 'stay'])
  const next = N.stepTarget(after, 3, there)
  check('stepping on: the album left is marked reviewed - by the path it has now', [next.kind, next.leaving, next.session.index], ['step', 'Portishead/Third (2008)', 3])
  const gone = N.rowChanged(after, { from: 'Portishead/Third (2008)', album: null, deleted: true })
  check('...never one deleted here', N.stepTarget(gone, 3, there).leaving, null)
  check('an album deleted here, stepped to: the session ends', N.stepTarget(N.rowChanged(begun, { from: COVERLESS.path, album: null, deleted: true }), 3, there),
    { kind: 'end', leaving: RIP.path })
  check('...and one gone from the scan (deleted outside)', N.stepTarget(begun, 3, (p) => p !== COVERLESS.path).kind, 'end')
  check('...but one a write has told of is there, whatever an older scan says (a rename)',
    N.stepTarget({ ...after, index: 3 }, 2, (p) => p !== 'Portishead/Third (2008)').kind, 'step')
  check('the album to mark as the session ends: the one on, unless deleted', [N.leavingAtEnd(after), N.leavingAtEnd(gone)], ['Portishead/Third (2008)', null])

  //? a set kept one folder per disc: both listed; the first renamed to the release's folder, the
  //? second merged into it - two rows, one path. A write from the second's panel is the second's.
  const DISCS = album('Radiohead/In Rainbows (2007)', issues(['misfiled']))
  const DISC4 = album('Radiohead/In Rainbows (Disc 4)', issues(['misfiled']))
  const MERGED = 'Radiohead/In Rainbows (2007) [Discbox]'
  let set = N.startSession([DISCS, DISC4], DISCS.path, null)
  set = N.rowChanged(set, { from: DISCS.path, album: { ...DISCS, path: MERGED, issues: [] }, deleted: false })
  set = { ...set, index: 1 }
  set = N.rowChanged(set, { from: DISC4.path, album: { ...DISC4, path: MERGED, issues: [] }, deleted: false })
  check('two rows come to one path (a disc folder merged into the other\'s)', set.rows.map((row) => row.path), [MERGED, MERGED])
  const dropped = N.rowChanged(set, { from: MERGED, album: null, deleted: true })
  check('...a delete from the current row\'s panel marks THAT row, not the first with the path', dropped.rows.map((row) => row.mark), ['fixed', 'deleted'])
  check('...so stepping on reviews nothing deleted', N.stepTarget(dropped, 0, there).leaving, null)
  check('...a write about a path the current row hasn\'t still finds its row', N.rowChanged({ ...set, index: 0 }, { from: MERGED, album: null, deleted: true }).rows.map((row) => row.mark), ['deleted', 'fixed'])
}

/* ===== the page itself: app/NeedsALook.tsx, rendered ===== */

const PAGE = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-needslook-page-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/NeedsALook.tsx', '--rootDir', 'src', '--outDir', PAGE,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - group.sim.cjs's stand-in
fs.mkdirSync(path.join(PAGE, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(PAGE, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
fs.writeFileSync(path.join(PAGE, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(PAGE, 'node_modules/preact/hooks.js'), `
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
  render.unmount = () => { for (const s of root.slots) if (s && typeof s.cleanup === 'function') s.cleanup() }
  return render
}
`)

const write = (file, body) => fs.writeFileSync(path.join(PAGE, file), body)
//? the main page's hook, as the test says it stands; the queue's calls, kept
write('hooks/useLibrary.js', `exports.useLibrary = (enabled) => { globalThis.__page.enabled.push(enabled); return globalThis.__page.library }\n`)
write('api/library.js', `exports.markReviewed = (path) => {
  const W = globalThis.__page
  W.reviewed.push(path)
  //? held: the note not written yet, to see what waits for it
  return W.holdMarks ? new Promise((resolve) => W.marks.push(() => resolve({ reviewed: true }))) : Promise.resolve({ reviewed: true })
}
`)
write('app/useQueueSummary.js', `
exports.askQueueSummary = () => { globalThis.__page.asked++ }
exports.setPageQueueCount = (count) => { globalThis.__page.counts.push(count) }
`)
write('app/useSheet.js', `exports.takeOpener = (event) => event?.currentTarget ?? null\n`)
write('player/icons.js', `exports.ChevronLeftIcon = function Icon() { return null }\n`)

const W = globalThis.__page = { enabled: [], reviewed: [], asked: 0, counts: [], reloads: [], library: null, holdMarks: false, marks: [] }
function libraryOf(albums, more = {}) {
  W.library = {
    albums, issueTypes: TYPES, problem: null, error: null, loading: false, loaded: true, stale: false,
    reload: (force) => new Promise((resolve) => W.reloads.push({ force, resolve })), ...more,
  }
}
function reset() {
  W.enabled.length = 0; W.reviewed.length = 0; W.asked = 0; W.counts.length = 0; W.reloads.length = 0
  W.holdMarks = false; W.marks.length = 0
}

const hooks = require(path.join(PAGE, 'node_modules/preact/hooks.js'))
const { NeedsALook } = require(path.join(PAGE, 'app/NeedsALook.js'))

let tree = null
function find(test, within = tree) {
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
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const classed = (name) => find(byClass(name))
const rowButtons = () => classed('app-queue-row')
const rowAlbums = () => classed('app-queue-album').map(words)
const rowMarks = () => rowButtons().map((row) => words(find(byClass('app-queue-mark'), row)[0]) || null)
const facetChips = () => classed('app-queue-facet').map((chip) => [words(chip), chip.props['aria-pressed']])
const click = (node) => node.props.onClick({ currentTarget: { focus() {}, tag: words(node) } })

function mount(props = {}) {
  const render = hooks.root(NeedsALook)
  const edits = [], facetsAsked = [], closes = []
  const all = {
    desktop: true, shown: true, facet: null, editing: null, backLabel: 'You', onBack() {},
    onFacet: (facet) => facetsAsked.push(facet),
    onEdit: (request, opener) => { edits.push({ request, opener }); all.editing = request.folder },
    onCloseEdit: () => { closes.push(true); all.editing = null },
    ...props,
  }
  const draw = (more = {}) => {
    Object.assign(all, more)
    tree = render(all)
    render.commit()
    tree = render(all)
    render.commit()
    return tree
  }
  return { draw, all, edits, facetsAsked, closes, unmount: () => render.unmount() }
}

async function page() {
  console.log('\nthe page: on a phone, a note - and nothing asked')
  {
    reset()
    libraryOf(LIBRARY)
    const phone = mount({ desktop: false })
    phone.draw()
    const link = find((node) => node.type === 'a')[0]
    check('the note, and the main page beside the app', [words(classed('app-queue-phone')[0]).replace(/\s+/g, ' '), link.props.target, link.props.rel],
      ['Fixing albums needs a wider screen for now - or the main page.', '_blank', 'noopener'])
    check('...the library never read, no row, no count, nothing reviewed', [W.enabled.every((on) => on === false), rowButtons().length, W.counts.every((c) => c === null), W.reviewed, W.asked],
      [true, 0, true, [], 0])
  }

  console.log('\nthe page: its states')
  {
    reset()
    libraryOf([], { loaded: false })
    const one = mount()
    one.draw()
    check('until the first answer: the spinner, nothing else', [classed('pl-spinner').length, rowButtons().length, classed('app-queue-facets').length], [1, 0, 0])
    check('...the library read once it shows on a desktop', W.enabled.at(-1), true)

    libraryOf([], { problem: 'LIBRARY_PATH is not set' })
    one.draw()
    check('LIBRARY_PATH not set: said plainly, as the scan said it', words(classed('app-queue-state')[0]), 'LIBRARY_PATH is not set')

    libraryOf([], { error: 'HTTP 502' })
    one.draw()
    const retry = find((node) => node.type === 'button' && words(node) === 'Try again')[0]
    check('a failed read with nothing to show: said, with Try again', [words(classed('app-queue-state')[0]).includes('HTTP 502'), !!retry], [true, true])
    click(retry)
    check('...which reads the library again', W.reloads.length, 1)

    libraryOf([CLEAN, SEEN])
    one.draw()
    check('nothing outstanding: "Nothing needs a look."', [words(classed('app-queue-state')[0]), rowButtons().length, facetChips()], ['Nothing needs a look.', 0, [['All 0', true]]])

    libraryOf(LIBRARY, { stale: true })
    one.draw()
    check('the saved scan shown: the rows at once, and the quiet line', [rowAlbums().length, words(classed('app-queue-checking')[0])], [4, 'Checking the library…'])
    libraryOf(LIBRARY)
    one.draw()
    check('...the real scan in: the line still there, saying nothing - so no row moves', [classed('app-queue-checking').length, words(classed('app-queue-checking')[0])], [1, ''])
  }

  console.log('\nthe page: the list, its facets, and its count')
  {
    reset()
    libraryOf(LIBRARY)
    const one = mount()
    one.draw()
    check('the rows in queueAlbums\' order', rowAlbums(), ['BULLY (2025)', 'Currents (2015)', 'Third rip', 'Dummy (1994)'])
    check('the facets, All pressed', facetChips(), [['All 4', true], ['Newly added 2', false], ['folder off-convention 2', false], ['no cover 2', false], ['no release 1', false]])
    const rip = rowButtons()[2]
    check('a row: New for a new import, its outstanding issues as chips, each titled with its hint, the plain tile with no cover',
      [find(byClass('app-queue-chip'), rowButtons()[0]).map(words), find(byClass('app-queue-chip'), rip).map((chip) => [words(chip), chip.props.title]), find(byClass('is-empty'), rip).length],
      [['New', 'folder off-convention'], [['no release', TYPES.no_release.hint], ['folder off-convention', TYPES.misfiled.hint], ['no cover', TYPES.no_art.hint]], 1])
    check('...and the folder\'s cover through the art route where it has one', find((node) => node.type === 'img', rowButtons()[1])[0].props.src,
      '/deadwax/library/art?album=Tame%20Impala%2FCurrents%20(2015)&v=1')
    check('its count stands in for the server\'s: shown, a real scan, no session', W.counts.at(-1), 4)
    click(find((node) => byClass('app-queue-facet')(node) && words(node).startsWith('no cover'))[0])
    check('a facet chosen: the address told', one.facetsAsked, ['no_art'])
    one.draw({ facet: 'no_art' })
    check('...the list narrowed, the chip pressed', [rowAlbums(), facetChips()[3]], [['Third rip', 'Dummy (1994)'], ['no cover 2', true]])
    one.draw({ facet: 'misfiled' })
    libraryOf([RIP, COVERLESS].map((one) => ({ ...one, issues: one.issues.filter((c) => c !== 'misfiled') })))
    one.draw()
    check('a facet that has emptied: All shown, and the address told', [facetChips()[0], one.facetsAsked.at(-1)], [['All 2', true], null])
    one.draw({ shown: false })
    check('hidden: the count is the server\'s again', W.counts.at(-1), null)
    const reads = W.reloads.length
    one.draw({ shown: true })
    check('shown again later: the library read again underneath, once', W.reloads.length - reads, 1)
  }
  {
    //? a facet that empties while the page is HIDDEN (its read landing under another tab): the router
    //? rewrites the tab that shows, so the address is told only once the page shows again
    reset()
    libraryOf(LIBRARY)
    const hid = mount({ facet: 'misfiled' })
    hid.draw()
    hid.draw({ shown: false })
    libraryOf([RIP, COVERLESS].map((one) => ({ ...one, issues: one.issues.filter((c) => c !== 'misfiled') })))
    hid.draw()
    check('a facet emptied while hidden: the address not told yet', hid.facetsAsked, [])
    hid.draw({ shown: true })
    check('...shown again: the address says All', hid.facetsAsked, [null])

    //? gone with NO session (back from a real scan): the page's count cleared, the server's again
    reset()
    libraryOf(LIBRARY)
    const gone = mount()
    gone.draw()
    check('a real scan, no session: the page\'s count', W.counts.at(-1), 4)
    gone.unmount()
    check('...the page gone (back) with no session: the count the server\'s again', W.counts.at(-1), null)
  }

  console.log('\nthe page: a session')
  {
    reset()
    libraryOf(LIBRARY)
    const one = mount()
    one.draw()
    click(rowButtons()[2])
    one.draw()
    const first = one.edits[0]
    check('a row clicked: the panel asked for its folder, read again underneath, with the queue\'s place',
      [first.request.folder, first.request.reread, first.request.queue.position, first.request.queue.total, first.opener.tag.startsWith('Third rip')],
      [RIP.path, true, 3, 4, true])
    check('...the row Explorer\'s selection, aria-current', rowButtons().map((row) => [row.props.class.includes('is-current'), row.props['aria-current'] ?? null]),
      [[false, null], [false, null], [true, 'true'], [false, null]])
    check('...and the count the server\'s while the session lasts', W.counts.at(-1), null)

    //? the album fixed, and re-filed, by the panel: its row in its place, saying so
    first.request.onChange({ from: RIP.path, album: { ...RIP, path: 'Portishead/Third (2008)', album: 'Third', issues: [], needs_attention: false }, deleted: false, wrote: true })
    libraryOf(LIBRARY.filter((one) => one !== RIP))
    one.draw()
    check('a write: the row says Fixed, in its place - the scan dropping it moves nothing', [rowAlbums(), rowMarks()],
      [['BULLY (2025)', 'Currents (2015)', 'Third', 'Dummy (1994)'], [null, null, 'Fixed', null]])
    check('...faded, its word not', rowButtons()[2].props.class.includes('is-done'), true)

    first.request.queue.onNext()
    one.draw()
    await settle()
    const second = one.edits[1]
    check('Next: the album left marked reviewed by its new path, the count asked again', [W.reviewed, W.asked], [['Portishead/Third (2008)'], 1])
    check('...the panel asked for the next folder, not read again, its place moved on', [second.request.folder, second.request.reread, second.request.queue.position, second.opener !== undefined],
      [COVERLESS.path, false, 4, true])
    check('...and the selection moved with it', rowButtons().map((row) => row.props.class.includes('is-current')), [false, false, false, true])

    second.request.onChange({ from: COVERLESS.path, album: null, deleted: true, wrote: true })
    one.draw()
    check('a delete: the row says Deleted', rowMarks()[3], 'Deleted')
    click(rowButtons()[0])
    one.draw()
    await settle()
    check('another row clicked: no review for the one deleted; the panel on the row clicked', [W.reviewed, one.edits[2].request.folder, one.edits[2].request.queue.position],
      [['Portishead/Third (2008)'], NEW_BROKEN.path, 1])
    one.edits[2].request.queue.onPrevious()
    one.draw()
    check('Previous at the first: nothing', [one.edits.length, W.reviewed.length], [3, 1])

    click(rowButtons()[0])
    one.draw()
    check('its own row clicked again: the panel closes', one.closes.length, 1)
    await settle()
    check('...the session ends: the album left marked reviewed, a fresh scan asked for, the rows held meanwhile',
      [W.reviewed.at(-1), W.reloads.length, rowMarks()], [NEW_BROKEN.path, 1, [null, null, 'Fixed', 'Deleted']])
    libraryOf([NEW_CLEAN, { ...NEW_BROKEN, reviewed: true }, IGNORED, CLEAN])
    W.reloads.shift().resolve([])
    await settle()
    one.draw()
    check('...and once it lands, the list worked out again from it - the new import first', rowAlbums(), ['Currents (2015)', 'BULLY (2025)'])
    check('...no row selected, the count the page\'s again', [rowButtons().some((row) => row.props.class.includes('is-current')), W.counts.at(-1)], [false, 2])
  }

  console.log('\nthe page: how else a session ends')
  {
    reset()
    libraryOf(LIBRARY)
    const one = mount()
    one.draw()
    click(rowButtons()[1])
    one.draw()
    one.draw({ editing: null })
    await settle()
    check('the panel closed (Close, Escape, another panel, the page left): the album left marked reviewed, the list read again',
      [W.reviewed, W.reloads.length], [[NEW_CLEAN.path], 1])

    reset()
    libraryOf(LIBRARY)
    const two = mount()
    two.draw()
    click(rowButtons()[2])
    two.draw()
    click(find((node) => byClass('app-queue-facet')(node) && words(node).startsWith('Newly'))[0])
    two.draw()
    await settle()
    check('a facet chosen in a session: it ends - reviewed, the panel closed - and the address told', [W.reviewed, two.closes.length, two.facetsAsked], [[RIP.path], 1, ['new']])

    reset()
    libraryOf(LIBRARY)
    const three = mount()
    three.draw()
    click(rowButtons()[2])
    three.draw()
    libraryOf(LIBRARY.filter((one) => one !== COVERLESS))
    three.draw()
    three.edits[0].request.queue.onNext()
    three.draw()
    await settle()
    check('an album gone when stepped to (deleted outside): the session ends, the panel closes, the one left reviewed',
      [three.closes.length, W.reviewed, three.edits.length], [1, [RIP.path], 1])

    reset()
    libraryOf(LIBRARY)
    const four = mount()
    four.draw()
    click(rowButtons()[0])
    four.draw()
    four.unmount()
    await settle()
    check('the page gone with a session on (back): the album left marked reviewed, the count the server\'s', [W.reviewed, W.counts.at(-1)], [[NEW_BROKEN.path], null])
  }

  console.log('\nthe page: after review')
  {
    //? the fresh scan is asked only once the album left has been noted reviewed - else it can still
    //? count it (a new import keeping its New chip, and the page's count beating the server's)
    reset()
    libraryOf(LIBRARY)
    W.holdMarks = true
    const one = mount()
    one.draw()
    click(rowButtons()[1])
    one.draw()
    one.draw({ editing: null })
    await settle()
    check('the panel closed: the album noted - and NO scan asked until the note is written', [W.reviewed, W.reloads.length], [[NEW_CLEAN.path], 0])
    check('...the rows held meanwhile, each refused and seen to be (aria-disabled)', rowButtons().map((row) => row.props['aria-disabled'] ?? null), ['true', 'true', 'true', 'true'])
    click(rowButtons()[3])
    one.draw()
    check('...a row clicked then begins nothing', one.edits.length, 1)
    W.marks.shift()()
    await settle()
    check('the note written: now the scan is asked', W.reloads.length, 1)

    //? the ending's read answered while a scan gathered after a write is still out: its albums were
    //? never written - so the rows stay until that one lands, never the list from before the session
    libraryOf(LIBRARY, { loading: true })
    W.reloads.shift().resolve([])
    await settle()
    one.draw()
    check('...answered with another read still out: the rows still held, still refused', [rowAlbums(), rowButtons()[0].props['aria-disabled']],
      [['BULLY (2025)', 'Currents (2015)', 'Third rip', 'Dummy (1994)'], 'true'])
    libraryOf([NEW_BROKEN, COVERLESS])
    one.draw()
    check('...no read out: the list worked out again from what is in, the rows taken again', [rowAlbums(), rowButtons()[0].props['aria-disabled'] ?? null],
      [['BULLY (2025)', 'Dummy (1994)'], null])

    //? go()'s own ending (an album gone when stepped to) waits for its note too
    reset()
    libraryOf(LIBRARY)
    W.holdMarks = true
    const two = mount()
    two.draw()
    click(rowButtons()[2])
    two.draw()
    libraryOf(LIBRARY.filter((album) => album !== COVERLESS))
    two.draw()
    two.edits[0].request.queue.onNext()
    two.draw()
    await settle()
    check('an album gone when stepped to: the one left noted, the scan waiting for it', [W.reviewed, W.reloads.length], [[RIP.path], 0])
    W.marks.shift()()
    await settle()
    check('...then asked', W.reloads.length, 1)
  }

  console.log('\nthe page: the chips while a session lasts')
  {
    reset()
    libraryOf(LIBRARY)
    const one = mount({ facet: 'no_art' })
    one.draw()
    click(rowButtons()[1])
    one.draw()
    //? the session's last coverless album fixed, the page's own scan rescanned (a write announced)
    libraryOf(LIBRARY.map((album) => ({ ...album, issues: album.issues.filter((code) => code !== 'no_art') })))
    one.draw()
    check('the chips as the session began, its facet pressed - none vanishing, none shifting, no count moving',
      facetChips(), [['All 4', false], ['Newly added 2', false], ['folder off-convention 2', false], ['no cover 2', true], ['no release 1', false]])
    one.draw({ editing: null })
    await settle()
    check('...and while its rows are held, still', facetChips()[3], ['no cover 2', true])
    W.reloads.shift().resolve([])
    await settle()
    one.draw()
    check('...the fresh scan in: the chips worked out again', facetChips().map(([label]) => label).includes('no cover 2'), false)
  }

  console.log('\nthe page: a facet, a row\'s words, a cover that fails, Try again')
  {
    reset()
    libraryOf(LIBRARY.map((album) => ({ ...album, issues: album.issues.filter((code) => code !== 'misfiled') })), { stale: true })
    const one = mount({ facet: 'misfiled' })
    one.draw()
    check('a facet the SAVED scan lacks: the address left alone until a real scan says so', one.facetsAsked, [])
    libraryOf(W.library.albums)
    one.draw()
    check('...the real scan agreeing: the address says All', one.facetsAsked, [null])

    const SPLIT = album('Radiohead/In Rainbows (Disc 4)', { ...issues(['no_art']), art: '', edition: 'Discbox', disc_label: 'Disc 4' })
    const COVERED = album('Portishead/Third (2008)', { ...issues(['misfiled']), edition: 'Made in Germany' })
    libraryOf([SPLIT, COVERED])
    one.draw({ facet: null })
    check('a row\'s second line: the artist, then disc_label before the edition', classed('app-queue-artist').map(words), ['Portishead · Made in Germany', 'Radiohead · Disc 4'])
    const img = find((node) => node.type === 'img', rowButtons()[0])[0]
    img.props.onError()
    one.draw()
    check('a cover that fails to load: the plain tile instead', [find((node) => node.type === 'img', rowButtons()[0]).length, find(byClass('is-empty'), rowButtons()[0]).length], [0, 1])

    libraryOf([], { error: 'HTTP 502', loading: true })
    one.draw()
    const retry = find((node) => node.type === 'button' && words(node) === 'Try again')[0]
    const reads = W.reloads.length
    check('Try again while a read is out: aria-disabled, never disabled (focus stays on it)', [retry.props['aria-disabled'], retry.props.disabled ?? null], ['true', null])
    click(retry)
    check('...and the tap refused', W.reloads.length - reads, 0)
    libraryOf([], { error: 'HTTP 502' })
    one.draw()
    click(find((node) => node.type === 'button' && words(node) === 'Try again')[0])
    check('...ready again: it reads the library', W.reloads.length - reads, 1)
  }
}

/* ===== the count's store: app/useQueueSummary.ts itself, against a faked deadwax ===== */

async function store() {
  console.log('\nthe count\'s store (the real useQueueSummary.ts)')
  const DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-needslook-store-'))
  execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
    'src/app/useQueueSummary.ts', '--rootDir', 'src', '--outDir', DIR,
    '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
    '--lib', 'es2022,dom', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
  ], { cwd: UI, stdio: 'inherit' })
  fs.mkdirSync(path.join(DIR, 'node_modules/preact'), { recursive: true })
  fs.writeFileSync(path.join(DIR, 'node_modules/preact/hooks.js'), `exports.useState = (v) => [v, () => {}]\nexports.useEffect = () => {}\n`)
  //? deadwax answering when the test says, and the downloads' "an album was filed"
  fs.writeFileSync(path.join(DIR, 'api/library.js'), `
exports.queueSummary = () => new Promise((resolve, reject) => globalThis.__store.asks.push({ resolve, reject }))
`)
  fs.writeFileSync(path.join(DIR, 'lib/libraryEvents.js'), `
exports.onAlbumsFiled = (listener) => { globalThis.__store.filed.push(listener); return () => {} }
`)
  const S = globalThis.__store = { asks: [], filed: [] }
  const Q = require(path.join(DIR, 'app/useQueueSummary.js'))
  const answer = async (reply) => { const ask = S.asks.shift(); if (reply instanceof Error) ask.reject(reply); else ask.resolve(reply); await settle() }

  check('nothing known before deadwax has said: null, never 0', Q.queueCountNow(), null)
  check('nothing heard of filings until something asks', S.filed.length, 0)
  Q.askQueueSummary()
  check('an ask: one request out, and filings heard from now on', [S.asks.length, S.filed.length], [1, 1])
  Q.askQueueSummary()
  Q.askQueueSummary()
  check('asked twice more meanwhile: still one request out', S.asks.length, 1)
  await answer({ total: 3, imports: 1, known: true })
  check('it answers: the count, and exactly ONE more asked after it', [Q.queueCountNow(), S.asks.length], [3, 1])
  await answer({ total: 2, imports: 0, known: true })
  check('...which answers last, the newest question\'s; nothing more asked', [Q.queueCountNow(), S.asks.length], [2, 0])
  Q.askQueueSummary()
  await answer(new Error('HTTP 502'))
  check('a failed ask keeps the last number', Q.queueCountNow(), 2)
  Q.setPageQueueCount(5)
  check('the page\'s own count stands in while it knows better', Q.queueCountNow(), 5)
  Q.askQueueSummary()
  await answer({ total: 4, imports: 0, known: true })
  check('...even over a newer answer from the server', Q.queueCountNow(), 5)
  Q.setPageQueueCount(null)
  check('the page stops knowing better: the server\'s number again', Q.queueCountNow(), 4)
  S.filed[0]()
  check('an album filed: asked again', S.asks.length, 1)
  await answer({ total: 5, imports: 1, known: true })
  check('...and the count moves', Q.queueCountNow(), 5)
  check('the filing listener added once, however many asks', S.filed.length, 1)
  return DIR
}

async function storeFailingFirst(DIR) {
  //? a fresh module: the first ask failing leaves the count unknown, never 0
  delete require.cache[require.resolve(path.join(DIR, 'app/useQueueSummary.js'))]
  const S = globalThis.__store = { asks: [], filed: [] }
  const Q = require(path.join(DIR, 'app/useQueueSummary.js'))
  Q.askQueueSummary()
  S.asks.shift().reject(new Error('down'))
  await settle()
  check('a first ask that fails: still null - no badge of 0 over an unknown', Q.queueCountNow(), null)
}

page().then(store).then(storeFailingFirst).then(() => {
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})
