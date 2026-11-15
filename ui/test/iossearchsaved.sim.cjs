/**
 * The iPhone app's Search draws what's saved at the library's moment, lets MusicBrainz's answer add only what isn't
 * there, keeps a kind view's rows where they were drawn, keeps the last answers and pages More from MusicBrainz as this
 * app's Search does (notes/ios.md, "Phase 5, slice 4").
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/SearchSaved.swift, and slice 4's half of SearchList.swift)
 * is held by SearchSavedVectorTests to ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/search/search-saved-vectors.json,
 * which ios/scripts/export-search-saved-vectors.cjs writes from what this app's own TypeScript answers -
 * lib/searchList.ts (savedFor, studioGroup, kindArea, the pool with what's saved, candidatesOf, Top results' saved
 * marks, sectionRows, lateRows, drawnCounts, savedWords, musicBrainzWords, savedAwayWords, nothingMoreWords),
 * lib/searchResults.ts (appendPage, morePages, morePageWords), lib/songs.ts (appendSongs, moreSongsWords) and
 * app/searchAnswers.ts (keepAnswer, keptAnswer) - and More's words read from Search.tsx. This runs that script with
 * --check: every vector made again from the TypeScript as it is today and compared byte for byte with the committed
 * file. So a web rule changed here fails here until the vectors are written again - and then the phone's Swift tests
 * fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iossearchsaved.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-search-saved-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  Search's saved, kept and More vectors are not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
