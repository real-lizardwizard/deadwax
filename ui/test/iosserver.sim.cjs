/**
 * The iPhone app's Server settings does what this app's does (notes/ios.md, "Server settings on the phone"; Phase 8,
 * slice 8): which tab a group sits on and the tabs' marks (lib/serverSettings.ts tabForGroup, tabMarks), the drafts and
 * the one save (editedEnvDraft, draftsAfterSave), the note asking for a secret again (retypeSecretNote), MusicBrainz's
 * saved answers' line (lib/musicbrainzAnswers.ts describeBytes, describeSavedAnswers, savedAnswersKey), Re-time's
 * sentence (lib/lyrics.ts describeRetime), Connections' words (lib/errorWords.ts pingWords, unansweredLine) - and what
 * app/ServerSettings.tsx, components/SettingsView.tsx, components/RetimeLyrics.tsx, components/MusicBrainzAnswers.tsx,
 * app/You.tsx, app/App.tsx and app/access.ts work out themselves, read out of their source.
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/ServerSettings.swift) is held by its tests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/server/server-vectors.json, which ios/scripts/export-server-vectors.cjs
 * makes by running the TypeScript as it is. This runs it with --check: every case made again from the TypeScript as it
 * is today and compared byte for byte with the committed file - each source's sha256 included, so even a change of
 * words fails here. A web rule changed fails here until the fixture is written again, and then the phone's Swift tests
 * fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosserver.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPTS = [
  ['export-server-vectors.cjs', "Server settings' fixture"],
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
