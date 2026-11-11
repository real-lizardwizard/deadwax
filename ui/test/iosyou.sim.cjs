/**
 * The iPhone app's You tab says what this app's You says (notes/ios.md, Phase 1): its headline - the avatar's letter,
 * the name, the line under it - About's Version and Logins, when Account and the UNVERIFIED line are drawn, and the
 * words it shares with it (No sign-in needed, Not known, UNVERIFIED, the section titles, the note under Normalization).
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/YouLines.swift) is held by its tests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/you/you.json, which ios/scripts/export-you-vectors.cjs reads out of
 * app/You.tsx and lib/permissions.ts as written. This runs that script with --check: every case made again from the
 * TypeScript as it is today and compared byte for byte with the committed file - each piece's sha256 included, so even
 * a change of words fails here. A web rule changed fails here until the fixture is written again, and then the
 * phone's Swift tests fail until the change is ported.
 *
 * Run it with:  node ui/test/iosyou.sim.cjs   (it needs no TMPDIR, but takes one as the other sims do)
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-you-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  You's fixture is not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
