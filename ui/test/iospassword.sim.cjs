/**
 * The iPhone app's Change password does what this app's does (notes/ios.md, "Change password on the phone"; Phase 8,
 * slice 10): who is offered it, the line over the form, what shows while typing - People's password rules and the same
 * password again (lib/ownPassword.ts changeOffered, changeLine, formProblem, formReady, doneWords, SAME_PASSWORD,
 * APPS_LINE; lib/people.ts passwordProblem, httpNote, PASSWORD_MIN, PASSWORD_MAX) - and what app/ChangePassword.tsx and
 * api/me.ts work out themselves, read out of their source: the fields' labels, the body sent, what a refusal of the
 * current password does, the route and the new session after it.
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/OwnPassword.swift) is held by its tests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/password/password-vectors.json, which
 * ios/scripts/export-password-vectors.cjs makes by running the TypeScript as it is. This runs it with --check: every
 * case made again from the TypeScript as it is today and compared byte for byte with the committed file - each source's
 * sha256 included, so even a change of words fails here. A web rule changed fails here until the fixture is written
 * again, and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iospassword.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPTS = [
  ['export-password-vectors.cjs', "Change password's fixture"],
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
