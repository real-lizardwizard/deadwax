/**
 * The iPhone app's artists sort, head, find, index and play as this app's do (notes/ios.md, "Phase 4, slice 4").
 *
 * The phone's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/Artists.swift) is held by ArtistVectorTests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/artists/artist-vectors.json, which ios/scripts/export-artist-vectors.cjs
 * writes from what this app's own TypeScript answers - lib/shelves.ts's artist rules, lib/artistPage.ts's rows, lines
 * and inTurns, lib/yourLibrary.ts's yourArtists, lib/appFrame.ts's titles - and a few words read from
 * LibrarySection.tsx, ArtistPage.tsx and persisted.ts. This runs that script with --check: every vector made again from
 * the TypeScript as it is today and compared byte for byte with the committed file. So a web rule changed here fails
 * here until the vectors are written again - and then the phone's Swift tests fail until the change is ported, rather
 * than the phone and the web quietly disagreeing about the order of someone's artists.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosartists.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-artist-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  the artists' vectors are not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
