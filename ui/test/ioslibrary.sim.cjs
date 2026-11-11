/**
 * The iPhone app's Library sorts, heads, finds and indexes albums as this app does (notes/ios.md, Phase 1).
 *
 * The phone's Swift ports (ios/DeadwaxKit/Sources/DeadwaxCore: Fold, AlbumTime, Shelves, ShelfIndex,
 * AlbumIndexState, NewMarks, LibraryWords) are held by their tests to vectors in
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/library/, which ios/scripts/export-library-vectors.cjs writes from
 * what this app's own TypeScript answers - lib/shelves.ts, lib/owned.ts's foldName, lib/myLibrary.ts, lib/appFrame.ts,
 * lib/yourLibrary.ts, and app/albumIndex.ts and app/useMyLibrary.ts run as they are. This runs that script with
 * --check: every vector made again from the TypeScript as it is today, and from this Node's Date.parse, and compared
 * byte for byte with the committed files. So a web rule changed here fails here until the vectors are written again
 * - and then the phone's Swift tests fail until the change is ported, rather than the phone and the web quietly
 * disagreeing about the order of someone's library.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/ioslibrary.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-library-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  the Library's vectors are not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
