#!/usr/bin/env node
/**
 * The tables WebCollation (ios/DeadwaxKit/Sources/DeadwaxCore/Collation.swift - the phone's localeCompare) weighs
 * characters by, made from what this Node's ICU answers (notes/ios.md, "Phase 5, slice 3, after its review"):
 *
 * - `variables`: the punctuation and symbols ICU weighs before the digits, in its order - its punctuation, then from
 *   "`" its symbols, then from "¤" its currency - and `variableTies`, those weighing as the one before them at the
 *   first level and differing at the second (’ after '); `unlistedSymbolsBefore`, the symbol an emoji (any symbol
 *   the table doesn't list) stands just before;
 * - `marks`: the combining marks in ICU's order at the second level, and `markTies`;
 * - `letterPlaces`: each Latin letter beyond a-z, then the letter of a-z it follows (shifted 8) and its place after it -
 *   ə after e, ŧ after t, ʻ before z, ʒ and ʼ after it - and `letterTies`;
 * - `variants`: the letters ICU weighs as one of a-z with a mark of its own (ø, đ, ð, ł, ħ): each, the letter, and its
 *   weight among the marks' at the second level (a mark's is 8 for each before it and 8 more); and
 *   `middleDotAfterL`, the weight a middle dot after an l takes there (ICU weighs "l·" as one letter: "col·lecció").
 *
 * Written between Collation.swift's BEGIN and END lines. With --check, made again and compared with what is there -
 * ui/test/iossearchsongs.sim.cjs runs it so - when this Node's ICU is the one they were made with. Another ICU makes
 * other tables, not wrong ones, so then it says which and passes; the song vectors still hold the order itself.
 *
 * Run it with:  node ios/scripts/collation-tables.cjs [--check]
 */
'use strict'

const fs = require('fs')
const path = require('path')

const FILE = path.join(__dirname, '..', 'DeadwaxKit', 'Sources', 'DeadwaxCore', 'Collation.swift')
const BEGIN = '    // BEGIN collation-tables.cjs'
const END = '    // END collation-tables.cjs'

const full = new Intl.Collator('en-US')
const accent = new Intl.Collator('en-US', { sensitivity: 'accent' })
const base = new Intl.Collator('en-US', { sensitivity: 'base' })
const ch = (cp) => String.fromCodePoint(cp)
const range = ([a, b]) => Array.from({ length: b - a + 1 }, (_, i) => a + i)
const ranges = (list) => [...new Set(list.flatMap(range))].sort((a, b) => a - b)
const decomposes = (cp) => ch(cp).normalize('NFKD') !== ch(cp)
const is = (pattern) => (cp) => pattern.test(ch(cp))
const sortedBy = (collator, list, key = (item) => item) => [...list].sort((a, b) => collator.compare(key(a), key(b)))
const hex = (n) => '0x' + n.toString(16).toUpperCase().padStart(4, '0')
const fail = (why) => { throw new Error(why) }

/* ===== the punctuation and symbols ===== */

// what titles carry: ASCII and Latin-1's, the modifier letters, general punctuation, letterlike symbols, arrows,
// maths, box drawing, shapes, dingbats, more arrows and shapes, CJK's, kana's marks - and every currency sign
const VARIABLE_RANGES = [[0x20, 0x7E], [0xA0, 0xBF], [0xD7, 0xD7], [0xF7, 0xF7], [0x2B9, 0x2FF], [0x2010, 0x205E],
  [0x2100, 0x214F], [0x2190, 0x23FF], [0x2500, 0x27BF], [0x2B00, 0x2BFF], [0x2E00, 0x2E5D], [0x3000, 0x303F],
  [0x309B, 0x309F], [0x30A0, 0x30A0], [0x30FB, 0x30FE]]
// the symbols the table doesn't list, by the emoji among them: ICU weighs them all at one place in its symbols
const EMOJI = [0x1F525, 0x1F600, 0x1F3B5, 0x1F44D, 0x1F680, 0x1F914, 0x1FAE0]

/** A space and marks that ICU weighs as a symbol of its own rather than as the space it decomposes to (¨, ´, ˜). */
const spacingAccent = (cp) => /^ \p{M}+$/u.test(ch(cp).normalize('NFKD')) && base.compare(ch(cp), ' ') !== 0

function variables() {
  const currency = range([0, 0xFFFF]).filter(is(/\p{Sc}/u))
  const found = ranges([...VARIABLE_RANGES, ...currency.map((cp) => [cp, cp])])
    .filter(is(/[\p{P}\p{S}\p{Zs}\p{Lm}]/u))
    .filter((cp) => full.compare(ch(cp), '0') < 0)
    // one canonically the same as another is weighed as that one (´ for Greek's oxia)
    .filter((cp) => ch(cp).normalize('NFD') === ch(cp) && (!decomposes(cp) || spacingAccent(cp)))
  const order = sortedBy(full, found, ch)
  const ties = order.filter((cp, i) => i > 0 && base.compare(ch(order[i - 1]), ch(cp)) === 0)
  for (const cp of ties) {
    const before = order[order.indexOf(cp) - 1]
    if (accent.compare(ch(before), ch(cp)) === 0) fail(`${hex(cp)} ties with ${hex(before)} at the second level too`)
  }
  // ICU's groups: punctuation, then symbols from "`", then currency from "¤"
  const money = order.indexOf(0xA4)
  order.forEach((cp, i) => {
    if (/\p{Sc}/u.test(ch(cp)) !== (i >= money)) fail(`${hex(cp)} stands ${i >= money ? 'among the currency' : 'before it'}`)
  })
  const places = new Set(EMOJI.map((emoji) => order.find((cp) => full.compare(ch(cp), ch(emoji)) > 0)))
  if (places.size !== 1) fail(`the emoji stand at ${[...places].map(hex).join(', ')}, not at one place`)
  return { order, ties, emoji: [...places][0] }
}

/* ===== the marks ===== */

const MARK_RANGES = [[0x300, 0x36F], [0x1AB0, 0x1ACE], [0x1DC0, 0x1DFF], [0x20D0, 0x20F0], [0x3099, 0x309A], [0xFE20, 0xFE2F]]

function marks() {
  const found = ranges(MARK_RANGES).filter(is(/\p{Mn}/u)).filter((cp) => ch(cp).normalize('NFD') === ch(cp))
    .filter((cp) => base.compare('a' + ch(cp), 'a') === 0 && accent.compare('a' + ch(cp), 'a') !== 0)
  const order = sortedBy(full, found, (cp) => 'a' + ch(cp))
  const ties = order.filter((cp, i) => i > 0 && accent.compare('a' + ch(order[i - 1]), 'a' + ch(cp)) === 0)
  const weight = new Map()
  let rank = 0
  for (const cp of order) {
    if (!ties.includes(cp)) rank++
    weight.set(cp, 8 * rank)
  }
  return { order, ties, weight }
}

/* ===== the Latin letters ===== */

const LETTER_RANGES = [[0xC0, 0x24F], [0x250, 0x2AF], [0x2B0, 0x2FF], [0x1D00, 0x1DBF], [0x1E00, 0x1EFF], [0x2C60, 0x2C7F],
  [0xA720, 0xA7FF], [0xAB30, 0xAB6F]]
// Collation.swift's own: two letters each, with a mark of their own between them
const EXPANDED = [0xE6, 0x153, 0xDF]
const A_Z = range([0x61, 0x7A])

function letters(markTable) {
  const found = ranges(LETTER_RANGES).filter(is(/\p{L}/u))
    .filter((cp) => !decomposes(cp) && !EXPANDED.includes(cp) && full.compare(ch(cp), '0') > 0)
    // an uppercase letter is weighed as its lowercase one, a level down
    .filter((cp) => { const lower = ch(cp).toLowerCase(); return lower === ch(cp) || [...lower].length !== 1 })
  const places = [], ties = [], variants = []
  let letter = -1, place = 0, last = null
  for (const cp of sortedBy(full, [...found, ...A_Z], ch)) {
    if (A_Z.includes(cp)) { letter = cp - 0x61; place = 0; last = null; continue }
    const same = A_Z.find((one) => base.compare(ch(cp), ch(one)) === 0)
    if (same !== undefined) { variants.push({ text: ch(cp), cp, one: same }); continue }
    if (letter < 0) fail(`${hex(cp)} stands before "a"`)
    if (last !== null && base.compare(ch(last), ch(cp)) === 0) {
      // one differing from the one before only at the third level (ᵎ beside ᴉ) is weighed as it
      if (accent.compare(ch(last), ch(cp)) !== 0) ties.push(cp)
    } else {
      place++
    }
    if (place > 0xFF) fail(`too many letters after ${ch(0x61 + letter)}`)
    places.push([cp, (letter << 8) | place])
    last = cp
  }
  if (base.compare('l·', 'l') !== 0) fail('ICU no longer weighs "l·" as an l')
  const middleDot = { text: 'l·', one: 0x6C }
  const weights = variantWeights([...variants, middleDot], markTable)
  return { places, ties, variants: variants.map((v) => [v.cp, v.one - 0x61, weights.get(v)]), middleDot: weights.get(middleDot) }
}

/** Where each variant's own mark stands among the marks on its letter: the weight of the mark it equals, or one
 *  between the marks before and after it - several in one gap in ICU's order. */
function variantWeights(variants, { order, weight }) {
  const gaps = new Map(), weights = new Map()
  for (const variant of variants) {
    const beside = order.map((mark) => accent.compare(ch(variant.one) + ch(mark), variant.text))
    const equal = beside.indexOf(0)
    if (equal >= 0) { weights.set(variant, weight.get(order[equal])); continue }
    const gap = beside.filter((sign) => sign < 0).length
    if (beside.slice(0, gap).some((sign) => sign > 0)) fail(`${variant.text}'s mark stands nowhere among the marks`)
    const before = gap === 0 ? 0 : weight.get(order[gap - 1])
    const key = `${variant.one}:${before}`
    gaps.set(key, [...(gaps.get(key) ?? []), { variant, before }])
  }
  for (const group of gaps.values()) {
    sortedBy(full, group, (entry) => entry.variant.text).forEach(({ variant, before }, i) => {
      if (i >= 7) fail(`too many variants of ${ch(variant.one)} between two marks`)
      weights.set(variant, before + 1 + i)
    })
  }
  return weights
}

/** The marks ICU weighs as a letter, a level down (the combining letters: "t" < "ͭ" < "T"): each, then the letter. */
/** The marks ICU ignores altogether (the combining grapheme joiner). */
function ignorableMarks() {
  return ranges(MARK_RANGES).filter(is(/\p{Mn}/u)).filter((cp) => full.compare('a' + ch(cp), 'a') === 0)
}

function markLetters() {
  return ranges(MARK_RANGES).filter(is(/\p{Mn}/u)).flatMap((cp) => {
    const same = A_Z.find((one) => base.compare(ch(cp), ch(one)) === 0)
    return same === undefined ? [] : [[cp, same - 0x61]]
  })
}

/* ===== the numbers ===== */

// the circled, the parenthesised and the negative numbers, the dingbats', the Hangzhou numerals
const NUMBER_RANGES = [[0x2460, 0x24FF], [0x2776, 0x2793], [0x3021, 0x3029], [0x3038, 0x303A]]

/** The numbers ICU weighs as the digits of their value, a level down, that don't decompose to them (❽, ⓰, 〨): each,
 *  then its value, then its weight at the third level - the digits' own, or 15 and 1 more for each of the same value
 *  before it in ICU's order, all of them before a circled number's ("8" = "〨" < "❽" < "➑" < "⑧"). */
function numbers() {
  const found = ranges(NUMBER_RANGES).filter(is(/[\p{No}\p{Nl}]/u)).filter((cp) => !decomposes(cp)).flatMap((cp) => {
    const value = range([0, 100]).find((n) => base.compare(ch(cp), String(n)) === 0)
    return value === undefined ? [] : [[cp, value]]
  })
  const forms = new Map()
  for (const [cp, value] of found) forms.set(value, [...(forms.get(value) ?? []), cp])
  const third = new Map()
  for (const [value, list] of forms) {
    const circled = value >= 1 && value <= 20 ? ch(0x2460 + value - 1) : null
    // one ICU weighs as the digits themselves takes theirs (2, lowercase)
    const own = sortedBy(full, list, ch).filter((cp) => full.compare(ch(cp), String(value)) !== 0)
    for (const cp of list) third.set(cp, 2)
    own.forEach((cp, i) => {
      if (i > 4) fail(`too many numbers of ${value}`)
      if (circled && full.compare(ch(cp), circled) > 0) fail(`${hex(cp)} stands after ${circled}`)
      third.set(cp, 15 + i)
    })
  }
  return found.map(([cp, value]) => [cp, value, third.get(cp)])
}

/* ===== the other alphabets ===== */

// Greek, Cyrillic, Georgian, Armenian, Hebrew and Arabic's letters - between Latin and the scripts after them, which
// stand by code point
const SCRIPT_RANGES = [[0x370, 0x3FF], [0x400, 0x52F], [0x10A0, 0x10FF], [0x1C90, 0x1CBF], [0x2D00, 0x2D2D], [0x531, 0x58A],
  [0x5D0, 0x5F2], [0x620, 0x64A], [0x66E, 0x6D3], [0x6EE, 0x6FF], [0x750, 0x77F]]
// Collation.swift's own: Greek's final sigma, its sigma a level down
const FINAL_SIGMA = 0x3C2

/** The letters that decompose to another and a mark but that ICU weighs as letters of their own (й, Arabic's alef
 *  with a hamza): each letter's two scalars, then the letter. */
function contractions() {
  return ranges([...LETTER_RANGES, ...SCRIPT_RANGES]).filter(is(/\p{L}/u)).flatMap((cp) => {
    const parts = [...ch(cp).normalize('NFD')].map((part) => part.codePointAt(0))
    return parts.length !== 2 || base.compare(ch(cp), ch(parts[0])) === 0 ? [] : [[...parts, cp]]
  })
}

function scriptLetters() {
  const contracted = new Set(contractions().map(([, , cp]) => cp))
  const found = ranges(SCRIPT_RANGES).filter(is(/\p{L}/u))
    .filter((cp) => (!decomposes(cp) || contracted.has(cp)) && cp !== FINAL_SIGMA && full.compare(ch(cp), '0') > 0)
    .filter((cp) => { const lower = ch(cp).toLowerCase(); return lower === ch(cp) || [...lower].length !== 1 })
  const places = [], ties = []
  let rank = 0, last = null
  for (const cp of sortedBy(full, found, ch)) {
    if (last !== null && base.compare(ch(last), ch(cp)) === 0) {
      if (accent.compare(ch(last), ch(cp)) !== 0) ties.push(cp)
    } else {
      rank++
    }
    places.push([cp, rank])
    last = cp
  }
  return { places, ties }
}

/* ===== Collation.swift ===== */

function table(name, doc, values, type = '[UInt32]') {
  if (values.length <= 8) {
    return [...doc.map((line) => `    /// ${line}`), `    static let ${name}: ${type} = [${values.map(hex).join(', ')}]`]
  }
  const lines = []
  for (let i = 0; i < values.length; i += 12) lines.push('        ' + values.slice(i, i + 12).map(hex).join(', ') + ',')
  return [...doc.map((line) => `    /// ${line}`), `    static let ${name}: ${type} = [`, ...lines, '    ]']
}

function made() {
  const v = variables(), m = marks(), l = letters(m), s = scriptLetters()
  const tie = 'Those weighing as the one before them at the first level, and after it at the second.'
  return [
    `${BEGIN}: made from Node's ICU ${process.versions.icu} (Unicode ${process.versions.unicode}), never by hand`,
    ...table('variables', ['The punctuation and symbols ICU weighs before the digits, in its order: its punctuation, then',
      'from "`" its symbols, then from "¤" its currency.'], v.order),
    ...table('variableTies', [tie], v.ties, 'Set<UInt32>'),
    '    /// The symbol an emoji stands just before - and any other symbol `variables` doesn\'t list.',
    `    static let unlistedSymbolsBefore: UInt32 = ${hex(v.emoji)}`,
    '',
    ...table('marks', ['The combining marks in ICU\'s order at the second level.'], m.order),
    ...table('markTies', ['Those weighing as the one before them.'], m.ties, 'Set<UInt32>'),
    '',
    ...table('letterPlaces', ['The Latin letters beyond a-z, in ICU\'s order: each, then the letter of a-z it follows (0 for',
      '"a", shifted 8) and its place after it.'], l.places.flat()),
    ...table('letterTies', [tie], l.ties, 'Set<UInt32>'),
    '',
    ...table('variants', ['The letters ICU weighs as one of a-z with a mark of its own: each, the letter (0 for "a"),',
      'and its weight among the marks\' at the second level.'], l.variants.flat()),
    '    /// The weight a middle dot after an l takes among the marks\' (ICU weighs "l·" as an l with a mark).',
    `    static let middleDotAfterL: UInt32 = ${hex(l.middleDot)}`,
    ...table('markLetters', ['The marks ICU weighs as a letter of a-z, a level down: each, then the letter (0 for "a").'],
      markLetters().flat()),
    '',
    ...table('numbers', ['The numbers ICU weighs as the digits of their value, a level down: each, then its value,',
      'then its weight at the third level.'],
      numbers().flat()),
    '',
    ...table('scriptLetters', ['Greek, Cyrillic, Georgian, Armenian, Hebrew and Arabic\'s letters in ICU\'s order: each, then',
      'its rank.'], s.places.flat()),
    ...table('scriptTies', [tie], s.ties, 'Set<UInt32>'),
    ...table('contractions', ['The letters ICU weighs as their own though they decompose to another and a mark (й): the',
      'two, then the letter.'], contractions().flat()),
    ...table('ignorableMarks', ['The marks ICU ignores altogether.'], ignorableMarks(), 'Set<UInt32>'),
    END,
  ].join('\n')
}

function main() {
  const check = process.argv.includes('--check')
  const source = fs.readFileSync(FILE, 'utf8')
  const start = source.indexOf(BEGIN), end = source.indexOf(END)
  if (start < 0 || end < start) fail(`Collation.swift has no "${BEGIN.trim()}" ... "${END.trim()}"`)
  const was = source.slice(start, end + END.length)
  const recorded = /made from Node's ICU ([\d.]+)/.exec(was)?.[1]
  if (check && recorded !== process.versions.icu) {
    console.log(`Collation.swift's tables were made with ICU ${recorded}; this Node's is ${process.versions.icu}, so they are not compared`)
    return
  }
  const now = made()
  if (check) {
    if (now !== was) {
      console.error('Collation.swift\'s tables are not what this ICU answers: run node ios/scripts/collation-tables.cjs')
      process.exit(1)
    }
    console.log(`Collation.swift's tables are what ICU ${process.versions.icu} answers`)
    return
  }
  fs.writeFileSync(FILE, source.slice(0, start) + now + source.slice(end + END.length))
  console.log(`wrote Collation.swift's tables from ICU ${process.versions.icu}`)
}

main()
