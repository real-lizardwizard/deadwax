/**
 * The iPhone app's play history rules are the web's (app 0.8, notes/ios.md "Play history on the phone"):
 * ios/scripts/export-history.cjs runs lib/playHistory.ts on every case it holds - the numbers, a start's key, merged,
 * withNewest and withOlder, countedIn, afterFailure, retryAfter, and 300 seeded runs of Up Next's moves with a start
 * at every song begun, what queueShows and pastRows answer after each - and compares what it answers with the fixture
 * DeadwaxCore's HistoryVectorTests replays (ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/history/vectors.json). A
 * rule changed here and not there - or the fixture edited by hand - fails, saying how to bring them together: run the
 * script, and make PlayHistory.swift say the same.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/ioshistory.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')

let failures = 0
try {
  const said = execFileSync(process.execPath, [path.join(REPO, 'ios/scripts/export-history.cjs'), '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  console.log(`  FAIL  ${String(error.stderr || error.message).trim()}`)
}

console.log(failures ? `\n${failures} failed` : '\nall passed')
process.exit(failures ? 1 : 0)
