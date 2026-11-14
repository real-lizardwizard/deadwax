/**
 * The iPhone app's Library's Shuffle brings a library's shuffle in, and its Songs pages every song, as this app's do
 * (notes/ios.md, "Phase 4, slice 5").
 *
 * The phone's Swift ports (ios/DeadwaxKit/Sources/DeadwaxCore/Shuffle.swift's ShuffleFeed and ShuffleFeedRun, and
 * Songs.swift) are held by ShuffleVectorTests to ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/shuffle/shuffle-vectors.json,
 * which ios/scripts/export-shuffle-vectors.cjs writes from what this app's own TypeScript answers - app/useShuffleFeed.ts
 * driven as the hook it is (startingElsewhere, songsAhead, and every ask it makes and every song it hands the player),
 * app/usePaged.ts's appendPage, and Songs' words from lib/yourLibrary.ts, lib/appFrame.ts, lib/artistPage.ts,
 * player/api.ts and LibraryViews.tsx. This runs that script with --check: every vector made again from the TypeScript
 * as it is today and compared byte for byte with the committed file. So a web rule changed here fails here until the
 * vectors are written again - and then the phone's Swift tests fail until the change is ported, rather than the phone
 * and the web quietly bringing a shuffle in differently.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosshuffle.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-shuffle-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  the shuffle's vectors are not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
