/**
 * The iPhone app's People does what this app's does (notes/ios.md, "People on the phone"; Phase 8, slice 11): the rules
 * a new person and a reset are typed against, what each row says and offers (lib/people.ts nameProblem, displayProblem,
 * formProblem, formReady, chips, signInWords, libraryWords, librariesWarning, actions, refusals, removeLines,
 * removeReady, makeAdminWords, unmakeAdminWords, knownWords, madeWords, resetWords, versionNote, peopleView; lib/
 * permissions.ts checkboxes, lockedReason, changed, savedWords) - and what app/People.tsx, UnlockPeople.tsx,
 * AddPerson.tsx, ResetPassword.tsx, RemovePerson.tsx, usePeople.ts and api/people.ts work out themselves, read out of
 * their source: the labels and buttons, each body sent, which actions are drawn, the flip's and Forget's words, what a
 * `locked` refusal does, each route.
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/People.swift, PeopleFlow.swift) is held by its tests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/people/people-vectors.json, which
 * ios/scripts/export-people-vectors.cjs makes by running the TypeScript as it is. This runs it with --check: every
 * case made again from the TypeScript as it is today and compared byte for byte with the committed file - each source's
 * sha256 included, so even a change of words fails here. A web rule changed fails here until the fixture is written
 * again, and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iospeople.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPTS = [
  ['export-people-vectors.cjs', "People's fixture"],
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
