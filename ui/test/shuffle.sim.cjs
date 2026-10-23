/**
 * The Library's Shuffle (2.0.0-player.57, Part B of Up Next, shuffle and repeat): app/ShuffleSongs.tsx - the button
 * at the top of your albums or of Songs - and app/useShuffleFeed.ts, the feed App calls once, which brings the rest of
 * deadwax's order in as it plays. Compiled with the repo's TypeScript and rendered by a small stand-in for Preact, as
 * pins.sim.cjs renders Pinned, against a faked deadwax whose every ask is kept and answered when the check says.
 *
 * What it pins:
 *
 *  - The button: nothing asked until the list shows; its first page asked then (and again once it shows after
 *    SHUFFLE_FRESH_MS), aria-disabled "Getting ready…" until it is in, then "Shuffle" over "450 songs"; its tap plays
 *    that page from its first song, in its order, as a library's shuffle (its token, total, fetched and scope) - and
 *    asks for a new order for the next tap; one that won't come leaves it unready, saying why, and asks again the next
 *    time the list shows.
 *  - The feed: nothing while the queue is no library's shuffle, nor while FEED_BELOW or more of its songs follow; at
 *    49, the next page from where the queue has got to - one ask at a time, whatever renders meanwhile - handed to
 *    extendQueue; a page that won't come asked again FEED_RETRY_MS later; the whole order in, with Repeat off nothing
 *    more, with Repeat All a fresh order as the next round, never starting with the song that ends this one; the order
 *    gone from deadwax (a 404) a fresh one as the rest of this round, said once. It calls nothing but extendQueue.
 *  - (review) The claims: the ask after a tap names the order the tap played until one gets through; the feed's
 *    fresh orders are asked for claimed. `count` draws the "450 songs" line (above your albums only); a scope with
 *    no songs draws nothing. Repeat turned off with the next round queued: that round let go and the shuffle back
 *    on the round playing's whole order, nothing more asked; turned off while a fresh round is on its way: the ask
 *    let go, and an answer landing before the effect has run dropped; an empty fresh order appended as nothing,
 *    asked for once - no loop.
 *
 * Run it with:  node ui/test/shuffle.sim.cjs
 */

const { execFileSync } = require('child_process')
const fs = require('fs'), os = require('os'), path = require('path')

const UI = path.resolve(__dirname, '..')
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-shuffle-'))

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/app/ShuffleSongs.tsx', 'src/app/useShuffleFeed.ts', 'src/lib/upNext.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
  '--lib', 'es2022,dom,dom.iterable', '--jsx', 'react-jsx', '--jsxImportSource', 'preact',
], { cwd: UI, stdio: 'inherit' })

//? JSX as plain objects, and hooks with a cursor whose effects run on commit - pins.sim.cjs's stand-in
fs.mkdirSync(path.join(OUT, 'node_modules/preact'), { recursive: true })
fs.writeFileSync(path.join(OUT, 'node_modules/preact/index.js'), `exports.Fragment = 'fragment'\n`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/jsx-runtime.js'), `
exports.jsx = exports.jsxs = (type, props, key) => ({ type, props: props || {}, key })
exports.Fragment = 'fragment'
`)
fs.writeFileSync(path.join(OUT, 'node_modules/preact/hooks.js'), `
let current = null
function slot(init) { const i = current.cursor++; if (!(i in current.slots)) current.slots[i] = init(); return current.slots[i] }
const changed = (a, b) => !a || !b || a.length !== b.length || a.some((v, i) => !Object.is(v, b[i]))
exports.useState = (v) => { const s = slot(() => ({ v: typeof v === 'function' ? v() : v })); return [s.v, (x) => { s.v = typeof x === 'function' ? x(s.v) : x; globalThis.__shuffle.changed++ }] }
exports.useMemo = (f, deps) => { const s = slot(() => ({})); if (changed(s.deps, deps)) { s.v = f(); s.deps = deps } return s.v }
exports.useRef = (v) => slot(() => ({ current: v }))
exports.useCallback = (f) => f
exports.useEffect = exports.useLayoutEffect = (f, deps) => {
  const s = slot(() => ({}))
  if (changed(s.deps, deps)) { s.deps = deps; current.effects.push(s); s.f = f }
}
exports.root = (component) => {
  const root = { slots: [], cursor: 0, effects: [] }
  const render = (props) => { const outer = current; current = root; root.cursor = 0; try { return component(props) } finally { current = outer } }
  render.commit = () => { for (const s of root.effects.splice(0)) { if (typeof s.cleanup === 'function') s.cleanup(); s.cleanup = s.f() } }
  return render
}
`)

//? deadwax's shuffle routes, faked: every ask kept, answered when the check says; the notice; a song as the queue takes it
const write = (file, body) => fs.writeFileSync(path.join(OUT, file), body)
write('player/api.js', `
exports.shuffleStart = (scope, signal, how) => { globalThis.__shuffle.signal = signal; return globalThis.__shuffle.ask('start', scope, ...(how && (how.playing || how.claim) ? [how] : [])) }
exports.shufflePage = (token, offset) => globalThis.__shuffle.ask('page', token, offset)
exports.toQueueTrack = (song, album) => ({ id: song.id, title: song.title, artist: song.artist ?? '', album: song.album ?? album.name, albumId: song.albumId ?? album.id,
  coverArt: null, duration: 1, contentType: 'audio/flac', suffix: 'flac', sampleRate: 0, bitDepth: 0, channels: 0 })
`)
write('app/usePins.js', `exports.sayPins = (text) => globalThis.__shuffle.said.push(text)\n`)
write('api/http.js', `class ApiError extends Error { constructor(status, detail) { super(detail); this.status = status } }\nexports.ApiError = ApiError\n`)
write('player/icons.js', `exports.ShuffleIcon = () => ({ type: 'svg', props: {} })\n`)

const S = globalThis.__shuffle = {
  asks: [], open: [], said: [], changed: 0,
  ask(name, ...args) {
    S.asks.push([name, ...args])
    let resolve, reject
    const promise = new Promise((yes, no) => { resolve = yes; reject = no })
    S.open.push({ name, args, resolve, reject })
    return promise
  },
}
function answer(name, value) {
  const at = S.open.findIndex((one) => one.name === name)
  if (at < 0) throw new Error(`nothing asked of ${name}`)
  const [one] = S.open.splice(at, 1)
  if (value instanceof Error) one.reject(value)
  else one.resolve(value)
}
const settle = async () => { for (let i = 0; i < 6; i++) await new Promise((resolve) => setImmediate(resolve)) }

//? (2.0.0-player.62) this device's storage, as the player's Normalization is read from it at the tap
const stored = new Map()
globalThis.localStorage = { getItem: (key) => (stored.has(key) ? stored.get(key) : null), setItem: (key, value) => stored.set(key, String(value)), removeItem: (key) => stored.delete(key) }

//? timers the checks run by hand: the feed's retry
const timers = []
globalThis.setTimeout = (fn, ms) => { timers.push({ fn, ms }); return timers.length }
let clock = 1_000_000
Date.now = () => clock

const hooks = require(path.join(OUT, 'node_modules/preact/hooks.js'))
const { ShuffleSongs, SHUFFLE_FRESH_MS, SHUFFLE_GETTING_READY, SHUFFLE_UNREADY } = require(path.join(OUT, 'app/ShuffleSongs.js'))
const F = require(path.join(OUT, 'app/useShuffleFeed.js'))
const { ApiError } = require(path.join(OUT, 'api/http.js'))
const U = require(path.join(OUT, 'lib/upNext.js'))

let failures = 0
let finished = false
process.on('exit', () => {
  if (!finished) {
    console.log('\nSTOPPED before the end - a check was left waiting')
    process.exitCode = 1
  }
})
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`))
}
function find(test, within) {
  const hits = []
  const visit = (node) => {
    if (!node || typeof node !== 'object') return
    if (Array.isArray(node)) { node.forEach(visit); return }
    if (test(node)) hits.push(node)
    visit(node.props?.children)
  }
  visit(within)
  return hits
}
function words(node) {
  if (node === null || node === undefined || node === false || node === true) return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(words).join('')
  if (typeof node.type === 'function') return ''
  return words(node.props?.children)
}
const byClass = (name) => (node) => typeof node.props?.class === 'string' && node.props.class.split(' ').includes(name)
const songs = (from, count, prefix = 's') => Array.from({ length: count }, (_, i) => ({ id: `${prefix}${from + i}`, title: `Song ${from + i}`, album: 'A', albumId: 'al' }))

;(async () => {
  console.log('\nthe Library\'s Shuffle: its first page in hand before the tap')
  {
    S.asks.length = 0
    const played = []
    const actions = { playTracks: (...args) => played.push(args) }
    const render = hooks.root(ShuffleSongs)
    const draw = (shown) => { const tree = render({ scope: 'yours', shown, actions, count: true }); render.commit(); return tree }
    let tree = draw(false)
    check('the list not showing: nothing asked', S.asks, [])
    tree = draw(true)
    const button = () => find(byClass('app-shuffle-button'), tree)[0]
    check('shown: its first page asked, the button unready, saying so', [S.asks, button().props['aria-disabled'], words(button())], [[['start', 'yours']], true, SHUFFLE_GETTING_READY])
    button().props.onClick()
    check('...a tap while it is getting ready plays nothing', played, [])
    answer('start', { token: 't1', total: 450, songs: songs(1, 200) })
    await settle()
    tree = draw(true)
    check('its page in: "Shuffle", "450 songs" under it', [button().props['aria-disabled'], words(button()), words(find(byClass('app-store-line'), tree))], [false, 'Shuffle', '450 songs'])
    S.asks.length = 0
    button().props.onClick()
    check('the tap: that page, from its first song, in its order, as a library\'s shuffle - then a new order asked for the next tap',
      [played.map(([tracks, start, shuffle, paged]) => [tracks.length, tracks[0].id, tracks[199].id, start, shuffle, paged]), S.asks],
      [[[200, 's1', 's200', 0, false, { token: 't1', total: 450, fetched: 200, scope: 'yours', level: 'track' }]], [['start', 'yours', { playing: 't1' }]]])
    //? (2.0.0-player.62) Normalization, Automatic on a fresh device: a shuffle is songs, each levelled on its own
    check('...its songs queued as songs: each at its own level, and that level on the shuffle, for its feed',
      [...new Set(played[0][0].map((track) => track.level))], ['track'])
    answer('start', new Error('Navidrome answered 500'))
    await settle()
    tree = draw(true)
    check('a first page that won\'t come: unready, why in its title and read out', [button().props['aria-disabled'], button().props.title, words(find((node) => node.props?.role === 'status', tree))], [true, SHUFFLE_UNREADY, SHUFFLE_UNREADY])
    S.asks.length = 0
    draw(false)
    draw(true)
    check('...asked again the next time the list shows - still naming the order the tap played, which deadwax claims', S.asks, [['start', 'yours', { playing: 't1' }]])
    answer('start', { token: 't2', total: 450, songs: songs(1, 200) })
    await settle()
    draw(true)
    S.asks.length = 0
    draw(false)
    draw(true)
    check('shown again soon after: the page in hand kept, nothing asked', S.asks, [])
    clock += SHUFFLE_FRESH_MS + 1
    draw(false)
    draw(true)
    check('...shown again after SHUFFLE_FRESH_MS: asked afresh (songs added meanwhile come in)', S.asks, [['start', 'yours']])
    answer('start', { token: 't3', total: 450, songs: songs(1, 200) })
    await settle()
    check('...once an ask naming it got through, it is named no more', S.asks, [['start', 'yours']])
  }
  {
    //? the Songs views' head counts the songs already; a scope with nothing in it draws no dead button
    S.asks.length = 0
    const actions = { playTracks: () => {} }
    const render = hooks.root(ShuffleSongs)
    const draw = () => { const tree = render({ scope: 'store', shown: true, actions }); render.commit(); return tree }
    draw()
    answer('start', { token: 'c1', total: 87, songs: songs(1, 87) })
    await settle()
    const tree = draw()
    check('without `count` (the Songs views): the button, and no second "87 songs" under it', [words(find(byClass('app-shuffle-button'), tree)[0]), find(byClass('app-store-line'), tree).length], ['Shuffle', 0])
    clock += SHUFFLE_FRESH_MS + 1
    const empty = hooks.root(ShuffleSongs)
    const drawEmpty = () => { const out = empty({ scope: 'yours', shown: true, actions, count: true }); empty.commit(); return out }
    drawEmpty()
    answer('start', { token: 'c2', total: 0, songs: [] })
    await settle()
    check('a scope with no songs at all (no starred albums yet): nothing drawn - not a dead "Shuffle" over "0 songs"', drawEmpty(), null)
  }

  console.log('\nthe shuffle\'s level (2.0.0-player.62): queued at the tap, its feed at the same level')
  {
    //? Off: nothing levelled, nothing said on the shuffle - the queue exactly what it was before the setting
    stored.set('deadwax-player-normalization', 'off')
    S.asks.length = 0
    const played = []
    const render = hooks.root(ShuffleSongs)
    const draw = () => { const tree = render({ scope: 'store', shown: true, actions: { playTracks: (...args) => played.push(args) } }); render.commit(); return tree }
    let tree = draw()
    answer('start', { token: 'o1', total: 3, songs: songs(1, 3) })
    await settle()
    tree = draw()
    find(byClass('app-shuffle-button'), tree)[0].props.onClick()
    check('under Off: no level on the songs, none on the shuffle', [played[0][0].map((track) => 'level' in track), played[0][3]],
      [[false, false, false], { token: 'o1', total: 3, fetched: 3, scope: 'store' }])
    answer('start', { token: 'o2', total: 3, songs: songs(1, 3) })
    await settle()
    //? By album: each song at its own album's level, the shuffle too
    stored.set('deadwax-player-normalization', 'album')
    tree = draw()
    find(byClass('app-shuffle-button'), tree)[0].props.onClick()
    check('under By album: album, on each song and on the shuffle', [[...new Set(played[1][0].map((track) => track.level))], played[1][3].level], [['album'], 'album'])
    stored.delete('deadwax-player-normalization')
    S.open.length = 0

    //? the feed: the rest of the order queued at the level the shuffle has - whatever the setting says now
    const tracks = (list, level) => list.map((song) => ({ id: song.id, title: song.title, artist: '', album: 'A', albumId: 'al', coverArt: null, duration: 1, contentType: 'audio/flac', suffix: 'flac', sampleRate: 0, bitDepth: 0, channels: 0, ...(level ? { level } : {}) }))
    for (const level of ['track', undefined]) {
      S.asks.length = 0
      stored.set('deadwax-player-normalization', 'album')
      const order = songs(1, 260)
      const extended = []
      const player = {
        queue: U.startUpNext(tracks(order.slice(0, 200), level), 0, false, Math.random, { token: 'f1', total: 260, fetched: 200, scope: 'store', ...(level ? { level } : {}) }),
        repeat: 'all',
        extendQueue(token, more, next) {
          extended.push([more.map((track) => track.level ?? null), next ?? null])
          player.queue = U.withMore(player.queue, token, more, next)
        },
      }
      const feed = hooks.root(() => F.useShuffleFeed({ ...player }))
      const turn = async () => { feed(); feed.commit(); await settle() }
      player.queue = { ...player.queue, index: 190 }
      await turn()
      answer('page', { total: 260, songs: order.slice(200) })
      await turn()
      player.queue = { ...player.queue, index: 255 }
      await turn()
      answer('start', { token: 'f2', total: 2, songs: songs(900, 2) })
      await turn()
      check(`a ${level ?? 'Off'} shuffle's next page and next round queued at ${level ?? 'no level'} - never the setting's album`,
        extended.map(([levels, next]) => [[...new Set(levels)], next && next.level !== undefined ? next.level : null]),
        [[[level ?? null], null], [[level ?? null], level ?? null]])
      stored.delete('deadwax-player-normalization')
      S.open.length = 0
    }
  }

  console.log('\nthe feed: the rest of the order, as the queue nears the end of what it has')
  {
    S.asks.length = 0
    S.said.length = 0
    const order = songs(1, 450)
    const tracks = (list) => list.map((song) => ({ id: song.id, title: song.title, artist: '', album: 'A', albumId: 'al', coverArt: null, duration: 1, contentType: 'audio/flac', suffix: 'flac', sampleRate: 0, bitDepth: 0, channels: 0 }))
    const extended = []
    const player = {
      queue: U.startUpNext(tracks(order.slice(0, 200)), 0, false, Math.random, { token: 't1', total: 450, fetched: 200, scope: 'store' }),
      repeat: 'off',
      extendQueue(token, more, next) {
        extended.push([token, more.length, more[0]?.id ?? null, next ?? null])
        player.queue = U.withMore(player.queue, token, more, next)
      },
    }
    const feed = hooks.root(() => F.useShuffleFeed({ ...player }))
    const turn = async () => { feed(); feed.commit(); await settle() }
    const at = (index) => { player.queue = { ...player.queue, index } }
    await turn()
    check('199 songs after the song playing: nothing asked', S.asks, [])
    at(149)
    await turn()
    check('...50 after it: still nothing', [F.songsAhead(player.queue), S.asks], [50, []])
    at(150)
    await turn()
    check('49 after it: the next page, from where the order has got to', [F.songsAhead(player.queue), S.asks], [49, [['page', 't1', 200]]])
    await turn()
    //? Repeat changed meanwhile - the effect runs again - and still the one ask
    player.repeat = 'all'
    await turn()
    player.repeat = 'off'
    await turn()
    check('...one ask at a time, however often it is drawn or Repeat changed meanwhile', S.asks.length, 1)
    answer('page', new Error('the network dropped'))
    await turn()
    check('a page that won\'t come: asked again FEED_RETRY_MS later, nothing meanwhile', [S.asks.length, timers.map((timer) => timer.ms)], [1, [F.FEED_RETRY_MS]])
    timers.shift().fn()
    await turn()
    check('...and then, from the same place', S.asks.slice(1), [['page', 't1', 200]])
    answer('page', { total: 450, songs: order.slice(200, 400) })
    await turn()
    check('the page handed to extendQueue, the order\'s token with it - nothing else of the player called', extended, [['t1', 200, 's201', null]])
    at(352)
    await turn()
    answer('page', { total: 450, songs: order.slice(400) })
    await turn()
    check('the last page: the order whole', [player.queue.upNext.paged.fetched, extended.length], [450, 2])
    at(420)
    S.asks.length = 0
    await turn()
    check('the whole order in, Repeat off: nothing more - the queue ends after its last song', S.asks, [])
    player.repeat = 'all'
    await turn()
    check('...with Repeat All: a fresh order, asked for claimed (it plays at once)', S.asks, [['start', 'store', { claim: true }]])
    //? the fresh order begins with the song that ends this one: it is moved later
    answer('start', { token: 't2', total: 450, songs: [order[449], ...order.slice(0, 199)] })
    await turn()
    const fresh = extended[2]
    check('...as the next round, never starting with the song that ends this one', [fresh[0], fresh[1], fresh[2] !== 's450', fresh[3], player.queue.upNext.marks[450].pass, player.queue.upNext.paged.token],
      ['t1', 200, true, { token: 't2', total: 450, fetched: 0, scope: 'store' }, 1, 't2'])
    check('startingElsewhere alone: the first swapped only when it is the song ending - with something else to start with',
      [F.startingElsewhere(tracks(songs(1, 3)), 's1', () => 0).map((t) => t.id), F.startingElsewhere(tracks(songs(1, 3)), 's9').map((t) => t.id), F.startingElsewhere(tracks(songs(1, 1)), 's1').map((t) => t.id)],
      [['s2', 's1', 's3'], ['s1', 's2', 's3'], ['s1']])
  }

  console.log('\nthe feed: an order deadwax no longer holds starts over, said once')
  {
    S.asks.length = 0
    S.said.length = 0
    const extended = []
    const tracks = (list) => list.map((song) => ({ id: song.id, title: song.title, artist: '', album: 'A', albumId: 'al', coverArt: null, duration: 1, contentType: 'audio/flac', suffix: 'flac', sampleRate: 0, bitDepth: 0, channels: 0 }))
    const player = {
      queue: { ...U.startUpNext(tracks(songs(1, 200)), 0, false, Math.random, { token: 'old', total: 450, fetched: 200, scope: 'yours' }), index: 160 },
      repeat: 'off',
      extendQueue(token, more, next) {
        extended.push([token, more.length, next ?? null])
        player.queue = U.withMore(player.queue, token, more, next)
      },
    }
    const feed = hooks.root(() => F.useShuffleFeed({ ...player }))
    const turn = async () => { feed(); feed.commit(); await settle() }
    await turn()
    answer('page', new ApiError(404, 'gone'))
    await turn()
    check('a 404: a fresh order asked for, claimed', S.asks, [['page', 'old', 200], ['start', 'yours', { claim: true }]])
    answer('start', { token: 'new', total: 450, songs: songs(1, 200, 'n') })
    await turn()
    check('...appended as the rest of this round, the shuffle from then on the new one, the notice said once',
      [extended, player.queue.upNext.marks[200].pass, player.queue.upNext.paged.token, S.said], [[['old', 200, { token: 'new', total: 450, fetched: 0, scope: 'yours' }]], 0, 'new', [F.SHUFFLE_STARTED_OVER]])
    //? (2.0.0-player.64) the words: an order a day old (a shuffle picked up again later) is no restart
    check('...in words true of a restart and of a day-old order alike', F.SHUFFLE_STARTED_OVER, 'Your shuffle started over - deadwax no longer had its order')
    const plain = { queue: U.startUpNext(tracks(songs(1, 3)), 0), repeat: 'all', extendQueue: () => extended.push('plain') }
    const quiet = hooks.root(() => F.useShuffleFeed(plain))
    S.asks.length = 0
    quiet()
    quiet.commit()
    await settle()
    check('a queue that is no library\'s shuffle: nothing asked, nothing extended', [S.asks, extended.includes('plain')], [[], false])
  }

  console.log('\nthe feed and Repeat: turned off, the shuffle ends after every song once (2.0.0-player.57 review)')
  {
    const tracks = (list) => list.map((song) => ({ id: song.id, title: song.title, artist: '', album: 'A', albumId: 'al', coverArt: null, duration: 1, contentType: 'audio/flac', suffix: 'flac', sampleRate: 0, bitDepth: 0, channels: 0 }))
    //? a whole order of 60 in hand (fetched === total), 39 songs after the one playing - under FEED_BELOW
    const make = (repeat) => {
      const extended = []
      const player = {
        queue: { ...U.startUpNext(tracks(songs(1, 60)), 0, false, Math.random, { token: 'w1', total: 60, fetched: 60, scope: 'store' }), index: 20 },
        repeat,
        extendQueue(token, more, next) {
          extended.push([token, more.length, next?.token ?? null])
          player.queue = U.withMore(player.queue, token, more, next)
        },
      }
      const feed = hooks.root(() => F.useShuffleFeed({ ...player }))
      const turn = async () => { feed(); feed.commit(); await settle() }
      return { player, extended, feed, turn }
    }
    {
      S.asks.length = 0
      const { player, extended, turn } = make('all')
      await turn()
      answer('start', { token: 'w2', total: 450, songs: songs(1, 200, 'n') })
      await turn()
      check('Repeat All at the order\'s end: the next round appended under a fresh order', [extended, player.queue.upNext.paged.token, player.queue.tracks.length], [[['w1', 200, 'w2']], 'w2', 260])
      player.queue = U.withRepeat(player.queue, 'off')
      player.repeat = 'off'
      S.asks.length = 0
      await turn()
      await turn()
      check('...Repeat turned off: the next round let go, the shuffle back on the round playing\'s order - whole - and nothing asked',
        [player.queue.tracks.length, player.queue.upNext.paged, S.asks], [60, { token: 'w1', total: 60, fetched: 60, scope: 'store' }, []])
      check('...as the pure model has it: the rounds kept by round, none left once back', player.queue.upNext.pagedRounds, [])
    }
    {
      S.asks.length = 0
      const { player, extended, turn } = make('all')
      await turn()
      check('a fresh round asked for', S.asks, [['start', 'store', { claim: true }]])
      const signal = S.signal
      player.repeat = 'off'
      await turn()
      check('...Repeat turned off while it is on its way: the ask called off', signal?.aborted, true)
      answer('start', { token: 'w2', total: 450, songs: songs(1, 200, 'n') })
      await turn()
      check('...Repeat turned off while it was on its way: the ask let go, its answer appended nothing', [extended, player.queue.tracks.length], [[], 60])
      player.repeat = 'all'
      await turn()
      check('...Repeat All again: asked afresh', S.asks.length, 2)
      answer('start', { token: 'w3', total: 450, songs: songs(1, 200, 'n') })
      await turn()
    }
    {
      S.asks.length = 0
      const { player, extended, feed, turn } = make('all')
      await turn()
      //? drawn with Repeat off, its effect not yet run, as the answer lands in between
      player.repeat = 'off'
      feed()
      answer('start', { token: 'w2', total: 450, songs: songs(1, 200, 'n') })
      await settle()
      feed.commit()
      await settle()
      check('...an answer landing after a render with Repeat off, before the effect ran: dropped all the same', extended, [])
    }
    {
      S.asks.length = 0
      S.said.length = 0
      const { player, extended, turn } = make('all')
      await turn()
      answer('start', { token: 'e1', total: 0, songs: [] })
      for (let i = 0; i < 4; i++) await turn()
      check('a fresh order with no songs (the library emptied meanwhile): nothing appended, the queue as it was, asked once - no loop',
        [extended, player.queue.upNext.paged.token, S.asks.length, S.said], [[['w1', 0, 'e1']], 'w1', 1, []])
    }
  }

  finished = true
  console.log(failures ? `\n${failures} FAILED` : '\nall passed')
  process.exit(failures ? 1 : 0)
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
