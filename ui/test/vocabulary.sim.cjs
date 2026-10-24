/**
 * One vocabulary for your library, Home and the Library (2.0.5, UX batch 2) - a scan of the words a listener reads -
 * and for Search, the album you don't have, Sources and Requests (2.0.6, UX batch 3).
 *
 * James (2026-10-23) decided the shared music on the server is "All music" as a heading and "the collection" in a
 * sentence - never "the store", "Browse", "Navidrome" or "everything" - and that a person's own library is said as
 * what they see ("Added to your library", "waiting to be added"), never in starring mechanics. This script reads the
 * source of every file the batch owns, keeps only what a listener can read - string literals that are words (not class
 * names, ids, routes or scopes) and JSX text, comments taken out - and checks:
 *
 *  - in the batch's own files (BATCH): no "store", no "Browse", no "Navidrome", no "star"/"starred"/"starring",
 *    no "Subsonic", no "Put away", no "Request it again", no "the admin", no "First seen", no "Other pressings", no "everything";
 *  - in EVERY file of the app (app/, lib/, player/, hooks/, components/): no "the store" or "in the store" - the
 *    rename was the whole app's, and a new line saying it would undo it;
 *  - (2.0.6) in batch 3's files (BATCH3): James's "source" for where a download comes from - never "peer", "folder",
 *    "Soulseek" or "slskd"; "added to your library", never "filed" or "organizing"; "pressing", never "editions" or
 *    "release id"; albums you don't have, never "MusicBrainz" (but its own ↗ links); no "saved" mark; "Searching…" and
 *    "Loading…", never "Asking…"; "Getting…", never "Get…"; and none of the old Sources and Requests words - Signals,
 *    Titles, Lengths, Free slot, their own average, Re-search, "#3 in", Next peer, Ask again, "3 ahead", and Navidrome's
 *    name ("try 2" is a template's "try " the scanner can't tell from code - requests.sim pins "2nd try"). A line left on
 *    purpose is in ALLOW3, with why.
 *  - (2.0.7) in batch 4's files (BATCH4): Info's About, Now Playing, the mini player, the turntable and the visualizer
 *    say none of Debug's or the engine's words to a listener - no LUFS, "levelled", numpy or soundfile, STREAMINFO or
 *    MiB, "in one stream", "deadwax hasn't said", Navidrome; no "can't be seen" or WebGL; "Up Next", never "Up next"; no
 *    "Open now playing"; no "couldn't be decoded". Debug's own words live in lib/debugRows.ts and lib/loudness.ts, an
 *    admin's, which are not in BATCH4. And (after review) the readout's old labels "now:" and "feel:" and a lowercase
 *    "bpm" in ANY of those files' text (BATCH4_LABELS: short labels and template tails the words-only scan drops as
 *    code), and the playback error words pinned in usePlayer.ts and as troubleshooting.md quotes them.
 *
 * Each rule is checked on a sample that breaks it, so a scan that finds nothing is known to look.
 *
 * Run it with:  node ui/test/vocabulary.sim.cjs
 */

const fs = require('fs'), path = require('path')

const SRC = path.resolve(__dirname, '..', 'src')

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` + (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

/**
 * The source read once, as a tokenizer would: its comments blanked (`code`), and every string literal's own text
 * (`strings`: [offset, text]) - a template's literal parts, with a space where each `${...}` was, and the strings
 * inside those expressions read too (a template nested in a template's expression - `${a ? `x` : 'y'}` - is
 * followed, never taken for the outer one's end).
 */
function tokens(src) {
  let code = '', i = 0
  const strings = []
  //? what we are inside: 'code' (with the brace depth an expression of a template started at), or a template
  const stack = [{ kind: 'code', depth: 0 }]
  let depth = 0
  const top = () => stack[stack.length - 1]
  while (i < src.length) {
    const c = src[i]
    if (top().kind === 'template') {
      const part = top()
      if (c === '\\') { part.text += src.slice(i, i + 2); code += src.slice(i, i + 2); i += 2; continue }
      if (c === '`') { stack.pop(); strings.push([part.at, part.text]); code += c; i++; continue }
      if (src.startsWith('${', i)) { part.text += ' '; stack.push({ kind: 'code', depth }); depth++; code += '${'; i += 2; continue }
      part.text += c; code += c; i++; continue
    }
    if (src.startsWith('//', i)) { const j = src.indexOf('\n', i); const end = j < 0 ? src.length : j; code += ' '.repeat(end - i); i = end; continue }
    if (src.startsWith('/*', i)) { const j = src.indexOf('*/', i + 2); const end = j < 0 ? src.length : j + 2; code += src.slice(i, end).replace(/[^\n]/g, ' '); i = end; continue }
    if (c === '"' || c === "'") {
      let j = i + 1, text = ''
      while (j < src.length && src[j] !== c && src[j] !== '\n') { if (src[j] === '\\') { text += src.slice(j, j + 2); j += 2 } else text += src[j++] }
      strings.push([i, text]); code += src.slice(i, j + 1); i = j + 1; continue
    }
    if (c === '`') { stack.push({ kind: 'template', at: i, text: '' }); code += c; i++; continue }
    //? a regex literal (a "/" where a value starts - after an operator, a bracket, a comma or `return`): skipped
    //? whole, so a quote or backtick in it - /[’‘`´]/ - never opens a string
    if (c === '/' && /(?:^|[(,=:[!&|?{};+\-*%<>~^]|\breturn)\s*$/.test(code.slice(-40))) {
      let j = i + 1, inClass = false
      while (j < src.length && src[j] !== '\n') {
        if (src[j] === '\\') { j += 2; continue }
        if (src[j] === '[') inClass = true
        else if (src[j] === ']') inClass = false
        else if (src[j] === '/' && !inClass) break
        j++
      }
      code += src.slice(i, j + 1); i = j + 1; continue
    }
    if (c === '{') depth++
    if (c === '}') {
      depth--
      if (stack.length > 1 && top().kind === 'code' && depth === top().depth) { stack.pop(); code += c; i++; continue }
    }
    code += c; i++
  }
  return { code, strings }
}

/** Whether a string is words a person reads - not a class list, an id, a route, a scope or an import. */
function wordy(text) {
  const s = text.trim()
  if (s.length < 3 || !/[A-Za-z]{2,}/.test(s)) return false
  if (/^(\.{1,2}\/|\/|#|@|http)/.test(s) && !s.includes(' ')) return false
  if (/^[\w\-.:/]+$/.test(s) && !/^[A-Z]/.test(s)) return false
  if (/^[a-z0-9\- ]+$/.test(s) && s.includes('-')) return false
  if (/^(app|pl)-[\w-]+/.test(s) && !/[A-Z]/.test(s)) return false
  return true
}

/**
 * Every piece of text in a file a listener could read: [line, words]. With `all`, every piece of text whether or not it
 * looks like words - a short label ("feel:" before an expression) or a template's tail (" bpm" after `${...}`) that
 * wordy() takes for code - for the batch 4 rules that look for exactly those (BATCH4_LABELS).
 */
function readable(src, all = false) {
  const { code, strings } = tokens(src)
  const lineOf = (at) => code.slice(0, at).split('\n').length
  const found = []
  for (const [at, text] of strings) {
    const before = code.slice(Math.max(0, at - 14), at)
    if (/\b(?:import|from)\s*$/.test(before) || /\bclass(?:Name)?=\{?`?$/.test(before)) continue
    if (all ? text.trim() : wordy(text)) found.push([lineOf(at), text])
  }
  //? JSX text: between a tag's end (or an expression's) and the next tag or expression
  const jsx = /(?<=[>}])([^<>{}]*[A-Za-z][^<>{}]*)(?=[<{])/g
  for (let m; (m = jsx.exec(code));) {
    const text = m[1].replace(/\s+/g, ' ').trim()
    //? code that happens to sit between a ">" and a "<" (a comparison, an arrow) is not text; words in brackets are
    if (!(all ? text : wordy(text)) || /=>|&&|\|\||[=!]==|[;=[\]]|\?\s|\(\)/.test(text)) continue
    if (/^(else|return|catch|as |while|from|function|const|let|if |case |default)/.test(text)) continue
    //? (2.0.6) code that sits between a ">" and a "{" too: a type annotation, a loop's head, a spread
    if (/\bvoid\b|\(const |\.\.\.\(|^\||^[\w.]+\.\w+\($/.test(text)) continue
    found.push([lineOf(m.index + 1), text])
  }
  return found
}

const BATCH = [
  'app/Home.tsx', 'app/LibraryHome.tsx', 'app/LibrarySection.tsx', 'app/LibraryViews.tsx', 'app/Pinned.tsx', 'app/PinToggle.tsx',
  'app/YourLibrary.tsx', 'app/AlbumProperties.tsx', 'app/ArtistPage.tsx', 'app/PressingPicker.tsx', 'app/Sidebar.tsx',
  'lib/pins.ts', 'lib/artistPage.ts', 'lib/whose.ts', 'lib/myLibrary.ts', 'lib/yourLibrary.ts', 'lib/appFrame.ts',
  'lib/albumProperties.ts', 'lib/idBridge.ts', 'lib/upNext.ts', 'player/AlbumPage.tsx', 'player/PlayerBar.tsx',
  //? (2.0.5 review) Library care's Held by nobody: its Put away became Dismiss in this batch too
  'app/HeldByNobody.tsx',
]

/** The words the batch's files never say to a listener - each with a sample that says it. */
const BATCH_RULES = [
  ['"store"', /\bstore\b/i, 'Removed from the store'],
  ['"Browse" as a label', /\bBrowse\b/, 'Browse the store'],
  ['"Navidrome"', /Navidrome/, 'Not in Navidrome yet'],
  ['starring', /\bstar(?:s|red|ring)?\b/i, 'Waiting for its turn to be starred.'],
  ['"Subsonic"', /Subsonic/, 'star it in a Subsonic app'],
  ['"Put away"', /\bput(?:ting)? away\b/i, 'Put away'],
  ['"Request it again"', /request it again/i, 'Request it again'],
  ['"the admin"', /\bthe admin\b/i, 'Removed by the admin'],
  ['"First seen"', /First seen/, 'First seen'],
  ['"Other pressings"', /Other pressings/, 'Other pressings'],
  ['"everything" for the collection', /\beverything\b/i, 'Then everything again, in a new order.'],
]

/** ...and the whole app never says "the store" (2.0.5: "the collection"). */
const APP_RULE = ['"the store"', /\b(?:the|in the|from the) store\b/i, 'Searching the store…']

/** (2.0.6, UX batch 3) Search, the album you don't have, Sources and Requests - and the artist page's MusicBrainz words
 *  and "2 editions", which batch 2 left to this one. */
const BATCH3 = [
  'app/Search.tsx', 'app/SearchRows.tsx', 'lib/searchList.ts', 'lib/searchResults.ts', 'lib/songs.ts',
  'app/ReleaseGroupPage.tsx', 'lib/pressings.ts', 'app/PressingPicker.tsx', 'lib/owned.ts',
  'app/Sources.tsx', 'app/SourceCard.tsx', 'lib/candidates.ts', 'lib/getSettings.ts', 'app/StoreState.tsx', 'hooks/useCandidateSearch.ts',
  'app/Requests.tsx', 'app/JobCard.tsx', 'lib/requestsView.ts', 'lib/perPerson.ts', 'hooks/useDownloadJobs.ts', 'app/Arriving.tsx', 'lib/myLibrary.ts',
  'lib/artistPage.ts', 'app/ArtistPage.tsx',
]

/** The words batch 3's files never say to a listener - each with a sample that says it. */
const BATCH3_RULES = [
  ['"MusicBrainz"', /MusicBrainz/, 'Asking MusicBrainz…'],
  ['"Soulseek"', /Soulseek/, '41 folders on Soulseek, none pass your filters'],
  ['"slskd"', /slskd/, 'slskd listens for answers for a few seconds.'],
  ['"peer"', /\bpeers?\b/i, 'Trying next peer…'],
  ['"folder" for a source', /\bfolders?\b/i, '2 disc folders'],
  ['"filed" / "filing"', /\bfil(?:ed|ing)\b/i, 'Partly filed: 2 file(s) failed to organize'],
  ['"organizing"', /organi[sz]/i, '12 of 12 files · organizing'],
  ['"release id"', /release id/i, 'its folder has no MusicBrainz release id'],
  ['"editions"', /\beditions\b/i, '1994 · in your library · 2 editions'],
  ['the "saved" mark', /\bsaved\b/i, 'Saved - MusicBrainz is away.'],
  ['"Asking…"', /\bAsking\b/, 'Asking the collection…'],
  ['the code\'s signal names', /\b(?:Signals|Titles|Lengths)\b/, 'Signals · 2'],
  ['"Free slot"', /\bFree slot\b/, 'Free slot'],
  ['"their own average"', /own average/, 'their own average'],
  ['"Re-search"', /Re-search/, 'Re-search'],
  ['"#3 in"', /#\s*in\b/, '#3 in their queue'.replace('3', ' ')],
  ['"Next peer" / "Ask again"', /Next peer|\bAsk(?:ing)? again\b/, 'Next peer · 3 left'],
  ['"Get…"', /\bGet…/, 'Get…'],
  ['"ahead"', /\bahead\b/, '3 ahead'],
  ['"Navidrome"', /Navidrome/, "Navidrome hasn't found it yet - it may still be scanning"],
]

/** Lines batch 3's rules leave on purpose: [file, the line's words, why]. */
const ALLOW3 = [
  ['app/ReleaseGroupPage.tsx', /^On MusicBrainz$/, 'the label over its own links to musicbrainz.org - the one place the name stays (the review\'s X2)'],
  ['lib/owned.ts', /^A folder with this name, not matched to a pressing/, "the maybe's tooltip, drawn only for whoever can Edit albums - its folders' paths; anyone reads the line under Get"],
  ['lib/candidates.ts', /^(?:those folders|that folder|Getting it adds only the tracks that folder doesn't have yet\.)$/, "a library folder, named by its path beside it (the store box's notes) - not a source"],
  ['app/Requests.tsx', /Downloads still arrive in slskd/, 'the database line for whoever runs deadwax only (it names DB_PATH); anyone else reads UNTRACKED_TEXT'],
  ['app/ArtistPage.tsx', /^Folders?$/, "the artist's facts' folder paths - the review's AR7, flagged beyond the batches (B6)"],
  ['lib/myLibrary.ts', /^its folder$/, "Held by nobody's flag line, a managing page's (batch 5)"],
]

/** (2.0.7, UX batch 4) Info's About, Now Playing, the mini player, the turntable and the visualizer - and the engine's
 *  playback error words (usePlayer.ts: its strings only, the one engine file this batch may change). */
const BATCH4 = [
  'lib/aboutRows.ts', 'lib/aboutSound.ts', 'app/InfoSheet.tsx', 'lib/idBridge.ts', 'player/MiniPlayer.tsx', 'player/NowPlaying.tsx', 'lib/upNext.ts',
  'app/UpNext.tsx', 'player/PlayerBar.tsx', 'lib/turntable.ts', 'player/Turntable.tsx', 'lib/vizSync.ts', 'player/Visualizer.tsx', 'lib/visualizer.ts',
  'lib/musicFeel.ts', 'player/usePlayer.ts',
]

/** The words batch 4's files never say to a listener - each with a sample that says it. */
const BATCH4_RULES = [
  ['"LUFS"', /\bLUFS\b/, 'Album, -3.56 dB · the album at -14.4 LUFS'],
  ['"levelled"', /\blevell?ed\b/i, 'Not levelled - MP3 songs play as they are'],
  ['numpy and soundfile', /numpy|soundfile/, 'deadwax is running without numpy and soundfile'],
  ['STREAMINFO and MiB', /STREAMINFO|\bMiB\b/, "its STREAMINFO doesn't say how long it is"],
  ['"in one stream"', /in one stream/i, 'On, in one stream'],
  ['"hasn\'t said"', /hasn't said/, "Asked for; deadwax hasn't said yet"],
  ['"Navidrome"', /Navidrome/, "Couldn't play this song - Navidrome didn't send audio this device can play"],
  ['"can\'t be seen"', /can't be seen/, "This song can't be seen - it isn't a FLAC file."],
  ['"WebGL"', /WebGL/, "WebGL isn't available here, so Ambient is showing the simple version."],
  ['"Up next"', /\bUp next\b/, 'Up next - Shuffle on'],
  ['"Open now playing"', /Open now playing/i, 'Open now playing'],
  ['"couldn\'t be decoded"', /couldn't be decoded/, "This song's file couldn't be decoded"],
]

/**
 * (after review) The readout's old labels, looked for in EVERY piece of text (readable's `all`): JSX text before an
 * expression is read alone - "now:" of <span>now: {STYLE_NAMES[...]}</span> - and a template's " bpm" after `${...}`,
 * both of which wordy() drops as code, so a rule over readable()'s words could never see them. Each sample is shaped
 * like the code that said it, and shown missed by the words-only scan, so the rule is known to need `all`.
 */
const BATCH4_LABELS = [
  ['the feel readout\'s "now:" label', /^now:$/, 'const v = <span>now: {STYLE_NAMES[nowStyle]}</span>'],
  ['the feel readout\'s "feel:" label', /^feel:$/, 'const v = <span>feel: {feelText}</span>'],
  ['a lowercase "bpm"', /\bbpm\b/, 'const t = `${Math.round(F.bpm)} bpm`'],
]

/**
 * (after review) The playback error words a listener reads (usePlayer.ts's describeMediaError and skipNotice, the one
 * engine file this batch changes - its strings only), pinned here rather than in player.sim (an engine file), as the
 * source says them and as docs/troubleshooting.md quotes them, so a rewording that misses the docs fails.
 */
const PLAYBACK_WORDS = [
  ["This device couldn't play this song's audio", "This device couldn't play this song's audio"],
  ["Couldn't play this song - it didn't come as audio this device can play", "Couldn't play this song - it didn't come as audio this device can play"],
  ['Skipped "${title}" - this device couldn\'t play its audio', 'Skipped "…" - this device couldn\'t play its audio'],
]

function filesUnder(dir) {
  return fs.readdirSync(path.join(SRC, dir)).filter((name) => /\.tsx?$/.test(name)).map((name) => `${dir}/${name}`)
}

console.log('\nthe scanner sees what a listener reads, and only that')
{
  const sample = `
    import { x } from './store'
    // the store, in a comment
    /* Navidrome in a block comment */
    const a = 'app-store-line is-store'
    const b = "Removed from the store"
    const c = \`\${n} albums in the store\`
    const d = <p class="pl-notice">Browse the store</p>
    const h = <p>Your favourite (starred) albums.</p>
    const e = scope === 'store'
    const f = name.replace(/[’‘\`´]/g, "'")
    const g = 'Then the end'
  `
  const words = readable(sample).map(([, text]) => text.trim())
  check("a string, a template and JSX text are read; comments, imports, classes, scopes and a regex's quotes are not",
    words, ['Removed from the store', 'albums in the store', 'Then the end', 'Browse the store', 'Your favourite (starred) albums.'])
  for (const [name, rule, said] of [...BATCH_RULES, APP_RULE, ...BATCH3_RULES, ...BATCH4_RULES]) {
    check(`the ${name} rule catches "${said}"`, readable(`const x = ${JSON.stringify(said)}`).some(([, text]) => rule.test(text)), true)
  }
  for (const [name, rule, said] of BATCH4_LABELS) {
    check(`the ${name} rule catches ${said} - in every piece of text, which the words alone miss`,
      [readable(said, true).some(([, text]) => rule.test(text.trim())), readable(said).some(([, text]) => rule.test(text.trim()))], [true, false])
  }
}

console.log('\nthe batch\'s files: your library, Home, the Library, the album and artist pages, pins, You > Your library')
for (const file of BATCH) {
  const found = readable(fs.readFileSync(path.join(SRC, file), 'utf8'))
  const broken = []
  for (const [line, text] of found) for (const [name, rule] of BATCH_RULES) if (rule.test(text)) broken.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
  check(`${file}: none of the old words a listener reads (${found.length} lines read)`, broken, [])
}

console.log('\nbatch 3\'s files (2.0.6): Search, the album you don\'t have, Sources, Requests - source, added, pressing, and no plumbing')
{
  const allowed = new Set()
  for (const file of BATCH3) {
    const found = readable(fs.readFileSync(path.join(SRC, file), 'utf8'))
    const broken = []
    for (const [line, text] of found) {
      for (const [name, rule] of BATCH3_RULES) {
        if (!rule.test(text)) continue
        const allow = ALLOW3.find(([where, words]) => where === file && words.test(text.trim()))
        if (allow) allowed.add(allow)
        else broken.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
      }
    }
    check(`${file}: none of batch 3's old words a listener reads (${found.length} lines read)`, broken, [])
  }
  //? an allowance nothing needs any more is a hole a new line could slip through: each must still be used
  check('every line left on purpose is still there - none of ALLOW3 stale', ALLOW3.filter((allow) => !allowed.has(allow)).map(([file, words]) => `${file} ${words}`), [])
}

console.log('\nbatch 4\'s files (2.0.7): Info\'s About, Now Playing, the turntable and the visualizer - a listener\'s words, Debug\'s numbers left to Debug')
for (const file of BATCH4) {
  const found = readable(fs.readFileSync(path.join(SRC, file), 'utf8'))
  const broken = []
  for (const [line, text] of found) for (const [name, rule] of BATCH4_RULES) if (rule.test(text)) broken.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
  check(`${file}: none of batch 4's old words a listener reads (${found.length} lines read)`, broken, [])
  const labels = []
  for (const [line, text] of readable(fs.readFileSync(path.join(SRC, file), 'utf8'), true)) {
    for (const [name, rule] of BATCH4_LABELS) if (rule.test(text.trim())) labels.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
  }
  check(`${file}: none of the readout's old labels in any of its text`, labels, [])
}
{
  const player = fs.readFileSync(path.join(SRC, 'player/usePlayer.ts'), 'utf8')
  const guide = fs.readFileSync(path.join(SRC, '..', '..', 'docs/troubleshooting.md'), 'utf8').replace(/\s+/g, ' ')
  check('the playback error words: each in usePlayer.ts as a listener reads it, and quoted so in troubleshooting.md',
    PLAYBACK_WORDS.map(([source, quoted]) => [player.includes(source), guide.includes(quoted)]), PLAYBACK_WORDS.map(() => [true, true]))
}

console.log('\nthe whole app: "the collection", never "the store"')
{
  const files = ['app', 'lib', 'player', 'hooks', 'components'].flatMap(filesUnder)
  const broken = []
  for (const file of files) {
    for (const [line, text] of readable(fs.readFileSync(path.join(SRC, file), 'utf8'))) if (APP_RULE[1].test(text)) broken.push(`${file}:${line} ${text.trim().slice(0, 120)}`)
  }
  check(`no file of ${files.length} says "the store" to anyone`, broken, [])
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
