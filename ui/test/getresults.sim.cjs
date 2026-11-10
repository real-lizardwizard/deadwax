/**
 * An album's own Get cover, Get CD art and Get lyrics saying what they came to (2.0.8, UX batch 5): the words in
 * lib/getResults.ts, and the buttons in components/LibraryParts.tsx - compiled with the repo's TypeScript and rendered
 * by the small stand-in for Preact the other sims use; deadwax faked at api/library, each ask answered by hand.
 *
 * Until 2.0.8 a Get's result was only in its button's tooltip, which a phone never shows: on a phone the button just
 * became "Retry cover" or "No CD art found", with no reason, and a failed cover went only to the console.
 *
 * What it pins:
 *
 *  - THE WORDS: a refusal or a 404 in the route's own words made a sentence ("The Cover Art Archive has no front cover
 *    for that release."), anything else in lib/errorWords.ts's - a sentence for anyone, the error's own words in
 *    brackets for whoever runs deadwax, never for anyone else; a Get lyrics that answered as a sentence - its failures
 *    "try again", and no press invited for the tracks LRCLIB hasn't got;
 *  - THE BUTTONS: busy in words ("Getting the cover…", never a bare spinner); a failure said in a line UNDER the button
 *    - a live region, there on a phone - with the button "Try again" (none to find, cover or CD art: "Look again"); the reason
 *    never only in a tooltip (no title carries it); the line gone for another album; a success saying nothing over
 *    what it got (the cover, the disc picture, shows), and a lyrics run's outcome kept under its button.
 *
 * Run it with:  node ui/test/getresults.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
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

const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-getresults-'))
execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/components/LibraryParts.tsx', 'src/lib/getResults.ts',
  '--rootDir', 'src', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects (a component left as its node, never called), and hooks with a cursor
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x }] }
exports.useEffect = exports.useLayoutEffect = () => {}
exports.useMemo = (f) => f()
exports.useRef = (v) => slot(() => ({ current: v }))
exports.root = (component) => {
  const root = { slots: [], cursor: 0 }
  return (props) => {
    const outer = current; current = root; root.cursor = 0
    try { return component(props) } finally { current = outer }
  }
}
`)
//? deadwax's three routes, each ask kept and answered by hand
fs.writeFileSync(path.join(OUT, 'api/library.js'), `
const W = () => globalThis.__gets
const ask = (kind) => (path) => new Promise((resolve, reject) => W().push({ kind, path, resolve, reject }))
exports.fetchCoverArt = ask('cover')
exports.fetchLyrics = ask('lyrics')
exports.fetchDiscArt = ask('disc')
`)
const asks = globalThis.__gets = []

const G = require(path.join(OUT, 'lib/getResults.js'))
const { GetArtButton, GetDiscArtButton, GetLyricsButton } = require(path.join(OUT, 'components/LibraryParts.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))
const Access = require(path.join(OUT, 'app/access.js'))
const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))

const LISTENER = { auth: 'on', user: 'ann', admin: false, permissions: ['request', 'edit'] }
const api = (status, detail, where) => new ApiError(status, detail, `POST ${where} failed`, false, null, null, where)

function words(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  //? the busy label is a <Loading label=…/>: its words are its label
  if (typeof node.type === 'function' && typeof node.props?.label === 'string') return node.props.label
  return words(node.props?.children)
}

async function main() {
  console.log('\nthe words (lib/getResults.ts)')
  {
    const none = api(404, 'the Cover Art Archive has no front cover for that release', '/library/art/fetch')
    const away = api(502, "the Cover Art Archive couldn't be reached - try again", '/library/art/fetch')
    const broke = api(500, "Error fetching the cover art: [Errno 13] Permission denied: '/music/P/Dummy/cover.jpg'", '/library/art/fetch')
    const offline = new TypeError('Failed to fetch')
    check('a 404 and a refusal: the route\'s own words, made a sentence - for anyone',
      [G.getProblem(none, 'cover', false), G.getProblem(away, 'cover', false), G.getProblem(none, 'cover', true)],
      ['The Cover Art Archive has no front cover for that release.', "The Cover Art Archive couldn't be reached - try again. If it keeps happening, tell whoever runs deadwax.",
        'The Cover Art Archive has no front cover for that release.'])
    check('a failure of deadwax\'s own: the sentence and the tell for a listener - its words only for whoever runs deadwax',
      [G.getProblem(broke, 'cover', false), G.getProblem(broke, 'cover', true)],
      ["Couldn't get the cover. If it keeps happening, tell whoever runs deadwax.", "Couldn't get the cover. (Error fetching the cover art: [Errno 13] Permission denied: '/music/P/Dummy/cover.jpg')"])
    check('...deadwax not reached at all: said so, the button beside it doing the trying again',
      [G.getProblem(offline, 'lyrics', false), G.getProblem(offline, 'disc', true)],
      ["Can't connect to deadwax. Check your connection.", "Can't connect to deadwax. Check your connection. (Failed to fetch)"])
    check('...each Get its own lead', [G.GET_FAILED.cover, G.GET_FAILED.disc, G.GET_FAILED.lyrics], ["Couldn't get the cover.", "Couldn't get CD art.", "Couldn't get lyrics."])
    const summary = { written: 7, replaced: 0, kept: 1, missing: 1, instrumental: 0, untagged: 0, failed: 1, synced: 7 }
    check('a Get lyrics that answered: a sentence - the failures it says to try again, nothing inviting a press for what LRCLIB hasn\'t got',
      [G.lyricsResult(summary), G.lyricsResult({ ...summary, missing: 0, failed: 0, kept: 3 }), G.lyricsResult({ ...summary, written: 0, kept: 0, missing: 2, failed: 0, synced: 0 })],
      ['Saved lyrics for 7 tracks (all synced), 1 already had them, 1 not on LRCLIB, 1 failed - try again.',
        'Saved lyrics for 7 tracks (all synced), 3 already had them.', 'No new lyrics, 2 not on LRCLIB.'])
  }

  const album = (more = {}) => ({ path: 'P/Dummy (1994)', art: '', release_mbid: 'rel-dummy', disc_art: [], lyrics_count: 0, track_count: 10, ...more })
  const draw = (Button, props) => {
    const render = hooks.root(Button)
    let tree = null
    const done = []
    const all = { onDone: () => done.push(true), class: 'app-edit-button', ...props }
    const view = (more = {}) => { Object.assign(all, more); tree = render(all); return tree }
    const button = () => (tree?.props.children ?? []).find((node) => node?.type === 'button')
    const line = () => (tree?.props.children ?? []).find((node) => node && typeof node.type === 'function')?.props ?? null
    return { view, button, line, done }
  }
  const press = (one) => one.button().props.onClick({ stopPropagation() {} })

  console.log('\nGet cover: what came of it, under the button')
  {
    const one = draw(GetArtButton, { album: album() })
    one.view()
    check('idle: Get cover, its title what it does - no line under it', [words(one.button()), one.button().props.title, one.line()?.text],
      ['Get cover', 'Download a cover for this album and change nothing else.', null])
    press(one)
    one.view()
    check('working: said in words, never a bare spinner; disabled while in flight', [words(one.button()), one.button().props.disabled], ['Getting the cover…', true])
    asks.shift().reject(api(404, 'the Cover Art Archive has no front cover for that release', '/library/art/fetch'))
    await settle()
    one.view()
    check('none to find: said under the button, a live region - and the button Look again, as CD art\'s', [one.line(), words(one.button()), one.button().props.disabled],
      [{ text: 'The Cover Art Archive has no front cover for that release.', class: 'app-edit-note' }, 'Look again', false])
    check('...the reason never only in a tooltip', one.button().props.title.includes('front cover'), false)
    press(one)
    asks.shift().reject(api(502, "the Cover Art Archive couldn't be reached - try again", '/library/art/fetch'))
    await settle()
    one.view()
    check('...not reached: said so - the button Try again, marked failed', [one.line()?.text, words(one.button()), one.button().props.class.includes('failed')],
      ["The Cover Art Archive couldn't be reached - try again.", 'Try again', true])
    one.view({ album: album({ path: 'P/Portishead (1997)' }) })
    check('another album: none of that said for it', [one.line()?.text, words(one.button())], [null, 'Get cover'])
    one.view({ album: album() })
    press(one)
    asks.shift().resolve({ written: 'cover.jpg', replaced: null })
    await settle()
    one.view()
    check('got it: told (the cover shows), nothing said under the button', [one.done.length, one.line()?.text], [1, null])
  }

  console.log('\nGet CD art: none found and a failure told apart, in words')
  {
    const one = draw(GetDiscArtButton, { album: album() })
    one.view()
    press(one)
    one.view()
    check('working: in words', words(one.button()), 'Getting CD art…')
    asks.shift().reject(api(404, 'no CD art on the Cover Art Archive for this release - a fanart.tv key in Server settings adds another source', '/library/disc_art/fetch'))
    await settle()
    one.view()
    check('none to find: the route\'s words, a sentence - the button Look again', [one.line()?.text, words(one.button())],
      ['No CD art on the Cover Art Archive for this release - a fanart.tv key in Server settings adds another source.', 'Look again'])
    press(one)
    asks.shift().reject(api(502, "the Cover Art Archive couldn't be reached - try again", '/library/disc_art/fetch'))
    await settle()
    one.view()
    check('...not reached: said so - the button Try again', [one.line()?.text, words(one.button())], ["The Cover Art Archive couldn't be reached - try again.", 'Try again'])
  }

  console.log('\nGet lyrics: the outcome kept under the button')
  {
    const one = draw(GetLyricsButton, { album: album() })
    one.view()
    press(one)
    one.view()
    check('working: in words', words(one.button()), 'Getting lyrics…')
    asks.shift().resolve({ written: 9, replaced: 0, kept: 0, missing: 1, instrumental: 0, untagged: 0, failed: 0, synced: 9 })
    await settle()
    one.view()
    check('answered: how many on the button, the whole outcome under it', [words(one.button()), one.line()?.text],
      ['Lyrics · 9 of 10', 'Saved lyrics for 9 tracks (all synced), 1 not on LRCLIB.'])
    //? said as it fails, for whoever is reading then
    Access.noteAccess(LISTENER)
    press(one)
    asks.shift().reject(api(500, 'Error fetching lyrics: ReadTimeout', '/library/lyrics/fetch'))
    await settle()
    one.view()
    check('...a failure, for someone given Edit albums alone: the sentence and the tell, never the error\'s own words',
      [one.line()?.text, words(one.button())], ["Couldn't get lyrics. If it keeps happening, tell whoever runs deadwax.", 'Try again'])
    Access.forgetAccess()
  }

  console.log('\nthe source: no Get keeps its reason in a tooltip, nor sends it only to the console')
  {
    const source = fs.readFileSync(path.join(UI, 'src/components/LibraryParts.tsx'), 'utf8')
    check('every button draws its line, and none logs its failure instead', [(source.match(/<ResultLine /g) ?? []).length, /console\.error/.test(source)], [3, false])
    //? (2.0.8) and the editors draw the writers' problems as sentences, however the server wrote them ("this release has 2
    //? tracks but the folder has 1 - check it's the right edition" a capital and a full stop)
    const editor = fs.readFileSync(path.join(UI, 'src/components/MetadataEditor.tsx'), 'utf8')
    const tags = fs.readFileSync(path.join(UI, 'src/components/TrackTagEditor.tsx'), 'utf8')
    check('the editors say the writers\' problems as sentences - the preview\'s, and what an Apply reported',
      [(editor.match(/>\{asSentence\(problem\)\}<\/h5>/g) ?? []).length, /metadata-problem" key=\{problem\}>\{sentence\(problem\)\}<\/p>/.test(tags), /\.\.\.results\.problems\.map\(sentence\)/.test(tags),
       /const sentence = useMemo\(\(\) => asSentenceKeeping\(filenames\)/.test(tags)],
      [2, true, true, true])
    //? (2.0.8 review) the Now: line's words in its own face - the mono metadata-mbid was the raw id's (it set "Matched to
    //? MusicBrainz" in mono, onto a line of its own on a phone) - and its year from nowYear, never "(this pressing )"
    check('the Release tab\'s Now: line: no mono class for words, the year from nowYear',
      [/metadata-mbid/.test(editor), /\{nowYear\(album\)\}/.test(editor), /this pressing \$\{album\.year\}/.test(editor)],
      [false, true, false])
  }

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
}

main().catch((error) => {
  console.error(error)
  process.exit(1)
})
