/**
 * Which search results are already in the library: ui/src/lib/owned.ts, which leaves held albums out
 * of the app's "Not in your library yet" (2.0.0-player.13), against every case in
 * tests/fixtures/pressings/owned.json.
 *
 * Until 2.0.0-player.66 the main page's interface/scripts/owned.mjs was run against the same cases,
 * the two copies held to one answer. That page retired; what the .mjs answered beyond the cases - the
 * functions it exported, every name in the fixture folded, the tooltip for both Dummys - was generated
 * from it once, before it was deleted, and is kept in the fixture's `frozen`, so owned.ts still answers
 * as the two did together.
 *
 * The cases that matter are the ones a wrong answer would hide: a pressing claimed by the wrong id,
 * an untagged folder claimed over a tagged one, a folder named the way the sleeve credited the
 * artist.
 *
 * Run it with:  node ui/test/owned.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const FIXTURE = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../tests/fixtures/pressings/owned.json'), 'utf8'))
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

;(() => {
  const O = require(path.join(OUT, 'owned.js'))
  console.log('\nowned.ts')
  const index = O.buildOwnedIndex(FIXTURE.albums)
  for (const item of FIXTURE.cases) check(item.label, run(O, index, item), item.expected)
  check('no index answers nothing', O.ownedForGroup(null, { groupId: 'dummy' }), { held: [], guessed: [] })
  check('...and holds no pressing', O.ownedForRelease(null, 'x'), [])

  console.log('\nas the main page\'s copy answered (frozen from owned.mjs before it retired)')
  const { frozen } = FIXTURE
  const exported = Object.keys(O).filter((key) => typeof O[key] === 'function').sort()
  check('exports the functions the .mjs did', exported, frozen.exported)
  //? one more pass over names nobody wrote a case for: every album's own name, both ways
  const names = FIXTURE.albums.flatMap((album) => [album.artist, album.album, album.path])
  check('...the names are the fixture\'s own', frozen.folded.map(([name]) => name), names)
  check('folds every name in the fixture as the .mjs did', names.map(O.foldName), frozen.folded.map(([, folded]) => folded))
  const group = FIXTURE.cases.find((item) => item.label === frozen.tooltip.case).args[0]
  check('words the tooltip as the .mjs did', O.describeGroupOwnership(O.ownedForGroup(O.buildOwnedIndex(FIXTURE.albums), group)).title, frozen.tooltip.title)

  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})()
