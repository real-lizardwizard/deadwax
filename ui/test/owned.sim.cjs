/**
 * Which search results are already in the library - BOTH copies of the rules, held to one answer.
 *
 * interface/scripts/owned.mjs marks the main page's search; ui/src/lib/owned.ts (2.0.0-player.13)
 * leaves held albums out of the app's "Not in your library yet". The image's UI stage copies only
 * ui/, so the app can't import the .mjs, and the two live side by side until the main page
 * retires. Every case is in tests/fixtures/pressings/owned.json and is run against each copy, so
 * an edit to one that the other doesn't share fails here, by name.
 *
 * The cases that matter are the ones a wrong answer would hide: a pressing claimed by the wrong id,
 * an untagged folder claimed over a tagged one, a folder named the way the sleeve credited the
 * artist.
 *
 * Run it with:  node ui/test/owned.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')
const { pathToFileURL } = require('url')

const UI = path.resolve(__dirname, '..')
const FIXTURE = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../tests/fixtures/pressings/owned.json'), 'utf8'))
const MJS = pathToFileURL(path.resolve(__dirname, '../../interface/scripts/owned.mjs')).href
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-owned-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/owned.ts', '--outDir', OUT, '--module', 'commonjs', '--target', 'es2022',
  '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' })

let failures = 0
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}

const paths = (albums) => albums.map((album) => album.path).sort()

/** One case of the fixture, through one copy - albums in an answer written as their paths. */
function run(O, index, { fn, args }) {
  const byPath = (entry) => (typeof entry === 'string' ? FIXTURE.albums.find((album) => album.path === entry) : entry)
  switch (fn) {
    case 'foldName': return O.foldName(...args)
    case 'ownedForRelease': return paths(O.ownedForRelease(index, ...args))
    case 'ownedForGroup': {
      const { held, guessed } = O.ownedForGroup(index, ...args)
      return { held: paths(held), guessed: paths(guessed) }
    }
    case 'describeGroupOwnership': {
      const chip = O.describeGroupOwnership(O.ownedForGroup(index, ...args))
      return chip && { kind: chip.kind, label: chip.label }
    }
    case 'describeFolders': return O.describeFolders(args[0].map(byPath))
    case 'total': return index.total
    default: throw new Error(`no such case: ${fn}`)
  }
}

;(async () => {
  const copies = [['owned.mjs', await import(MJS)], ['owned.ts', require(path.join(OUT, 'owned.js'))]]

  for (const [name, O] of copies) {
    console.log(`\n${name}`)
    const index = O.buildOwnedIndex(FIXTURE.albums)
    for (const item of FIXTURE.cases) check(item.label, run(O, index, item), item.expected)
    check('no index answers nothing', O.ownedForGroup(null, { groupId: 'dummy' }), { held: [], guessed: [] })
    check('...and holds no pressing', O.ownedForRelease(null, 'x'), [])
  }

  console.log('\nthe two copies')
  const exported = (O) => Object.keys(O).filter((key) => typeof O[key] === 'function').sort()
  check('export the same functions', exported(copies[1][1]), exported(copies[0][1]))
  //? one more pass over names nobody wrote a case for: every album's own name, both ways
  const names = FIXTURE.albums.flatMap((album) => [album.artist, album.album, album.path])
  check('fold every name in the fixture alike', names.map(copies[1][1].foldName), names.map(copies[0][1].foldName))
  const tooltip = (O) => O.describeGroupOwnership(O.ownedForGroup(O.buildOwnedIndex(FIXTURE.albums), FIXTURE.cases[6].args[0])).title
  check('word a tooltip alike', tooltip(copies[1][1]), tooltip(copies[0][1]))

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})()
