/**
 * The iPhone app's Needs a look does what this app's does (notes/ios.md, "Needs a look on the phone"; Phase 8, slice 6):
 * the list and its order (lib/metadataQueue.ts queueAlbums), its facets and their counts (lib/needsLook.ts facets,
 * facetAlbums, facetShown, isIgnoredOnly, summaryTotal), a session's rows and marks and the steps through it
 * (startSession, markFor, rowChanged, stepTarget, leavingAtEnd), the notes (ignoresUnsaved, navidromeNote), the count's
 * words (needsLookLabel), who it is for (lib/permissions.ts asksQueueSummary) - and what app/NeedsALook.tsx,
 * components/MetadataEditor.tsx's queue buttons, app/You.tsx's Manage row, app/useQueueSummary.ts and app/App.tsx work
 * out themselves, read out of their source. And (Phase 8, slice 7) its Library care does what this app's does too: Rescan's
 * facts (lib/libraryCare.ts scanTotals, scanAge), the runs' narrowing, scope and plans (narrowAlbums, scopeLine,
 * planWords), which albums each takes and what a run came to (lib/bulkTargets.ts bulkTargets, runBulk, bulkSummary), the
 * parts by permission (lib/permissions.ts careParts), In nobody's library's words (lib/myLibrary.ts heldByNobodyLine,
 * flagWords) - and what app/LibraryCare.tsx, app/useLibraryCare.ts and app/HeldByNobody.tsx work out themselves.
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/NeedsLook.swift, ScanAlbums.swift's MetadataQueue and
 * Managing.swift) is held by its tests to ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/care/care-vectors.json, which
 * ios/scripts/export-care-vectors.cjs makes by running the TypeScript as it is - and LibraryCare.swift to
 * Fixtures/care/library-care-vectors.json, which ios/scripts/export-library-care-vectors.cjs makes. This runs each with --check: every case
 * made again from the TypeScript as it is today and compared byte for byte with the committed file - each source's
 * sha256 included, so even a change of words fails here. A web rule changed fails here until the fixture is written
 * again, and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/ioscare.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPTS = [
  ['export-care-vectors.cjs', "Needs a look's fixture"],
  ['export-library-care-vectors.cjs', "Library care's fixture"],
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
