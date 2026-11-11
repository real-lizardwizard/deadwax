/**
 * The iPhone app's Navidrome gate says what this app's says (notes/ios.md, "Phase 1: the app"): the Library in place of
 * its albums when Navidrome isn't set up or isn't answering - its heading, lines and buttons, for each kind of reader -
 * and what a failed check means (deadwax unreached is offline; an error answer isn't).
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/NavidromeGate.swift) is held by its tests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/gate/navidrome.json, which ios/scripts/export-gate-vectors.cjs makes by
 * running app/NeedsNavidrome.tsx and lib/navidromeCheck.ts as they are. This runs that script with --check: every case
 * made again from the TypeScript as it is today and compared byte for byte with the committed file - each source's
 * sha256 included, so even a change of words fails here. A web rule changed fails here until the fixture is written
 * again, and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosgate.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-gate-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  the Navidrome gate's fixture is not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
