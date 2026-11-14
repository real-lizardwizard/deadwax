/**
 * The iPhone app's Search reads the box, says whose a row is, makes Top results and the sections, and says every line as
 * this app's Search does (notes/ios.md, "Phase 5, slice 1").
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/SearchReading.swift, SearchList.swift, Owned.swift) is
 * held by SearchVectorTests to ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/search/search-vectors.json, which
 * ios/scripts/export-search-vectors.cjs writes from what this app's own TypeScript answers - lib/searchList.ts (whose,
 * the pool, the sections, matchTier, Top results, rowLine, the words), lib/searchQuery.ts (artistNames, searchQuery),
 * lib/searchResults.ts, lib/songs.ts's titleKey, lib/owned.ts and lib/whose.ts - and a few numbers and words read from
 * api.ts and Search.tsx. This runs that script with --check: every vector made again from the TypeScript as it is today
 * and compared byte for byte with the committed file. So a web rule changed here fails here until the vectors are
 * written again - and then the phone's Swift tests fail until the change is ported, rather than the phone and the web
 * quietly disagreeing about what "portishead" finds first.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iossearch.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-search-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  Search's vectors are not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
