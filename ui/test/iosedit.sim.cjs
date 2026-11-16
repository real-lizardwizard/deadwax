/**
 * The iPhone app's Edit album does what this app's Edit album does (notes/ios.md, "Edit album on the phone"; Phase 8,
 * slices 1-4): which folder an album page's album is (lib/albumEdit.ts editFolders, folderChoices, editStatus and the
 * follow after a write), what is wrong with it (lib/metadataQueue.ts), and the Release editor - its queries and scores
 * (lib/release.ts), the payload Apply sends and the fields a pick seeds (components/MetadataEditor.tsx, read out of its
 * source), and every word of the preview and the apply (lib/retagPlan.ts); and its other parts - Tags (lib/tagEdit.ts,
 * a track's page from lib/trackInspector.ts, components/TrackTagEditor.tsx's words), Artwork and Lyrics, and Delete.
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/AlbumEdit.swift, ScanAlbums.swift, Retag.swift,
 * RetagFlow.swift, TagEdit.swift, TrackInspector.swift and the rest) is held by its tests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/edit/edit-vectors.json and edit-parts-vectors.json, which
 * ios/scripts/export-edit-vectors.cjs and export-edit-parts-vectors.cjs make by running the TypeScript as it is. This
 * runs both scripts with --check: every case made again from the TypeScript as it is today and compared byte for byte
 * with the committed file - each source's sha256 included, so even a change of words fails here. A web rule changed
 * fails here until the fixture is written again, and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosedit.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPTS = [
  ['export-edit-vectors.cjs', "Edit album's fixture"],
  ['export-edit-parts-vectors.cjs', "Edit album's parts' fixture"],
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
