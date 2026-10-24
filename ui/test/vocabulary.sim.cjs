/**
 * One vocabulary for your library, Home and the Library (2.0.5, UX batch 2) - a scan of the words a listener reads.
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
 *    rename was the whole app's, and a new line saying it would undo it.
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

/** Every piece of text in a file a listener could read: [line, words]. */
function readable(src) {
  const { code, strings } = tokens(src)
  const lineOf = (at) => code.slice(0, at).split('\n').length
  const found = []
  for (const [at, text] of strings) {
    const before = code.slice(Math.max(0, at - 14), at)
    if (/\b(?:import|from)\s*$/.test(before) || /\bclass(?:Name)?=\{?`?$/.test(before)) continue
    if (wordy(text)) found.push([lineOf(at), text])
  }
  //? JSX text: between a tag's end (or an expression's) and the next tag or expression
  const jsx = /(?<=[>}])([^<>{}]*[A-Za-z][^<>{}]*)(?=[<{])/g
  for (let m; (m = jsx.exec(code));) {
    const text = m[1].replace(/\s+/g, ' ').trim()
    //? code that happens to sit between a ">" and a "<" (a comparison, an arrow) is not text; words in brackets are
    if (!wordy(text) || /=>|&&|\|\||[=!]==|[;=[\]]|\?\s|\(\)/.test(text)) continue
    if (/^(else|return|catch|as |while|from|function|const|let|if |case |default)/.test(text)) continue
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
  for (const [name, rule, said] of [...BATCH_RULES, APP_RULE]) {
    check(`the ${name} rule catches "${said}"`, readable(`const x = ${JSON.stringify(said)}`).some(([, text]) => rule.test(text)), true)
  }
}

console.log('\nthe batch\'s files: your library, Home, the Library, the album and artist pages, pins, You > Your library')
for (const file of BATCH) {
  const found = readable(fs.readFileSync(path.join(SRC, file), 'utf8'))
  const broken = []
  for (const [line, text] of found) for (const [name, rule] of BATCH_RULES) if (rule.test(text)) broken.push(`${file}:${line} ${name}: ${text.trim().slice(0, 120)}`)
  check(`${file}: none of the old words a listener reads (${found.length} lines read)`, broken, [])
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
