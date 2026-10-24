/**
 * Inside a track, in the app (2.0.0-player.44): the pure rules - lib/trackInspector.ts (what the Edit
 * panel's track inspector says of a track) and lib/albumProperties.ts (an album page's Properties) - and
 * the parts themselves, compiled with the repo's TypeScript and rendered by a small stand-in for Preact
 * that keeps each component's hooks apart (the inspector draws two of its own, each with state): the
 * track inspector (app/TrackInspector.tsx), the cover viewer round the main page's ArtViewer
 * (app/CoverViewer.tsx) and Properties (app/AlbumProperties.tsx).
 *
 * What it pins:
 *
 *  - THE FIELDS: every field the main page's track viewer offers (lib/trackFields.ts's registry - not
 *    only the ones its Fields menu shows), each once, grouped Tags, Audio, MusicBrainz, File in the
 *    registry's order; the file's own value where it has been read (it wins over the scan's), the scan's
 *    until then, '' for a field the file lacks, `waiting` only for a field the scan can't fill while the
 *    file is still being read; the dimmed disc 1 of a file with no disc tag, saying why.
 *  - THE WORDS: where the track sits ("Track 2", "Unnumbered, disc 2 of 2 · <disc title>", its length and
 *    format), Previous's and Next's tracks and "2 of 3", a picture's bytes and facts, the main page's
 *    words for no pictures and no lyrics (Get lyrics in the Lyrics tab), where lyrics came from, what
 *    lyrics are read again on, "All tags in this file (N)", a title that is the file's name.
 *  - PROPERTIES: nothing until the bridge has answered (or failed); the year against this pressing's;
 *    the size only when every folder said (a set's added); the release linked - "not tagged" only once
 *    the album's own answer from Navidrome has SAID there is none ('' - review: the bridge's null is also
 *    its answer for an album id Navidrome doesn't have, or a Navidrome it couldn't ask); the earliest
 *    first seen ("Added" since 2.0.5), downloaded here when any folder was; the release as "MusicBrainz: View this
 *    pressing" (2.0.5), and the no-release line only for whoever can Edit albums.
 *  - (review) BACK TO THE LIST: the least scroll that brings the track focus goes back to into view
 *    (lib/trackInspector.ts revealBy) - nothing for a row in view, down to its bottom, up to its top.
 *  - THE INSPECTOR, RENDERED: its title, place and count; for a screen reader, a polite status line always
 *    first in it saying the track and where it is (stepping changes its words), Back described by it;
 *    every field's label once, in order, its value
 *    or a dash - or, for a field only the file carries while the file is read, '…' (review) - mono only for a value, the inferred disc dimmed with its reason; Previous and Next
 *    aria-disabled at the ends (still focusable) and refusing a click there, each handing the panel the
 *    track either side; "Edit this track…" the tag editor on this one file; Back; the pictures with their
 *    facts, the pixel size once loaded, a tap opening that picture alone in the cover viewer (its opener
 *    taken in the tap); "All tags in this file" every raw tag and the file's name; a read error said;
 *    the lyrics - asked with a signal, synced lines with their times and the gaps between verses, where
 *    they came from, none, an error - through latestOnly(): a step on calls the last track's off, and
 *    its answer landing late draws nothing.
 *  - THE COVER VIEWER: its own scroll lock on <html> while it shows (let go as it closes, and as it goes);
 *    focus to its Close button as it opens and back to its opener as it closes; Tab kept inside it; a
 *    move through the history (popstate, hashchange) closing it while it shows, through the close it was
 *    given last, and nothing listening once it is shut or gone (review: an album page in a hidden tab
 *    stays mounted, and its viewer would have kept its lock and taken the page's next Escape).
 *  - PROPERTIES, RENDERED: nothing for no rows; label and value rows; the release a link opening beside
 *    the app (target="_blank" rel="noopener") to its musicbrainz.org page.
 *
 * Run it with:  node ui/test/inspector.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')

let failures = 0
let checks = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  checks++
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
const settle = () => new Promise((resolve) => setImmediate(() => setImmediate(resolve)))

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-inspector-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/trackInspector.ts', 'src/lib/albumProperties.ts', 'src/app/TrackInspector.tsx', 'src/app/CoverViewer.tsx', 'src/app/AlbumProperties.tsx',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects; hooks kept per component instance (by where it is drawn), effects run on commit,
//? and an instance no longer drawn unmounted - its effects' cleanups run
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
let current = null
const instances = new Map()
let drawn = new Set()
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useCallback = (f, deps) => exports.useMemo(() => f, deps)
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.__begin = () => { drawn = new Set() }
exports.__render = (key, fn, props) => {
  let inst = instances.get(key)
  if (!inst) { inst = { slots: [], effects: [], cursor: 0 }; instances.set(key, inst) }
  drawn.add(key)
  const outer = current; current = inst; inst.cursor = 0
  try { return fn(props) } finally { current = outer }
}
exports.__commit = () => {
  for (const [key, inst] of [...instances]) {
    if (drawn.has(key)) continue
    for (const s of inst.slots) if (s && typeof s.cleanup === 'function') s.cleanup()
    instances.delete(key)
  }
  for (const inst of instances.values()) for (const s of inst.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() }
}
exports.__reset = () => { for (const inst of instances.values()) for (const s of inst.slots) if (s && typeof s.cleanup === 'function') s.cleanup(); instances.clear() }
`)

const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
const I = globalThis.__inspector = { lyrics: [], openers: [] }
//? deadwax, as the test answers it: each lyrics request kept with its track and signal, answered by hand
write('api/library.js', `
exports.trackLyrics = (path, filename, signal) => new Promise((resolve, reject) => globalThis.__inspector.lyrics.push({ path, filename, signal, resolve, reject }))
`)
write('components/ArtViewer.js', `exports.ArtViewer = function ArtViewer(props) { return { type: 'art-viewer', props } }\n`)
write('components/Loading.js', `exports.Loading = ({ label }) => ({ type: 'span', props: { class: 'loading-blocks', role: 'status', children: label } })\n`)
write('player/icons.js', `exports.ChevronLeftIcon = function Icon() { return null }\nexports.ChevronRightIcon = function Icon() { return null }\n`)
write('app/useSheet.js', `exports.takeOpener = (event) => { globalThis.__inspector.openers.push(event.currentTarget); return event.currentTarget }\n`)

const T = require(path.join(OUT, 'lib/trackInspector.js'))
const P = require(path.join(OUT, 'lib/albumProperties.js'))
const { TRACK_FIELDS, FIELD_GROUPS } = require(path.join(OUT, 'lib/trackFields.js'))
const { formatSize } = require(path.join(OUT, 'lib/format.js'))
const { TrackInspector } = require(path.join(OUT, 'app/TrackInspector.js'))
const { CoverViewer, VIEWER_LOCK } = require(path.join(OUT, 'app/CoverViewer.js'))
const { AlbumProperties } = require(path.join(OUT, 'app/AlbumProperties.js'))
const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))

/* ===== the stand-in's tree ===== */

function expand(node, key) {
  if (node === null || node === undefined || typeof node !== 'object') return node
  if (Array.isArray(node)) return node.map((child, index) => expand(child, `${key}/${child && child.key !== undefined && child.key !== null ? `k${child.key}` : index}`))
  if (typeof node.type === 'function') {
    const here = `${key}/${node.type.name}`
    return expand(hooks.__render(here, node.type, node.props), here)
  }
  return { ...node, props: { ...node.props, children: expand(node.props?.children, `${key}/${node.type}`) } }
}
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
  if (typeof node.type !== 'string' && node.type !== 'fragment') return ''
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const classed = (name, within) => find(byClass(name), within)
const one = (name, within) => classed(name, within)[0]

/** A component drawn, its effects committed - twice, so state an effect set is drawn. `between` runs after
 *  the first render and before its effects (a ref a test fills in, as the DOM would). */
function mount(component) {
  let tree = null
  const draw = (props, between) => {
    hooks.__begin()
    tree = expand({ type: component, props, key: null }, 'root')
    if (between) between(tree)
    hooks.__commit()
    hooks.__begin()
    tree = expand({ type: component, props, key: null }, 'root')
    hooks.__commit()
    return tree
  }
  return { draw, tree: () => tree }
}

/* ===== the album ===== */

const TRACKS = [
  { filename: '01 - Mysterons.flac', title: 'Mysterons', has_title_tag: true, position: 1, disc: 1, length: 306, size: 4686904, format: 'flac',
    artist: 'Portishead', album: 'Dummy', albumartist: 'Portishead', date: '1994-08-22', originaldate: '1994', release_mbid: 'rel-scan' },
  { filename: '02 - Sour Times.flac', title: 'Sour Times', has_title_tag: true, position: 2, disc: null, length: 254, size: 3919784, format: 'flac',
    artist: 'Portishead', album: 'Dummy', albumartist: 'Portishead', date: '1994-08-22', originaldate: '1994', release_mbid: 'rel-scan' },
  { filename: 'track03.flac', title: 'track03', has_title_tag: false, position: null, disc: 2, length: 0, size: 100, format: 'mp3',
    artist: 'Portishead', album: 'Dummy', albumartist: 'Portishead', date: '', originaldate: '', release_mbid: '' },
]
const ALBUM = {
  path: 'Portishead/Dummy (1994)', artist: 'Portishead', album: 'Dummy', disc_count: 2, disc_titles: { 2: 'Bonus' }, modified_at: 5,
  lyrics_count: 1, track_count: 3, tracks: TRACKS,
}
const SOUR = {
  filename: '02 - Sour Times.flac', format: 'flac', size: 3919784, length: 254, bitrate: 1411000, sample_rate: 44100, bits_per_sample: 16, channels: 2,
  codec: 'FLAC', position: 2, disc: null,
  tags: { title: 'Sour Times', artist: 'Portishead', genre: 'Trip hop', musicbrainz_albumid: 'rel-file' },
  raw: [['TITLE', 'Sour Times'], ['GENRE', 'Trip hop']],
  pictures: [
    { index: 0, type: 3, label: 'Front cover', mime: 'image/jpeg', size: 61234, description: '' },
    { index: 1, type: 6, label: 'Media (the disc itself)', mime: 'image/png', size: 2 * 1024 * 1024 + 1, description: '' },
  ],
}

console.log('\nthe fields: every one the main page offers, grouped, the file\'s value over the scan\'s')
{
  const groups = T.inspectorGroups(TRACKS[1], SOUR, false)
  check('four groups, the main page\'s, in its order', groups.map((group) => group.name), ['Tags', 'Audio', 'MusicBrainz', 'File'])
  check('every field of the registry, each once, in its order - not only the Fields menu\'s',
    groups.flatMap((group) => group.fields.map((field) => field.id)), TRACK_FIELDS.map((field) => field.id))
  check('...each under its own group', groups.every((group) => group.fields.every((field) => TRACK_FIELDS.find((f) => f.id === field.id).group === group.name)), true)
  check('...and there are dozens of them', TRACK_FIELDS.length >= 30 && FIELD_GROUPS.length === 4, true)
  const value = (id, from = groups) => from.flatMap((group) => group.fields).find((field) => field.id === id)
  check('the file\'s own tags: genre, and the release id where the file and the scan differ (the file wins)',
    [value('genre').value, value('musicbrainz_albumid').value], ['Trip hop', 'rel-file'])
  check('what the file says of its audio', ['bitrate', 'sample_rate', 'bits', 'channels', 'codec'].map((id) => value(id).value), ['1411 kbps', '44.1 kHz', '16-bit', 'Stereo', 'FLAC'])
  check('its pictures, its size and its name', [value('pictures').value, value('size').value, value('filename').value], ['Front cover +1', formatSize(3919784), '02 - Sour Times.flac'])
  check('a field the file lacks is "" - and not waiting, the file being read', [value('composer').value, value('composer').waiting], ['', false])
  check('mono where the main page sets it', [value('isrc').mono, value('artist').mono], [true, false])
  check('the disc of a file with no disc tag: 1, inferred, saying why', [value('disc').value, value('disc').inferred], ['1', 'No disc number on the file - it reads as disc 1'])
  const tagged = T.inspectorGroups(TRACKS[0], undefined, false)
  check('...one with a disc number is no inference', [value('disc', tagged).value, value('disc', tagged).inferred], ['1', null])
  const reading = T.inspectorGroups(TRACKS[1], undefined, true)
  check('the file still being read: what only the file carries waits, what the scan has shows',
    [value('genre', reading).waiting, value('genre', reading).value, value('artist', reading).waiting, value('artist', reading).value, value('musicbrainz_albumid', reading).value],
    [true, '', false, 'Portishead', 'rel-scan'])
  const failed = T.inspectorGroups(TRACKS[1], undefined, false)
  check('...no longer being read (a failed read): nothing waits', value('genre', failed).waiting, false)
}

console.log('\nthe words')
{
  check('where it sits: its number, its length and format', T.trackPlace(ALBUM, TRACKS[1]), 'Track 2 · 4:14 · FLAC')
  check('...a disc of a set, with its title - and a file with no number', T.trackPlace(ALBUM, TRACKS[2]), 'Unnumbered, disc 2 of 2 · Bonus · MP3')
  check('...disc 1, untitled', T.trackPlace(ALBUM, TRACKS[0]), 'Track 1, disc 1 of 2 · 5:06 · FLAC')
  check('Previous and Next: either side, none at the ends, nothing for a track not there',
    ['01 - Mysterons.flac', '02 - Sour Times.flac', 'track03.flac', 'gone.flac'].map((name) => {
      const steps = T.trackSteps(ALBUM, name)
      return [steps.before, steps.after, T.stepWords(steps)]
    }),
    [[null, '02 - Sour Times.flac', '1 of 3'], ['01 - Mysterons.flac', 'track03.flac', '2 of 3'], ['02 - Sour Times.flac', null, '3 of 3'], [null, null, '']])
  check('the title: the file\'s tag once read, else the scan\'s', [T.trackTitle(TRACKS[1], undefined), T.trackTitle(TRACKS[1], { ...SOUR, tags: { title: 'Sour Times (live)' } })],
    ['Sour Times', 'Sour Times (live)'])
  check('a title that is the file\'s name: the scan says so until the file is read, then the file does',
    [T.untitled(TRACKS[2], undefined), T.untitled(TRACKS[1], undefined), T.untitled(TRACKS[1], { ...SOUR, tags: {} }), T.untitled(TRACKS[2], { ...SOUR, tags: { title: 'Named' } })],
    [true, false, true, false])
  check('a picture\'s bytes: KB under a megabyte, never 0', [T.pictureBytes(61234), T.pictureBytes(10), T.pictureBytes(2 * 1024 * 1024 + 1)], ['60 KB', '1 KB', formatSize(2 * 1024 * 1024 + 1)])
  check('a picture\'s facts: pixels once loaded, bytes, format', [T.pictureFacts(SOUR.pictures[0], '600 × 600'), T.pictureFacts(SOUR.pictures[1], undefined)],
    ['600 × 600 · 60 KB · JPEG', `${formatSize(2 * 1024 * 1024 + 1)} · PNG`])
  check('no pictures, in the main page\'s words', T.NO_PICTURES, "None - a player shows the album's cover for this song, or its CD art if the song has a disc number.")
  check('no lyrics - and where Get lyrics is while some tracks have none (the Lyrics tab)',
    [T.noLyricsWords({ lyrics_count: 1, track_count: 3 }), T.noLyricsWords({ lyrics_count: 3, track_count: 3 })],
    ['No lyrics for this track on disk. Get lyrics, in the Lyrics tab, looks for them on LRCLIB.', 'No lyrics for this track on disk.'])
  check('where lyrics came from', [T.lyricsSource({ source: 'file', lyrics_file: '01 - Mysterons.lrc' }), T.lyricsSource({ source: 'embedded', lyrics_file: null })],
    ['From 01 - Mysterons.lrc', 'Embedded in the file'])
  const key = T.lyricsKey(ALBUM, 'a.flac')
  check('lyrics read again on a new .lrc (the folder\'s mtime, the scan\'s count) and for another track',
    [key === T.lyricsKey({ ...ALBUM }, 'a.flac'), key === T.lyricsKey({ ...ALBUM, modified_at: 6 }, 'a.flac'), key === T.lyricsKey({ ...ALBUM, lyrics_count: 2 }, 'a.flac'), key === T.lyricsKey(ALBUM, 'b.flac')],
    [true, false, false, false])
  check('"All tags in this file", with the count once read', [T.rawTagsTitle(undefined), T.rawTagsTitle(SOUR)], ['All tags in this file', 'All tags in this file (2)'])
  check('(review) what a screen reader is told: the name the list showed, and where it is',
    [T.trackNow(TRACKS[1], T.trackSteps(ALBUM, TRACKS[1].filename)), T.trackNow({ title: '', filename: 'track03.flac' }, { at: 2, count: 3 }), T.trackNow(TRACKS[0], { at: -1, count: 3 })],
    ['Sour Times, 2 of 3', 'track03.flac, 3 of 3', 'Mysterons'])
}

console.log('\n(review) back to the list: the track focus goes to brought into view, the least scroll that does it')
{
  const box = { top: 100, bottom: 400 }
  check('a row in view: nothing', [T.revealBy(box, { top: 100, bottom: 136 }), T.revealBy(box, { top: 250, bottom: 286 }), T.revealBy(box, { top: 364, bottom: 400 })], [0, 0, 0])
  check('below the box (Next moved on past the rows in view): down to its bottom', T.revealBy(box, { top: 561, bottom: 597 }), 197)
  check('...partly below: just the part out of view', T.revealBy(box, { top: 380, bottom: 416 }), 16)
  check('above the box (Previous moved back past them): up to its top', [T.revealBy(box, { top: 20, bottom: 56 }), T.revealBy(box, { top: 90, bottom: 126 })], [-80, -10])
  check('...a row taller than the box: its top', T.revealBy(box, { top: 450, bottom: 900 }), 350)
}

console.log('\nan album page\'s Properties')
{
  const row = (more) => ({ id: 1, path: 'Portishead/Dummy (1994)', release_mbid: 'r', artist: 'Portishead', album: 'Dummy', edition: '', year: '2014', formats: ['flac'], track_count: 10, ...more })
  const answer = (present, release = 'f5804905-6e8d-45dc-bae9-b36c64ccc99b') => ({ release_mbid: release, release_group_mbid: null, navidrome_id: 'nd', present, other_pressings: [] })
  check('nothing until the bridge has answered or failed', [P.albumProperties(null, false, 'x'), P.albumProperties(null, true, undefined)], [null, []])
  const vinyl = answer([row({ original_year: '1994', size: 45 * 1024 * 1024, first_seen: '2026-10-14T12:24:29+00:00', imported: true })])
  //? (2.0.5, UX batch 2) in a listener's words: "MusicBrainz: View this pressing ↗" - a link, never the raw id - and
  //? "Added", ", downloaded here" for one deadwax filed
  check('the year against this pressing\'s, the size, the release linked (its words, never its id), when it was added and that deadwax downloaded it',
    P.albumProperties(vinyl, false, 'ignored', 'en-GB'),
    [{ label: 'Year', text: '1994 (this pressing 2014)' }, { label: 'Size', text: '45 MB' },
      { label: 'MusicBrainz', text: 'View this pressing \u2197', release: 'f5804905-6e8d-45dc-bae9-b36c64ccc99b' },
      { label: 'Added', text: '14 October 2026, downloaded here' }])
  const set = answer([row({ path: 'A (Disc 1)', size: 10 * 1024 * 1024, first_seen: '2026-10-14T12:00:00+00:00', imported: false, original_year: '' }),
    row({ path: 'A (Disc 2)', size: 20 * 1024 * 1024, first_seen: '2025-01-02T12:00:00+00:00', imported: true, original_year: '' })])
  check('a set kept one folder per disc: its sizes added, the earliest added, downloaded here when any folder was',
    P.albumProperties(set, false, undefined, 'en-GB').filter((one) => one.label !== 'MusicBrainz'),
    [{ label: 'Year', text: '2014' }, { label: 'Size', text: '30 MB' }, { label: 'Added', text: '2 January 2025, downloaded here' }])
  const half = answer([row({ size: 10 }), row({ path: 'B', size: null })])
  check('...no size when a folder of it didn\'t say - half a set is no size', P.albumProperties(half, false, undefined).some((one) => one.label === 'Size'), false)
  check('found by a scan: added, not downloaded here', P.albumProperties(answer([row({ first_seen: '2026-01-05T12:00:00+00:00', imported: false })]), false, undefined, 'en-GB').at(-1),
    { label: 'Added', text: '5 January 2026' })
  const NONE = [{ label: 'MusicBrainz', text: 'Not matched to a release - match it in Edit album', quiet: true }]
  check('no release - the album\'s own answer saying none (Navidrome\'s \'\'), the bridge with none too: said, quietly, to whoever can Edit albums (2.0.5)',
    P.albumProperties(answer([], null), false, '', undefined, true), NONE)
  check('...and to nobody else: a listener can do nothing about it (2.0.5)', [P.albumProperties(answer([], null), false, ''), P.albumProperties(answer([], null), false, '', undefined, false)], [[], []])
  //? (review) the bridge's null is also what it answers when Navidrome couldn't be asked, or has no album by
  //? that id (an old address after a rescan, "Navidrome has nothing by that id" above it): not a "none"
  check('(review) the bridge answering with none, the album\'s own answer not come or failed: nothing said of the release',
    [P.albumProperties(answer([], null), false, undefined), P.albumProperties(answer([], null), false, null)], [[], []])
  check('(review) ...and the album\'s own release, once it comes, linked over the bridge\'s null',
    P.albumProperties(answer([], null), false, 'mb-own'), [{ label: 'MusicBrainz', text: 'View this pressing \u2197', release: 'mb-own' }])
  check('the bridge failed: the album\'s own release, its own "none" (\'\'), or nothing said while its answer hasn\'t come',
    [P.albumProperties(null, true, 'mb-own', undefined, true), P.albumProperties(null, true, '', undefined, true), P.albumProperties(null, true, undefined, undefined, true)],
    [[{ label: 'MusicBrainz', text: 'View this pressing \u2197', release: 'mb-own' }], NONE, []])
  check('the year in words', [P.yearWords('2014', '1994'), P.yearWords('1994', '1994'), P.yearWords('1994', ''), P.yearWords('', '1994'), P.yearWords('', '')],
    ['1994 (this pressing 2014)', '1994', '1994', '1994', ''])
  check('a first seen that isn\'t a date says nothing', [P.firstSeenWords('soon', true), P.firstSeenWords(null, false)], ['', ''])
  check('the release\'s page', P.releaseUrl('f5804905-6e8d-45dc-bae9-b36c64ccc99b'), 'https://musicbrainz.org/release/f5804905-6e8d-45dc-bae9-b36c64ccc99b')
}

console.log('\nProperties, rendered')
{
  check('no rows, nothing drawn', [AlbumProperties({ rows: null }), AlbumProperties({ rows: [] })], [null, null])
  const tree = expand(AlbumProperties({ rows: [{ label: 'Year', text: '1994' }, { label: 'MusicBrainz', text: 'View this pressing', release: 'abc' }, { label: 'Release', text: 'none', quiet: true }] }), 'p')
  check('its heading, and each line a label and a value', [words(one('app-props-title', tree)), classed('app-props-label', tree).map(words), classed('app-props-value', tree).map(words)],
    ['Properties', ['Year', 'MusicBrainz', 'Release'], ['1994', 'View this pressing', 'none']])
  const link = find((node) => node.type === 'a', tree)
  check('the release a link to its page, opening beside the app', link.map((node) => [node.props.href, node.props.target, node.props.rel]),
    [['https://musicbrainz.org/release/abc', '_blank', 'noopener']])
  //? (2.0.5) the link is words now ("View this pressing"), so it is in the text's own face, not the data face
  check('...in the text\'s face; a line saying what isn\'t there quieter', classed('app-props-value', tree).map((node) => node.props.class),
    ['app-props-value', 'app-props-value', 'app-props-value is-quiet'])
}

/* ===== the inspector, rendered ===== */

async function inspector() {
  console.log('\nthe inspector, rendered')
  //? a document for the cover viewer's lock, and a window for its history listeners, nothing more
  const locks = new Set()
  globalThis.document = { documentElement: { classList: { add: (name) => locks.add(name), remove: (name) => locks.delete(name) } }, activeElement: null }
  globalThis.window = historyWindow()
  const calls = { back: 0, step: [], edit: [] }
  const props = (filename, details = { files: new Map([['02 - Sour Times.flac', SOUR]]), loading: false, error: null }) => ({
    album: ALBUM, filename, details,
    onBack: () => { calls.back++ }, onStep: (name) => calls.step.push(name), onEdit: (name) => calls.edit.push(name),
  })
  const view = mount(TrackInspector)
  let tree = view.draw(props('02 - Sour Times.flac'))
  check('its title, where it sits and where it is among the album\'s', [words(one('app-inspect-title', tree)), words(one('app-inspect-place', tree)), words(one('app-inspect-count', tree))],
    ['Sour Times', 'Track 2 · 4:14 · FLAC', '2 of 3'])
  check('...no "file\'s name" note for a titled file', classed('app-inspect-note', tree).map(words).includes("No title tag - this is the file's name."), false)
  //? (review) a screen reader told which track shows: a polite region always there, Back described by it
  const nowLine = (within) => within.props.children[0]
  const live = nowLine(tree)
  check('(review) first in it, always there: a polite, atomic status line, out of sight, saying the track and where it is',
    [live.type, live.props.class, live.props.role, live.props['aria-live'], live.props['aria-atomic'], words(live)],
    ['p', 'app-visually-hidden', 'status', 'polite', 'true', 'Sour Times, 2 of 3'])
  check('...Back described by it, as the inspector opens with focus on Back', [!!live.props.id, one('app-inspect-back', tree).props['aria-describedby'] === live.props.id], [true, true])
  const groupNames = classed('app-inspect-heading', tree).map((node) => words(node))
  check('the four groups, then the pictures and the lyrics', groupNames.slice(0, 6), ['Tags', 'Audio', 'MusicBrainz', 'File', 'Pictures in this file', 'Lyrics'])
  const fieldList = classed('app-inspect-fields', tree).filter((node) => !node.props.class.includes('is-raw'))
  check('every field\'s label once, in the registry\'s order', fieldList.flatMap((list) => classed('app-inspect-label', list).map(words)), TRACK_FIELDS.map((field) => field.label))
  const valueOf = (label) => {
    const items = fieldList.flatMap((list) => list.props.children.flat(3)).filter(Boolean)
    const labels = fieldList.flatMap((list) => classed('app-inspect-label', list))
    const values = fieldList.flatMap((list) => classed('app-inspect-value', list))
    void items
    return values[labels.findIndex((node) => words(node) === label)]
  }
  check('a value, and a dash for a field the file lacks (in the words\' face, quieter)', [words(valueOf('Genre')), words(valueOf('Composer')), valueOf('ISRC').props.class],
    ['Trip hop', '—', 'app-inspect-value is-empty'])
  check('the data face only for a value', valueOf('File name').props.class, 'app-inspect-value is-mono')
  check('the disc 1 of a file with no disc tag: dimmed, its reason its tooltip', [words(valueOf('Disc')), valueOf('Disc').props.class.includes('is-inferred'), valueOf('Disc').props.title],
    ['1', true, 'No disc number on the file - it reads as disc 1'])

  const button = (name, within = tree) => one(name, within)
  check('Previous and Next live in the middle of the album', [button('app-inspect-prev').props['aria-disabled'], button('app-inspect-next').props['aria-disabled']], [undefined, undefined])
  button('app-inspect-prev').props.onClick()
  button('app-inspect-next').props.onClick()
  check('...each handing the panel the track either side', calls.step, ['01 - Mysterons.flac', 'track03.flac'])
  button('app-inspect-edit').props.onClick()
  button('app-inspect-back').props.onClick()
  check('"Edit this track…" the tag editor on this one file; Back the list', [calls.edit, calls.back, words(button('app-inspect-edit'))], [['02 - Sour Times.flac'], 1, 'Edit this track…'])

  //? the pictures: each with its facts, its pixels once its image has loaded, a tap opening it alone
  const pictures = classed('app-inspect-picture', tree)
  check('each picture in the file: its type and its facts', pictures.map((node) => [words(one('app-inspect-picture-label', node)), words(one('app-inspect-picture-facts', node))]),
    [['Front cover', '60 KB · JPEG'], ['Media (the disc itself)', `${formatSize(2 * 1024 * 1024 + 1)} · PNG`]])
  find((node) => node.type === 'img', pictures[0])[0].props.onLoad({ currentTarget: { naturalWidth: 600, naturalHeight: 600 } })
  tree = view.draw(props('02 - Sour Times.flac'))
  check('...its pixel size once it has loaded', words(one('app-inspect-picture-facts', classed('app-inspect-picture', tree)[0])), '600 × 600 · 60 KB · JPEG')
  check('...its picture from the track\'s picture route, versioned on the folder', find((node) => node.type === 'img', classed('app-inspect-picture', tree)[1])[0].props.src,
    '/deadwax/library/tracks/picture?album=Portishead%2FDummy%20(1994)&file=02%20-%20Sour%20Times.flac&index=1&v=5')
  check('the cover viewer shut until a picture is tapped', find((node) => node.type === 'art-viewer', tree).length, 0)
  const tapped = { tag: 'picture-button', focused: 0, focus() { this.focused++ } }
  classed('app-inspect-picture', tree)[1].props.onClick({ currentTarget: tapped })
  tree = view.draw(props('02 - Sour Times.flac'))
  const viewer = find((node) => node.type === 'art-viewer', tree)
  check('a tap opens THAT picture alone, labelled with the file - its opener taken in the tap',
    [viewer.length, viewer[0]?.props.images, I.openers.at(-1) === tapped],
    [1, [{ label: 'Media (the disc itself) · 02 - Sour Times.flac', sources: ['/deadwax/library/tracks/picture?album=Portishead%2FDummy%20(1994)&file=02%20-%20Sour%20Times.flac&index=1&v=5'] }], true])
  viewer[0].props.onClose()
  tree = view.draw(props('02 - Sour Times.flac'))
  check('...and its close shuts it, focus back to the picture tapped', [find((node) => node.type === 'art-viewer', tree).length, tapped.focused], [0, 1])

  const raw = one('app-inspect-raw', tree)
  check('"All tags in this file": its count, every raw tag under its own name, and the file\'s name',
    [words(one('app-inspect-summary', raw)), classed('app-inspect-label', raw).map(words), classed('app-inspect-value', raw).map(words), words(one('app-inspect-file', raw))],
    ['All tags in this file (2)', ['TITLE', 'GENRE'], ['Sour Times', 'Trip hop'], '02 - Sour Times.flac'])

  //? the lyrics, asked as the track shows, with a signal; and only the newest answer drawn
  check('its lyrics asked as it shows - its folder, its file, a signal', I.lyrics.map((ask) => [ask.path, ask.filename, !!ask.signal]), [['Portishead/Dummy (1994)', '02 - Sour Times.flac', true]])
  check('..."reading lyrics" while they are out', words(classed('app-inspect-group', tree).find((node) => words(one('app-inspect-heading', node)).startsWith('Lyrics'))), 'Lyricsreading lyrics')
  I.lyrics[0].resolve({ filename: '02 - Sour Times.flac', source: null, lyrics_file: null, synced: false, lines: [] })
  await settle()
  tree = view.draw(props('02 - Sour Times.flac'))
  const lyricsPart = () => classed('app-inspect-group', tree).find((node) => words(one('app-inspect-heading', node)).startsWith('Lyrics'))
  check('none on disk: the main page\'s words, and Get lyrics\'s tab', words(one('app-inspect-note', lyricsPart())), 'No lyrics for this track on disk. Get lyrics, in the Lyrics tab, looks for them on LRCLIB.')

  //? a step on: the last track's lyrics called off, and its answer landing late draws nothing
  tree = view.draw(props('01 - Mysterons.flac', { files: new Map(), loading: true, error: null }))
  check('(review) stepped: the same status line, first in it, now saying this track - spoken, focus staying on the button',
    [nowLine(tree)?.props?.role, nowLine(tree)?.props?.id === live.props.id, words(nowLine(tree))], ['status', true, 'Mysterons, 1 of 3'])
  check('stepped to the first track: Previous aria-disabled (still focusable) and refusing a click', [button('app-inspect-prev').props['aria-disabled'], (() => { const before = calls.step.length; button('app-inspect-prev').props.onClick(); return calls.step.length - before })()],
    ['true', 0])
  check('...its lyrics asked', I.lyrics.map((ask) => ask.filename), ['02 - Sour Times.flac', '01 - Mysterons.flac'])
  //? (review) what the docs promise while the file is read: a field only the file carries says '…', not the
  //? dash that reads as "this track has none" - and a field the scan has shows its value meanwhile
  const valueIn = (within, label) => {
    const lists = classed('app-inspect-fields', within).filter((node) => !node.props.class.includes('is-raw'))
    const labels = lists.flatMap((list) => classed('app-inspect-label', list))
    return lists.flatMap((list) => classed('app-inspect-value', list))[labels.findIndex((node) => words(node) === label)]
  }
  check('(review) ...a field only the file carries "…" while it is read (not "—"), one the scan has its value',
    [words(valueIn(tree, 'Genre')), words(valueIn(tree, 'Composer')), words(valueIn(tree, 'Artist')), words(valueIn(tree, 'Album'))], ['…', '…', 'Portishead', 'Dummy'])
  check('...the file being read: "reading the file" under the pictures, and the count waiting in the summary', [words(one('loading-blocks', classed('app-inspect-group', tree).find((node) => words(one('app-inspect-heading', node)) === 'Pictures in this file'))), words(one('app-inspect-summary', tree))],
    ['reading the file', 'All tags in this file'])
  tree = view.draw(props('02 - Sour Times.flac'))
  check('back to Sour Times: asked again, the first track\'s ask called off', [I.lyrics.map((ask) => ask.filename), I.lyrics[1].signal.aborted], [['02 - Sour Times.flac', '01 - Mysterons.flac', '02 - Sour Times.flac'], true])
  I.lyrics[2].resolve({ filename: '02 - Sour Times.flac', source: 'file', lyrics_file: '02 - Sour Times.lrc', synced: true,
    lines: [{ time: 12.4, text: 'Did you really want to' }, { time: 18.1, text: '' }, { time: 83.4, text: 'Lost in the coldest place' }] })
  await settle()
  tree = view.draw(props('02 - Sour Times.flac'))
  const lineWords = () => classed('app-inspect-line', tree).map((node) => [node.props.class, words(one('app-inspect-time', node)), words(one('app-inspect-words', node))])
  const sour = [['app-inspect-line', '0:12', 'Did you really want to'], ['app-inspect-line is-gap', '', ''], ['app-inspect-line', '1:23', 'Lost in the coldest place']]
  check('synced lines with their times; a blank line a gap with no time', lineWords(), sour)
  I.lyrics[1].resolve({ filename: '01 - Mysterons.flac', source: 'file', lyrics_file: '01 - Mysterons.lrc', synced: true, lines: [{ time: 12.4, text: 'Mysterons, late' }] })
  await settle()
  tree = view.draw(props('02 - Sour Times.flac'))
  check('...the first track\'s answer landing late, after this one\'s, draws nothing - this one\'s lines stay', lineWords(), sour)
  check('...marked synced, and where they came from', [words(one('app-inspect-mark', tree)), classed('app-inspect-note', lyricsPart()).map(words).at(-1)], ['synced', 'From 02 - Sour Times.lrc'])

  //? the third track: unnumbered, its name for a title, the last - and its lyrics embedded and plain
  tree = view.draw(props('track03.flac', { files: new Map(), loading: false, error: 'couldn\'t read the files' }))
  check('a file with no title tag says its title is its name; Next aria-disabled at the last; a read error said',
    [classed('app-inspect-note', tree).map(words).includes("No title tag - this is the file's name."), button('app-inspect-next').props['aria-disabled'], words(one('app-inspect-warn', tree))],
    [true, 'true', 'couldn\'t read the files'])
  const before = calls.step.length
  button('app-inspect-next').props.onClick()
  check('...Next refusing the click there', calls.step.length - before, 0)
  I.lyrics.at(-1).resolve({ filename: 'track03.flac', source: 'embedded', lyrics_file: null, synced: false, lines: [{ time: null, text: 'Words' }] })
  await settle()
  tree = view.draw(props('track03.flac', { files: new Map(), loading: false, error: null }))
  check('plain lyrics: no times, no synced mark, "Embedded in the file"', [classed('app-inspect-time', tree).length, classed('app-inspect-mark', tree).length, classed('app-inspect-note', lyricsPart()).map(words).at(-1)],
    [0, 0, 'Embedded in the file'])
  tree = view.draw(props('gone.flac'))
  check('a track no longer in the folder draws nothing (the panel shows the list)', tree, null)
  tree = view.draw(props('01 - Mysterons.flac'))
  I.lyrics.at(-1).reject(new Error('no such track'))
  await settle()
  tree = view.draw(props('01 - Mysterons.flac'))
  check('a lyrics read that failed is said', words(one('app-inspect-warn', lyricsPart())), 'no such track')
  delete globalThis.document
  delete globalThis.window
  hooks.__reset()
}

/** A window that keeps its listeners, so a test can move through the history - and count what listens. */
function historyWindow() {
  const listeners = []
  return {
    addEventListener: (type, listener, options) => listeners.push({ type, listener, capture: options === true || !!options?.capture }),
    removeEventListener: (type, listener, options) => {
      const capture = options === true || !!options?.capture
      const at = listeners.findIndex((each) => each.type === type && each.listener === listener && each.capture === capture)
      if (at >= 0) listeners.splice(at, 1)
    },
    dispatch: (type) => { for (const each of listeners.filter((one) => one.type === type)) each.listener({ type }) },
    count: (type) => listeners.filter((each) => each.type === type).length,
  }
}

/* ===== the cover viewer ===== */

function coverViewer() {
  console.log('\nthe cover viewer round the main page\'s ArtViewer')
  const classes = new Set()
  let active = null
  const focused = []
  const element = (name) => ({ name, focus: () => { active = element.all[name]; focused.push(name) } })
  element.all = {}
  for (const name of ['close', 'footer-close', 'opener', 'page']) element.all[name] = element(name)
  globalThis.document = {
    documentElement: { classList: { add: (name) => classes.add(name), remove: (name) => classes.delete(name) } },
    get activeElement() { return active },
  }
  const win = globalThis.window = historyWindow()
  const box = {
    querySelector: (selector) => (selector === '.window-close' ? element.all.close : null),
    querySelectorAll: () => [element.all.close, element.all['footer-close']],
    contains: (node) => node === element.all.close || node === element.all['footer-close'],
  }
  const fill = (tree) => { const div = find((node) => node.type === 'div' && node.props.class === 'app-viewer', tree)[0]; if (div) div.props.ref.current = box }
  const opener = { current: element.all.opener }
  let closed = 0
  const images = [{ label: 'Dummy', sources: ['/a'] }]
  const view = mount(CoverViewer)
  let tree = view.draw({ images: null, onClose: () => closed++, opener })
  check('shut: nothing drawn, no lock, focus left where it is', [tree, classes.has(VIEWER_LOCK), focused], [null, false, []])
  tree = view.draw({ images, onClose: () => closed++, opener }, fill)
  const art = find((node) => node.type === 'art-viewer', tree)[0]
  check('open: the main page\'s viewer with the images, in the app\'s wrapper; its own lock on <html>; focus to its Close',
    [art?.props.images, VIEWER_LOCK, classes.has(VIEWER_LOCK), focused], [images, 'app-viewer-open', true, ['close']])
  art.props.onClose()
  check('...its close is the caller\'s', closed, 1)
  const wrapper = find((node) => node.type === 'div' && node.props.class === 'app-viewer', tree)[0]
  const tab = (shiftKey) => { let prevented = false; wrapper.props.onKeyDown({ key: 'Tab', shiftKey, preventDefault: () => { prevented = true } }); return prevented }
  active = element.all['footer-close']
  check('Tab from its last button goes round to its first, never out to the page', [tab(false), active?.name], [true, 'close'])
  active = element.all.close
  check('...Shift-Tab from its first to its last', [tab(true), active?.name], [true, 'footer-close'])
  active = element.all.close
  check('...Tab between its own buttons left to the browser', tab(false), false)
  active = element.all.page
  check('...and focus somewhere outside brought back in', [tab(false), active?.name], [true, 'close'])
  tree = view.draw({ images: null, onClose: () => closed++, opener })
  check('shut again: the lock let go, focus back to what opened it', [tree, classes.has(VIEWER_LOCK), focused.at(-1)], [null, false, 'opener'])
  check('...and nothing left listening for a move through the history', [win.count('popstate'), win.count('hashchange')], [0, 0])

  //? (review) Back or Forward while it shows: an album page in a tab not shown stays mounted, hidden - a
  //? viewer left open there would hold its lock on the page shown and take its next Escape
  let movedClosed = 0
  tree = view.draw({ images, onClose: () => closed++, opener }, fill)
  check('open: it listens for a move through the history, once each', [win.count('popstate'), win.count('hashchange')], [1, 1])
  tree = view.draw({ images, onClose: () => movedClosed++, opener }, fill)
  win.dispatch('popstate')
  check('...Back or Forward (popstate) closes it - through the close it was given last', [movedClosed, closed], [1, 1])
  win.dispatch('hashchange')
  check('...and an address changed under it (hashchange) does too', movedClosed, 2)
  tree = view.draw({ images: null, onClose: () => movedClosed++, opener })
  check('...shut by that close: the lock let go, the listeners gone', [tree, classes.has(VIEWER_LOCK), win.count('popstate'), win.count('hashchange')], [null, false, 0, 0])
  win.dispatch('popstate')
  check('...a move once it is shut closes nothing', movedClosed, 2)

  tree = view.draw({ images, onClose: () => closed++, opener }, fill)
  hooks.__begin()
  hooks.__commit()
  check('drawn no more while open (the panel letting its editors go): the lock let go with it', classes.has(VIEWER_LOCK), false)
  check('...and its history listeners', [win.count('popstate'), win.count('hashchange')], [0, 0])
  delete globalThis.document
  delete globalThis.window
  hooks.__reset()
}

inspector().then(() => {
  coverViewer()
  console.log(`\n${checks} checks, ${failures ? `${failures} FAILED` : 'all passed'}`)
  process.exit(failures ? 1 : 0)
}, (error) => {
  console.error(error)
  process.exit(1)
})
