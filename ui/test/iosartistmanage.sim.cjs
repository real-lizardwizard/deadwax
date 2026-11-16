/**
 * The iPhone app's artist tools do what this app's artist page does (notes/ios.md, "The artist tools on the phone";
 * Phase 8, slice 5): which names the library files an artist's albums under (lib/artistManage.ts libraryNames), which
 * of them move and which folder takes their pictures (namesToMove, imagesFolder), Artist images' rules and words
 * (toggleChoice, byKind, slotLine, imageNotes, savedLine, matchLine, and app/ArtistPanel.tsx's own, read out of its
 * source), and Move albums' (refileView, canMove, moveLine, moveButton, refileAfter, refileOutcome, the subtitle and the
 * names Move applies).
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/ArtistManage.swift and ArtistManageFlow.swift) is held by
 * its tests to ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/artists/artist-manage-vectors.json, which
 * ios/scripts/export-artist-manage-vectors.cjs makes by running the TypeScript as it is. This runs it with --check:
 * every case made again from the TypeScript as it is today and compared byte for byte with the committed file - each
 * source's sha256 included, so even a change of words fails here. A web rule changed fails here until the fixture is
 * written again, and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosartistmanage.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPTS = [
  ['export-artist-manage-vectors.cjs', "the artist tools' fixture"],
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
