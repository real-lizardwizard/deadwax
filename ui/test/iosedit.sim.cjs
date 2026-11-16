/**
 * The iPhone app's Edit album does what this app's Edit album does (notes/ios.md, "Edit album on the phone"; Phase 8,
 * slice 1): which folder an album page's album is (lib/albumEdit.ts editFolders, folderChoices, editStatus and the
 * follow after a write), what is wrong with it (lib/metadataQueue.ts), and the Release editor - its queries and scores
 * (lib/release.ts), the payload Apply sends and the fields a pick seeds (components/MetadataEditor.tsx, read out of its
 * source), and every word of the preview and the apply (lib/retagPlan.ts).
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/AlbumEdit.swift, ScanAlbums.swift, Retag.swift,
 * RetagFlow.swift) is held by its tests to ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/edit/edit-vectors.json,
 * which ios/scripts/export-edit-vectors.cjs makes by running the TypeScript as it is. This runs that script with
 * --check: every case made again from the TypeScript as it is today and compared byte for byte with the committed
 * file - each source's sha256 included, so even a change of words fails here. A web rule changed fails here until
 * the fixture is written again, and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosedit.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-edit-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  Edit album's fixture is not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
