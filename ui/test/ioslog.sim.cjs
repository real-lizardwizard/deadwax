/**
 * The iPhone app's event log does what this app's does (notes/ios.md, "The event log on the phone"; Phase 8, slice 9):
 * the lines joined from the history and the stream, the gap a history not read leaves and the next fills, Clear, a
 * line's level and time (lib/eventLog.ts joinLine, joinHistory, clearLog, levelOf, lineTime, EMPTY_WORDS, STREAM_WORDS,
 * STREAM_RETRY_MS, LOG_KEPT), the stream's address (api/logs.ts logStreamUrl), the history's failure in words
 * (lib/errorWords.ts) - and what app/EventLog.tsx, lib/appRoutes.ts, app/App.tsx and app/access.ts work out themselves,
 * read out of their source.
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/EventLog.swift, EventStream.swift) is held by its tests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/log/log-vectors.json, which ios/scripts/export-log-vectors.cjs makes by
 * running the TypeScript as it is. This runs it with --check: every case made again from the TypeScript as it is today
 * and compared byte for byte with the committed file - each source's sha256 included, so even a change of words fails
 * here. A web rule changed fails here until the fixture is written again, and then the phone's Swift tests fail until
 * the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/ioslog.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPTS = [
  ['export-log-vectors.cjs', "the event log's fixture"],
]

let failures = 0
for (const [script, what] of SCRIPTS) {
  try {
    const said = execFileSync(process.execPath, [path.join(REPO, 'ios', 'scripts', script), '--check'], { cwd: REPO, encoding: 'utf8' })
    console.log(`  PASS  ${said.trim()}`)
  } catch (error) {
    failures++
    process.stdout.write(error.stdout || '')
    process.stderr.write(error.stderr || '')
    console.log(`  FAIL  ${what} is not what the web's TypeScript answers today (exit ${error.status})`)
  }
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
