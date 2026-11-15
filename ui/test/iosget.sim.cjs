/**
 * The iPhone app's Get sends what the web's Get sends, and its store line and Sources sheet say, filter and rank what
 * the web's do (notes/ios.md, "Phase 6, slice 2: Get and Sources").
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/GetRelease.swift, StoreLine.swift, Sources.swift,
 * GetSettings.swift and Whose.withStoreLine) is held by GetVectorTests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/get/get-vectors.json, which ios/scripts/export-get-vectors.cjs writes
 * from what this app's own TypeScript answers - lib/releasePayload.ts (the one download payload builder, over the main
 * page's two Find buttons' bodies and the real pressings in tests/fixtures/pressings/), lib/release.ts's edition words
 * and video rule, lib/pressings.ts's getGroup, lib/candidates.ts (the filters, the sorts, a card's facts and reasoning,
 * every line of the sheet, the store's status and notes), lib/getSettings.ts (the chips, readGetSettings),
 * lib/perPerson.ts (storeStatusFor, withoutJoin, the floor's word, candidateQuality), lib/whose.ts's withStoreLine and
 * lib/format.ts's formatSize - and the words read from Sources.tsx, SourceCard.tsx, ReleaseGroupPage.tsx and
 * permissions.ts. This runs that script with --check: every vector made again from the TypeScript as it is today and
 * compared byte for byte with the committed file. So a web rule changed here fails here until the vectors are written
 * again - and then the phone's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosget.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-get-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  Get's vectors are not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
