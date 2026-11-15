/**
 * The iPhone app's Requests tab draws every download under the web's headings, with the web's words, overlays, speeds
 * and looks (notes/ios.md, "Phase 6, slice 1: Requests").
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/Requests.swift, RequestOverlays.swift and
 * RequestsWatch.swift) is held by RequestsVectorTests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/requests/requests-vectors.json, which
 * ios/scripts/export-requests-vectors.cjs writes from what this app's own TypeScript answers - lib/requestsView.ts (the
 * board, every row's words, the badge, changes and focusAfterGone, watchingOf, stallsOn, asksAgain, doneLooks),
 * lib/downloadOverlay.ts, lib/speed.ts, lib/perPerson.ts, lib/myLibrary.ts's grantWords and partlyWords and
 * lib/format.ts's formatSpeed - and the numbers and words read from useDownloadJobs.ts, Requests.tsx, JobCard.tsx,
 * You.tsx and ConfirmCancelChoice.tsx. This runs that script with --check: every vector made again from the TypeScript
 * as it is today and compared byte for byte with the committed file. So a web rule changed here fails here until the
 * vectors are written again - and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosrequests.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-requests-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  Requests' vectors are not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
