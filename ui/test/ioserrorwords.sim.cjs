/**
 * The iPhone app's error words are the web's (Phase 1): ios/scripts/export-error-words.cjs runs lib/errorWords.ts and
 * lib/signIn.ts on every case it holds and compares what they answer with the fixture DeadwaxCore's ErrorWordsTests
 * replay (ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/errors/error-words.json). A sentence, a class or a plumbing
 * pattern changed here and not there - or the fixture edited by hand - fails, saying how to bring them together:
 * run the script, and make ErrorWords.swift say the same.
 *
 * Run it with:  node ui/test/ioserrorwords.sim.cjs   (TMPDIR somewhere writable inside a sandbox)
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')

let failures = 0
try {
  const said = execFileSync(process.execPath, [path.join(REPO, 'ios/scripts/export-error-words.cjs'), '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  console.log(`  FAIL  ${String(error.stderr || error.message).trim()}`)
}

console.log(failures ? `\n${failures} failed` : '\nall passed')
process.exit(failures ? 1 : 0)
