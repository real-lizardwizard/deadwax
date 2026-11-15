/**
 * The iPhone app's Manage section offers what this app's You offers (notes/ios.md, "Phase 7: Managing"): which
 * managing tools show for which permissions - lib/permissions.ts managing and albumEdit, over every set of
 * permissions and a run of /deadwax/me answers through app/access.ts - and the address each opens at in the web app
 * (lib/appRoutes.ts formatRoute and parseHash: each Managing page as You opens it, the Library's and You's roots, an
 * album's page), with You's Manage section read out of its source (its title, its rows in order) and Change
 * password's offer (lib/ownPassword.ts).
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/Managing.swift) is held by its tests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/managing/managing-vectors.json, which
 * ios/scripts/export-managing-vectors.cjs makes by running the TypeScript as it is. This runs that script with
 * --check: every case made again from the TypeScript as it is today and compared byte for byte with the committed
 * file - each source's sha256 included, so even a change of words fails here. A web rule changed fails here until
 * the fixture is written again, and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosmanaging.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-managing-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  Manage's fixture is not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
