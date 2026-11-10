# The interface: CSS, panels, phones and the design system

The main page these describe retired in 2.0.0-player.66 (see "The main page retired" in notes/app.md); the reasoning is kept as history.

The main page's layout and look, and the CSS gotchas that cost time.

Moved verbatim from CLAUDE.md (2026-10-07), where it was loaded into every session; read it when your work touches this area. Sections refer to each other by title: `grep -rn "### <title>" notes/` finds one.

### Interface details that cost time

- **`overflow-y: auto` silently promotes `overflow-x` to `auto` too.** A box cannot have
  `visible` on one axis and `auto` on the other. That is where the metadata editor's unwanted
  sideways scrollbar came from — nothing ever asked for horizontal scrolling. Declare
  `overflow-x: hidden` explicitly when you only want vertical.
- **A flex item defaults to `min-width: auto`, so `text-overflow: ellipsis` never fires.**
  The item refuses to shrink below its content, so the row grows instead and the container
  scrolls. `min-width: 0` on the flex child is the missing half of every ellipsis that
  "doesn't work".
- **`getBoundingClientRect()` returns the TRANSFORMED box; `offsetWidth`/`offsetHeight` do
  not.** The panels open with a `scale(0.98)` entrance, so measuring size with the rect during
  that animation bakes in the scaled value. Use the rect for POSITION (where it is on screen)
  and the offset properties for SIZE.
- **`style.left` on an absolutely positioned element is relative to its offsetParent, not the
  viewport.** Writing a `getBoundingClientRect().left` into it threw the log and downloads
  panels most of a screen sideways on the first resize. `resize.js` converts explicitly; fixed
  panels have no offsetParent and need no conversion.
- **A CSS `resize` grip does not track the cursor on a transformed element.** It drags in the
  element's own untransformed space, so with `translate(-50%, -50%)` the corner runs away at
  double speed. That is why resizing is done in JS now — see `interface/scripts/resize.js`.

- **An animation loop only looks smooth if its end state is pixel-identical to its start.**
  The loading sweep sets a tile width and travels exactly one tile; anything else pops on
  every cycle. Percentage `background-position` will not do this — it positions relative to
  (container − image), not to the image.
- **Capitalization: sentence case in the markup, and let CSS do any uppercasing.** Several
  labels are rendered uppercase by `text-transform`, so the source string still has to read
  correctly when that rule is not applied. Proper nouns keep their own casing, and **`slskd`
  and `deadwax` are lowercase brand names** — never sentence-case them, rephrase so they are
  not sentence-initial instead.

### Panels move as well as resize

- **Only the two DIALOGS move — the Downloads and Log dropdowns are anchored (v0.6.8, asked
  for).** They were in `DRAG_HANDLES` too, and James could drag them around "like a tab" when
  they should hang off their button. They are in `ANCHORED` in `resize.js` now: no drag
  handle, no `grab` cursor, and resizing only from the free edges — `edgeAt()` strips `n` and
  `e`, because the top is glued to the button and `right: 0` glues the right edge. A resize
  writes width/height only and never calls `freeze()`, so the CSS anchoring is never replaced
  by explicit left/top. A position saved from when they could be dragged is IGNORED by
  `applySavedSize()` rather than restored, so nobody's dropdown is stuck mid-screen from
  storage. Don't put them back in `DRAG_HANDLES`.
  - **Anchoring exposed an outside-click bug, fixed alongside.** A press inside a dropdown
    released outside it fires its click on the common ancestor — outside — so a habitual
    title-bar drag, or a text selection run off the edge, closed the panel. It never showed
    while the panels moved, because the pointer stayed on them. Both close handlers
    (Downloads' and the log's in `main.js`) now also track where the press BEGAN, and reset on
    every click so a keyboard click is judged by its target alone. On the Preact side that rule
    is `hooks/useDismiss.ts` since v0.9.23, shared with the candidate dropdowns.
  - **Verified** in the browser with real pointer drags, transitions disabled (the preview pane
    paints no frames while hidden, so the open animation sits at `scale(0.98)` and edges measure
    wrong): toolbar and title-bar drags leave both panels where they were and open; the left
    edge widened Downloads 520→620 with its right edge fixed at the button; the bottom edge
    grew both; the top-right corner does nothing; a stale saved `left`/`top` is ignored; a plain
    click outside still closes.
  - **Downloads and Log close each other, in BOTH directions.** Opening Downloads always closed
    the log (`closeOtherDropdowns`), but opening the log left Downloads open: the log's toggle
    calls `stopPropagation()`, which hides the click from the panel's outside-click listener.
    The panel now puts `closeDownloads` on the bridge and the log's toggle calls it when it
    opens. **Verified** with real clicks both ways. The page-level dropdowns (type filter,
    sort, columns, candidate signals) stop propagation the same way and so still leave
    Downloads open beside them — not asked for, left alone.
- **Moving is by a TITLE BAR, never by the whole panel.** These panels are full of lists you
  scroll, text you select and buttons you press; one that slides away when you try any of
  those is worse than one that never moved. `DRAG_HANDLES` names the bar per panel and
  `NOT_A_HANDLE` exempts the controls inside it.
- **The log gained a title bar rather than being made an exception.** It was the only floating
  panel that did not say what it was, so it wanted one anyway.
- **`.metadata-path` is exempt from the handle AND from `user-select: none`.** It is the album's
  full filesystem path and the one string in any title bar people actually copy — it is what
  you paste into a terminal when an album is misfiled. Making the bar unselectable would have
  quietly taken that away, so it keeps a text cursor and starts no drag.
- **Resize WINS over move where they overlap.** A title bar's own top and side edges sit inside
  the 6px resize zone. Resizing is the more precise gesture and the harder one to begin by
  accident, so it takes precedence and moving gets everything else.
- **Position is persisted now, and the old objection is answered by clamping, not by
  forgetting.** Position used to be deliberately discarded because a dialog pinned to absolute
  viewport coordinates can end up entirely off screen after the window shrinks, with no OS
  window list to recover it from. That held while position was only ever a side effect of
  `freeze()`; now that moving is deliberate, throwing it away every time is the worse failure.
  `clampToViewport()` keeps a 64px strip of the bar reachable. **Verified:** a position stored
  at (1300, 820) restores at (836, 536) in a 900×600 window — exactly the 64px strip on both
  axes.
- **`applySavedSize()` restores position through `freeze()`, not by writing `left`/`top`
  directly.** These panels are anchored with `right: 0`; setting `left` on top of that pins
  both edges and stretches the panel instead of moving it.
- **`thaw()` only deletes the frozen flag.** It used to wipe the inline geometry, which would
  now undo a move the instant the panel closed.
- **A gesture its panel didn't survive is dropped, not saved (v1.0.8).** Escape closes the
  Downloads panel (and the candidates dialog) in the middle of a drag, and `onPointerUp` then
  saved what a hidden panel measures: 0 x 0, so the panel opened at its 280 x 160 minimum for
  ever after - found in the preview pane's storage, reproduced with real input in headless Brave
  (press on the left edge, drag, Escape, release). A move abandoned the same way saved an
  off-screen spot (-550, 0). `endGesture()` saves only while `isShown()`, `saveSize` refuses a
  non-positive size, the observer ends a drag whose panel it sees hidden, and `applySavedSize`
  ignores a saved size of 0 or below the panel's CSS minimum, so a stored 0 x 0 recovers by itself.
- **"Hidden" is `isShown()`, never `offsetParent` (v1.0.8).** offsetParent is null for anything
  `position: fixed` - both dialogs - whether showing or not, so the observer took them for hidden
  every time and never ran `applySavedSize` on them: the candidates dialog opened at its default
  (70, 90) with a position saved, contradicting the note above. The dialogs also hide by
  `visibility: hidden` (kept laid out to fade), which has boxes, so `isShown()` checks visibility
  as well as boxes. **Verified in headless Brave**: a saved (1300, 820) now restores at exactly
  (836, 536) in 900 x 600, the 64px clamp above. **Not verified**: the metadata editor, which
  mounts only when opened and has no library in the scratch setup.
- **A press outside a panel's box is on no edge of it (v1.0.9).** James: comparing covers in the
  metadata editor, "the x highlights but doesn't do anything", while Close worked. The cover
  viewer was drawn INSIDE `#metadata-window`, so `panelFor()` called a press on it a press on
  the editor, and `edgeAt()` never asked whether the pointer was inside the box: "above the top"
  passed as the top edge. Once the editor had been moved (no centring transform, so the fixed
  viewer covered the screen) its ✕ sat above the editor; the press began a resize, the editor
  took pointer capture, and the click landed on `#metadata-window`. Close, below the editor,
  failed the bottom test's `>= scrollbar` half and escaped. Two fixes: `edgeAt` returns '' for
  a pointer outside the box, and the viewer renders BESIDE the editor's window (a fragment),
  which also makes it full screen when the editor is centred - inside the transform it had been
  the editor's 900 x 680. **A script's click can't show this**: a synthetic pointer can't be
  captured, so the click went through in every scripted test, in Arc too. **Verified with real
  input in headless Brave**: before, the moved editor's ✕ logged pointerdown on the button and
  then capture, pointerup and click on the editor; after, the ✕ closes the viewer centred or
  moved, the viewer is 1440 x 900, Escape, the scrim and Close each close only the viewer, and
  the editor still resizes from its top and left edges (60 and 50px) while a press just above
  it does nothing.

### The mobile layout

Rebuilt in v0.5.3. It fitted on a phone since v0.3.x, which is not the same as being usable
on one — the whole thing was the desktop layout with `flex-wrap` turned on.

- **The header is one row, and that is where most of the win came from.** It wrapped to four
  — wordmark, connection pills, actions — for **161px of every screen** on a 375px phone,
  before the tab bar. It is ~47px now. Three changes did it, and each is worth keeping:
  the wordmark is set as TEXT on mobile rather than drawn as 350px of ASCII art (`#brand
  -compact`, which is also the accessible name at every size — figlet art read aloud is
  gibberish, so the `<pre>` is `aria-hidden`); **the connection pills only render when
  something is WRONG**; and the actions no longer claim a row.
- **A status that says "everything is fine" is not worth 71px of a phone.** The `ok` pills
  are hidden on mobile and the raw error code goes too — truncated to `UNKNOWN_…` it tells
  you nothing the red dot and the service name have not, and the log is one tap away with an
  unread badge on it. Which connection is down is the part that fits and the part that
  matters.
- **The search form was 450px, on top of that 161px header.** Between them they filled the
  viewport, so a result was never visible without scrolling past everything you had just
  typed. Type, Limit and Search share one row now; the two text fields keep full width
  because they hold the longest values. ~146px.
- **The release-group card header is a GRID on mobile, not a wrapping flex row.** As flex,
  the title wants 100% of `.shrinkable`, which makes it claim the whole row and pushes the
  match chip and Find onto a line of their own — ~55px per card for two small controls.
  Flex-basis percentages can force it back but only by guessing a ratio that breaks with a
  longer label. `grid-template-columns: minmax(0, 1fr) auto` states it directly. Cards went
  from ~280px to ~99px, which is five on screen instead of one and a half.
- **The title is `order: -1`** because the markup lists artist before album, and the album is
  the only part you read while scanning. Two lines then clip — a live bootleg's title is a
  date and a venue and will otherwise take four.
- **Measured, at 375px:** header 161→47px, search form 450→146px, result cards 280→99px,
  first result 770→343px from the top. No horizontal overflow anywhere, no control off-screen
  in any view, and desktop is untouched (checked at 1280px after the cascade move above).

### The phone pass (v0.9.31)

James: "mobile needs to be 1000% optimized and working well. no weird overflows or cutoffs,
everything should work exceptionally well". Every view and state was driven at 320, 375 and
390px, at 844x390 (a phone on its side) and at 800 and 1024px tablets, with an audit script run in
each. It flags anything past the screen edge that isn't inside a sideways scroller, text clipped
without an ellipsis, fixed panels running off screen, and tap targets under 32px. Everything it
found was fixed, and it now reports nothing anywhere, apart from 20px checkboxes whose labels are
the real targets. All the CSS is in one commented section at the end of the 768px block, "the
phone pass". What it changed, and why:

- **Every text field is 16px on a phone (`!important`).** Anything smaller makes iOS Safari zoom
  the whole page when you tap into it, and it doesn't zoom back. Every input in the app was
  12-14px.
- **`100dvh`, not `100vh`, for the app's height**, with `100vh` first as a fallback. iOS Safari's
  `100vh` is its height with the toolbar hidden, so the bottom of the page (the library's status
  bar) sat under the toolbar while it showed.
- **Search scrolls as ONE column on a phone** (`#middle-content` is the scroller; the results
  section and its box grow instead). Before, the results scrolled in a box under the form, the
  header and the tab bar, and those never moved: 40% of the screen on a form already used.
  **A screen under 520px tall gets the same** (`@media (max-height: 520px)`), because a phone on
  its side is wider than the breakpoint and so gets the desktop layout at 390px tall.
- **A release in the grid is a BLOCK on a phone, not a row of a 1,700px table.** `main.js` gives
  each cell a `data-label` and an `is-na` class (values MusicBrainz doesn't have); the phone CSS
  lays the row out as ▷, title and Find; then the edition and tracklist chips; then each other
  visible column as a small labelled value; with "N/A" left out and the header hidden. The values
  are `<h4>`s and go inline so a label shares their line - but NOT the Find cell's, which is a
  button that `min-height` must still reach.
- **The card's cover tucks into its header corner** (52px, `:has()` gives the header room only
  when a cover is there), so an expanded card's pressings use the full width. Its height now
  comes from a `--card-height` property that `loadAllCoverImages` sets, rather than inline, so
  the phone rule can square it. The " - " between artist and title, and the spaces around the
  type, are `.releaseGrpSep` spans a phone hides; " match" after the score is too. An undated
  group no longer shows "(N/A)" as its year, anywhere.
- **The results summary counts albums as well as pressings**, with plurals: "2 albums · 20
  releases listed". It said "1 releases" beside fifty cards, because it only ever counted the
  pressings in expanded grids.
- **Candidates**: a full-height sheet; each row a grid with the score, the folder and Download
  on the first line and every detail line spanning under it (`.candidate-body` is
  `display: contents` for this); details wrap BETWEEN items, never inside one ("busy-" / "peer"
  was the old way). The desktop panels' `min-width` floors (280-340px) are dropped on a phone:
  at 320px the metadata editor hung 10px off both sides.
- **Saved panel sizes aren't applied at phone width** (resize.js `PHONE`), and a window
  narrowed into it drops the inline geometry. A size saved at a desk is an inline style, beats
  every phone rule, and there's no way to resize it back on a phone.
- **The track list is a music app's on a phone**: tick, number, title, length, 44px rows, no
  sideways scroll. Body cells now carry `data-column` so CSS can pick them; the header can't be
  dragged or resized and the Fields button is hidden (the fields are a desktop table's). Its
  minimum width moved from inline `min-width` to a `--track-min-width` property for the same
  reason as the cover height; the resize drag writes the property too (checked with a real drag
  at 1440px). The editions table shows edition, year and tracks, with any issue on its own line.
- **Tree rows have a shrink order**: the issue chip and the edition count give way, ellipsized,
  before the album's name does - "Dummy" was drawn as "D." on a 375px phone. The weights are in
  the thousands, not a fraction on the name: when the chips reach their minimum the name is the
  only item left to shrink, and flex takes back space in proportion to the weights' SUM when
  that is under 1, so a 0.001 on the name left rows running off the screen.
- **Pinch to zoom a cover** (ArtViewer): the image takes `touch-action: none` for its drag, so
  the browser's own pinch never happened there. Each finger's listeners answer only their own
  pointer (every finger's hear every finger's events, and lifting one ended the other's gesture),
  the finger left after a pinch pans on without a jump, and a still finger lifted after a pinch
  isn't a tap. The hint says "tap … pinch" on a touchscreen (`hover: none`).
- **Also fixed at every size**, found by the same sweep:
  - The search row pushed Search 95px off the edge between 769 and about 940px; the fields
    now shrink, down to 7em.
  - The library toolbar pushed Rescan off at 800px; it wraps now.
  - The tag editor's Disc box grew to match the Track field beside it.
  - The editor's release rows could lose their title to a long detail line.
  - The artist page's links were the browser's default blue.
  - The facet checkboxes sat 4px from the edge at 420px, because side padding was dropped
    under a -8px margin.
  - The sort menu started 2px off the screen.
- **Verified in the real page** at every size above, with screenshots and the audit. On desktop,
  checked unchanged: 184px search fields, the release table with its header, the separators, 10
  track columns, and the Fields button.

### The v0.5 design system

The brief was "snappy, and modernise the dated aesthetic". The direction chosen was **modern
foundation, keep the signature**: the ASCII wordmark, the purple accent and monospace data
stay; the CRT overlay, the text-glow and the ░▒▓ chrome go.

- **`theme.css` is the token layer and the only place raw values belong.** Colours, type
  sizes, spacing, radii, shadows, durations and easings are all defined there once. This is
  load-bearing *because the migration is unfinished*: `main.css` styles the vanilla half and
  the Preact half, so one token edit restyles both together and the two can't drift apart
  while they coexist. A hex code or a px size typed into a rule defeats that.
- **The type scale is REM, and that is the whole point.** The old sheet was ~15 unrelated
  `em` sizes, which COMPOUND through nesting — the same `<h4>` rendered at different sizes
  depending on where it sat, and each value had been hand-picked to look right after
  whatever compounding applied at that spot. That is also why it could never be fixed by
  setting a base size on `body`: the headings scaled with it. rem resolves against the root,
  so a step means one thing everywhere and the interface can be rescaled from one line.
- **The glow tokens still exist and resolve to `transparent`.** ~23 `text-shadow` rules
  reference them. Neutralising the tokens switched every one of those off without editing
  them, which makes the CRT bloom one edit to restore and one edit to remove. That is why
  they weren't deleted — resist tidying them away.
- **The bundled scene font is unreferenced, not deleted.** All 30 `@font-face` rules went and
  the UI uses the platform's own stacks; the `.otf` files are still on disk and in git. This
  app is self-hosted and often runs with no internet at all, so a webfont CDN was never an
  option — local stacks are the only honest choice, and they cost nothing to load.
  **Superseded in v0.6.7: the files are DELETED, on James's instruction.** Their name table read
  "TX-02" and "Berkeley Mono ... Copyright 2022-2024, U.S. Graphics LLC. All Rights Reserved",
  and the `SCT.nfo` beside them was a scene release note - a commercial font with no licence to
  redistribute, sitting in a public repo. **They are still in git history** before v0.6.7;
  scrubbing that means rewriting and force-pushing the branch, which has NOT been done and
  should not be done without asking. Don't bring any of it back. The interface face is now a
  bundled, openly licensed Noto Sans - see the entry on it below.
- **The wordmark is figlet-style ASCII art and therefore needs `--font-mono`.** It used to
  inherit a *proportional* face, which is why the letterforms never quite lined up.
- **The foundation layer at the top of `main.css` is written with `:where()`, so it carries
  ZERO specificity.** The ~3,500 legacy lines below beat it on any property they actually
  set, and it only fills in what they never mention. That is what made it safe to add a
  baseline to a stylesheet whose own header calls it an abomination: it cannot take anything
  away. Keep new baseline rules inside `:where()`.
- **Overlays animate via `@starting-style` + `transition-behavior: allow-discrete`.** Every
  dropdown here is toggled by swapping `display`, which is a discrete property — the panel
  simply existed on one frame and not the one before, and that hard cut was most of why the
  app read as abrupt despite never being slow. Browsers without support ignore both and get
  the instant show/hide it always had, so there is no fallback to write.
- **`prefers-reduced-motion` is handled once, in `theme.css`, by collapsing the duration
  tokens** rather than by redefining animations. One block therefore covers every transition
  in both halves — including ones written after it.
- **v0.6.5 took a step back from "modern", on request: "a touch more of a Windows 7 feel".**
  A TOUCH - the dark palette, the purple accent and the monospace data stay. What came back is
  Aero's shapes: radii pulled in to 2/3/4/6px, glossy two-tone fills with a hard midline,
  a 1px top highlight on anything raised, gradient toolbars/captions/status bar, and
  Explorer's selection (translucent gradient in a thin border; grey when the list isn't
  focused). All of it is section 9 of theme.css plus ONE block in main.css ("A TOUCH OF
  WINDOWS 7", just above the responsive blocks) - so it can be dialled back from the tokens,
  the same arrangement as the glow tokens. A full light-and-blue Aero palette would be a
  different theme, not a touch; don't drift there without being asked.
- **The interface face is Noto Sans, bundled (v0.6.7).** Picked by James from six candidates
  set side by side (system UI, Segoe UI, Tahoma, Verdana, IBM Plex, JetBrains Mono). It is
  SELF-HOSTED woff2 in `interface/styles/font/noto-sans/`, served by the app itself, which is
  what squares it with the no-CDN rule: it works with no internet, like everything else here.
  One variable-weight file (300-700) per script, split by `unicode-range` exactly as Google
  Fonts splits it, so a browser fetches only the Latin file (~the only one most pages need)
  unless a name on screen is Cyrillic, Greek or Vietnamese. Devanagari was deliberately left
  out. Noto Sans is used on EVERY device - not "Segoe UI first", which was the option's label -
  because what James saw and liked was Noto (his Mac has no Segoe), and Segoe-first would make
  Windows look different from the choice. The mono data face is unchanged. `OFL.txt` ships
  beside the files, as the licence requires. The "0 font bytes on load" figure in the
  performance table below is therefore now one 35 KB Latin file, cached; all seven together
  are 342 KB, of which Latin Extended (164 KB) is the one a European name will pull in.
  (Since 2.0.9 the data face is Noto Sans Mono, the large titles Noto Sans SemiCondensed and the
  Latin Extended file trimmed to 68 KB - see "Fonts and type (2.0.9)" below.)
- **Checkboxes, not switches (v0.6.6), for every checkbox in the app.** The settings tab's
  sliding switches were the one phone idiom left; they are plain checkboxes now, drawn by one
  `input[type="checkbox"]` rule in the Windows 7 block (a sunken square, a gloss on hover, a
  drawn tick) so the vanilla candidate filters and the editor's boxes match them. In a settings
  row the box sits BEFORE its label (`.settings-row:has(.settings-check)`), where a desktop
  checkbox lives. Radios got the same well, round with a dot, so the settings tab's format
  choice matches. The old `accent-color` rules on individual inputs are inert now. The
  `#format-preference-select` rules (and the rest of that dead profile-popover block) were
  deleted in v0.9.18.
- **Accent is spent, not sprinkled.** Solid purple fills appear on exactly three controls:
  Search, the metadata editor's Apply, and the tag editor's Apply (v0.6.9). Both Applies write
  tags to disk with no undo, so they must not look like the Cancel button beside them.
  Everything purple used to be purple — three accent-coloured boxes sat in the top bar — and
  when everything is accented the accent marks nothing.

### Interface and CSS

- **`theme.css` is `@import`ed from `main.css`, so it caches independently.** Editing the
  palette and reloading shows the OLD colours. Bust it explicitly when verifying, and
  hard-refresh after deploying.
- ~~Text colour classes are element-scoped~~ **Fixed at the root.** Colour was an element ×
  colour matrix (`h4.default`, `h5.white`, `span.white-secondary`…), so every unforeseen
  pairing inherited instead — `<div class="text white-secondary">` had no rule and rendered
  black on black. There are now element-agnostic `.white`, `.default-secondary` etc. at lower
  specificity than the legacy rules, so old pairings are untouched and new ones just work.
  **`body` also sets `font-family` and `color`**, so a missed element now degrades to looking
  ordinary rather than disappearing. Prefer the generic classes for new markup.
- **Nothing had set a font on `body`**, so any element without its own rule fell back to
  Times at 16px. That is how the releases-grid `▷` arrows and `#results-summary` shipped in
  a serif face. Fixed by the `body` baseline above.
- **A Preact `useEffect` that writes to a DOM node outside its own tree is unreliable.** The
  tab bar set `data-tab` on `#main-container` from an effect; when the tab was changed by a
  click originating in the *library* tree, the effect didn't fire and the button highlighted
  while the panes never swapped. Cross-tree DOM writes belong in the shell (`main.tsx`),
  done synchronously. Symptom to recognise: the component looks right, the page doesn't.
- **The layout had no media queries at all until v0.3.x.** On a 375px phone it produced
  1131px of content — 756px unreachable off the right edge, with the entire top-bar actions
  row off-screen. Three causes: `#top-bar` was a nowrap flex row of `flex-shrink: 0`
  children, `#main-content` put a fixed 220px filter column beside the content leaving 155px,
  and the dropdown panels were 440–460px wide. **Anything new with a fixed px width needs a
  mobile rule**, and the responsive block at the bottom of `main.css` is where it goes.
- **THE RESPONSIVE BLOCKS MUST BE THE LAST THING IN `main.css`, and they had stopped being.**
  About 460 lines of unmediated rules were appended after them across several changes, and
  any of those with equal specificity beats the mobile rule *at mobile widths*. The failure
  is horrible to spot because it is completely silent: the mobile rule is present, it reads
  correctly, and it simply never applies. It cost real time in v0.5.3 — one-field-per-row in
  the metadata editor was written, confirmed present in the sheet, and did nothing, because
  `.metadata-fields > .metadata-field { flex: 1 1 45% }` sat a hundred lines below it. Both
  blocks now live at the end under a comment saying so. **New rules go above that comment.**
  The 420px block also has to stay after the 768px one, since a 375px screen matches both.
- **Right-align the library toolbar from the SUMMARY, not from each button.** Every trailing
  control used to carry its own `margin-left: auto` plus a rule cancelling the one before it,
  so adding a third button meant adding another override — and two live auto margins split the
  free space instead of pooling it, putting a gap in the middle of the group. `#library-summary`
  takes the slack with `margin-right: auto` and any number of controls after it stay together.
- **The filter column and the library's views collapse on mobile, and the class is inert on
  desktop.** The vanilla `#filter-column` and the library's `#library-views` both carry
  `collapsed`; only the `max-width: 768px` block acts on it. Don't "tidy" that by removing the
  class on desktop — it's what keeps one code path.
- ~~The loading indicator animates `content`~~ **Replaced in v0.5.** It swapped ░▒▓█ on
  `steps(1)`, justified as using "the same glyphs the filter headings use". Those headings
  are plain words now, so that justification expired with them — and animating `content`
  replaces a text node twelve times a second, each swap a layout and a paint. It is a
  gradient sweep over a 2px bar instead. Still deliberately not a rotating arc: a horizontal
  sweep suits an interface built out of rows and tables.
- ~~Decorated headings wrap if you let them~~ **Moot in v0.5 — the ░▒▓ chrome is gone.**
  Worth knowing why it was ever a rule: `░ ▒ ▓ filters ▓ ▒ ░` measured 138px in a 190px
  header that also holds a "clear" button, so a lone `░` wrapped to a second line and the
  column read as broken. The general lesson survives the decoration: **anything in a
  fixed-width column needs measuring at that width**, not eyeballing.
- **Removing a UI element leaves references behind, and a module-scope `ReferenceError`
  aborts the REST of the handler.** The download-profile dropdown went in v0.5 but two
  `profileControl.classList.remove('open')` calls stayed, referencing a binding that no
  longer existed anywhere. The damaging one was in `closeOtherDropdowns()` — the bridge
  function the Preact downloads panel calls as it opens — where it threw on the *first* line,
  so the `setLogOpen(false)` beneath it never ran and **opening downloads left the log open**,
  defeating the one invariant that function exists to hold. The other, in the log toggle, threw
  *after* `setLogOpen()` and so did nothing visible at all, which is why both survived several
  releases. Found in the console while verifying something unrelated. **After deleting an
  element, grep for its variable — and note that a dead reference positioned late in a handler
  is invisible, while the same reference one line earlier is a broken feature.**

- **`hidden` did nothing to any badge.** `.log-unread-badge` and `.signals-badge` both set
  `display`, which beats the browser's `[hidden] { display: none }` — so all three badges sat
  on screen showing `0` while their JS believed it had hidden them. Found by checking
  `getBoundingClientRect()` after `el.hidden` read back `true`; it is invisible to any check
  that trusts the property. `main.css` now forces `[hidden]` to win. **`hidden` reading
  `true` is not evidence an element is hidden — measure it.**
- **The downloads panel vanishes if `ui/` hasn't been built.** `interface/index.html` loads
  `dist/deadwax-ui.js`, which is gitignored and generated. Running from source without
  `npm run build` leaves it 404ing and that panel simply absent. Check this first. **And
  `/player/` is a blank black page**, with no error on screen: it loads `dist/deadwax-player.js`,
  the second entry. A build that emits only the first (an old local rolldown config) does it too.
- **Don't derive an overlay's subject from a list that a write reloads.** The metadata editor
  originally resolved its album by looking `review.paths[index]` up in `albums` on every
  render. Applying a release renames the folder, so the reloaded library and the queue's record
  of where the album now lives land in *two separate state commits* — and for the render
  between them **neither the old path nor the new one resolves**, so the editor unmounted
  mid-queue every time a rename was applied. It now holds the album itself and is updated once,
  explicitly, from the array `reload()` resolves with (never from `albums`, which the caller's
  own `await` has not necessarily committed yet). One value updated once cannot disagree with
  itself.
- **The editor is keyed on a step counter, and that is load-bearing in both directions.** It
  must NOT reset when its album prop changes — that happens after an apply, where the release
  list on screen is still right and re-searching MusicBrainz would be waste. It MUST reset when
  the queue moves to a different album, since nothing about the previous one applies. A `key`
  that changes only on navigation is what buys both; keying on `album.path` or `album.key`
  would break the first, because an apply changes them.
- ~~New chips in the album rows do not shrink~~ **The rows are gone (v0.6.5), the lesson isn't.**
  Adding issue chips to the old nowrap album rows pushed the edit and delete buttons off a 375px
  screen and took "Selected Ambient Works 85-92" from 84px to **9px**, because chips carry
  `flex-shrink: 0` and titles don't. The tree rows drop their chips by `@container` query as
  the tree narrows, for exactly that reason. **Anything added to a tree row needs measuring at
  the tree's narrowest width (260px)**, not eyeballing.
- **An id containing NUL can never be found by `querySelector`.** Album group keys are built
  with a `\u0000` separator (the source writes that escape, so the file stays plain text; the
  string itself still holds one real NUL), and
  `CSS.escape()` turns NUL into U+FFFD, as the spec requires. So `[data-node="${CSS.escape(id)}"]`
  silently matched nothing for every album and track: arrow keys moved the selection while
  focus stayed on the row you left, and only artist rows (no NUL) worked. The tree now compares
  `dataset.node` directly. The same misreading built a group id by hand with a space, which
  resolved to nothing - **never rebuild a node id by hand; go through `lib/libraryTree.ts`.**
- **A grid resolves `em` track sizes against ITS OWN font-size, so two grids meant to line up
  have to share one (v0.6.13).** The track viewer draws its header and every row as separate
  grids from one `--track-columns` template, and the header was a type step smaller with
  `--text-2xs` set on the CONTAINER. Every em column then came out about 9% narrower up there -
  `2.6em` was 28.6px in the header against 31.2px in a row - so the two grids' boundaries drifted
  further apart the further right you looked, and a value sat up to 10px right of its own label.
  James reported it as "a weird space before the text in the columns", which is exactly what it
  looks like. The smaller label type belongs on the header's CELLS; both grid containers stay on
  the table's own size. A px track is immune, which is why a column already dragged to a width
  was the one thing that lined up, and why this hid for so long.
  **It also quietly bent the resize**, which measures HEADER cells to pin the flexible columns to
  the left of the grip: while the two disagreed, it pinned a body column to a width 9% short of
  the one it was actually drawn at. Nothing about the drag changed to fix that - the grids
  agreeing is what fixed it.
  The rows also carry a 1px transparent border for their hover and selection outline, so the
  header carries a matching transparent one on each side; without it everything sits one pixel
  out. **Verified:** both grids resolve identical tracks, and every column's value now starts at
  exactly the same x as its header label, before and after a resize drag.
- **Current Chrome ignores every `::-webkit-scrollbar` rule on an element that sets
  `scrollbar-width` or `scrollbar-color`.** `.scrollable` set both, so the Windows 7 scrollbars
  applied in Safari only. The Windows 7 block resets both to `auto` first; if the scrollbars
  ever look flat again in Chrome, look for one of those two properties having crept back.

### Fonts and type (2.0.9)

James asked for "a font review as well" beside the review of the app's words (2026-10-23). The review is
`deadwax-scratch/work/ux-audit/fonts.md` (today's faces, a census of every drawn size, the contrast table, a
proposed scale, ranked fixes, candidate files); he chose its recommended set **plus Noto Sans SemiCondensed for
the large titles**, and no Text size setting. What was built, fix by fix:

- **Three faces, all Noto, all self-hosted** (theme.css section 1). Noto Sans for words, as since v0.6.7.
  **Noto Sans Mono** (`styles/font/noto-sans-mono/`, seven files, one per script as Noto Sans's, OFL beside them)
  first in `--font-mono`: until now the data face was the system's (SF Mono on an iPhone, Liberation
  Mono on Linux), so nobody had chosen it; it is the face James liked on the roadmap page and has exactly Noto
  Sans's vertical metrics. **Noto Sans SemiCondensed** (`styles/font/noto-sans-semicondensed/`, seven files, one
  per script, OFL beside them) for the large titles. The mono's Latin file is Google's (31 KB); its other six are
  Noto Sans Mono 2.014's variable font (notofonts' release, `NotoSansMono/unhinted/variable`) with the width pinned
  at 100 and the weight axis whole, as Google's, subset to Noto Sans's own ranges. The first build bundled the
  Latin file alone, and the review after it found a folder named Czesław drawn in two monospace designs (the ł
  from the system's, a different weight and shape) and a Cyrillic path's letters in the system's monospace between
  Noto Sans Mono's slashes and digits: a path, a folder or an artist's folder in any of Noto's scripts is one face now.
- **SemiCondensed is a family of its own, not Noto Sans at `font-stretch: 87.5%`** - the review's option C
  proposed the latter, serving the Latin file with its width axis. Chrome (FontFaceCache keys its segmented faces
  by their descriptors) and Safari both group a family's faces by identical descriptors and take ONE group for a
  run of text, so a width-variable Latin face beside fixed-width faces for the other scripts would have left
  Greek, Cyrillic and Vietnamese to the system face - and a Polish title would have mixed widths (its ł and ś at
  100%). Each SemiCondensed file is the width axis pinned at 87.5 (fontTools' instancer): the Latin one from
  Google's width-and-weight Latin file (the review's candidate), the other six subset from Noto Sans 2.015's
  variable font (notofonts/latin-greek-cyrillic's release, `NotoSans/unhinted/variable-ttf`) with Google's
  unicode-ranges. Every face of each Noto family has the same descriptors (weight 300 700); tests/test_type.py
  holds that, and that SemiCondensed covers every range Noto Sans does.
- **The large titles**: `.pl-large-title`, `.pl-hero-title`, `.pl-sheet-title`, `.app-artist-name`, You's
  `.app-identity-name`, the sign-in's `.app-signin-title` and the desktop's `.app-side-brand`, through
  `--dw-font-title` (player.css's `--pl-font-display`). Not section headings, panel titles or rows.
  `text-wrap: balance` on the ones that wrap (and Info's names); the sheet's song is one line with an ellipsis.
  An album's title over 60 letters (code points - `lib/titles.ts`, `heroTitleClass()`, used by the album page,
  the album you don't have and a playlist's page) takes `.is-long`, `--dw-text-title-long`: 20px on a phone, 24
  on a desktop. Fiona Apple's 23-word title: 5 lines before, 4 balanced lines at 20px after (phone); 2 on a desktop.
- **Pinned line heights**: `--dw-leading-row` (1.36, Noto's own `normal` - its 1069 + 293 thousandths) on
  `body`, so no text takes a face's `normal`. player.css's five raw line heights are tokens (`--pl-leading-*`,
  aliasing section 10's at the SAME values - 1.2, 1.25, 1.35 - so nothing moved).
- **A track's number and length on its title's line.** They were 15px mono beside a 17px title, each centred in
  the row's grid: measured in headless Chromium, the number's and the length's baselines sat 3px above the
  title's on a phone, 2.5 on a desktop, and with an artist's line under the title 6px BELOW it (centred on the
  two lines). `.pl-track` now aligns its items by their first baselines (`align-items: baseline` - the text
  column's first baseline is its title's) and centres that one line of them in the row (`align-content: center`):
  0px on both frames, with or without an artist's line, the line of them within a pixel of the row's middle.
  The numbers read `--dw-text-data` (15px on a phone, as they were through `--pl-text-subhead`). The review's
  "a quick align-self made it worse" was the number and the length baseline-aligned while the text column stayed
  centred. **A playlist's row** (every one has an artist's line) is aligned the same way, and only its cover is
  centred (`.app-playlist-track-art { align-self: center }` - a baseline would sit the cover on the line): the
  first build kept the whole row centred, which drew the length 8.2px below the title's line on a phone and 7.5
  on a desktop (6.0 and 6.5 in 2.0.8). Measured after: 0px on both; the title and artist block is centred on the
  cover on a phone, and 1.6px above the cover's middle on a desktop, where its two lines (14 and 13px) are shorter
  than the 40px cover and a baseline group starts at the top of the row's line. The playing bars in the number's
  place stand on the line.
- **One type scale per frame, in theme.css.** The phone's is unchanged but for `--dw-text-data` (14 to 15, the
  track numbers' size, so the `.app-mono` spans that take it grow a pixel) and two new tokens: `--dw-text-field`
  (17px, every text field and picker, NEVER redefined - iOS zooms into a field under 16px, and an iPad on its
  side is a desktop) and `--dw-text-title-long`. The desktop's: body 14px (was 17 - so a search result, You's
  choices, a menu item now match the track rows instead of being 3px bigger), meta 13, data 13 (was 12: track
  times, the player bar's clocks, which were a local 11px), labels 12 (was 11: the sidebar's group labels, Info's
  labels - the hardest text to read), brand 20. app-desktop.css's own sizes are folded in and gone:
  `--app-desk-text` (= body), `-text-sm` and `-field-text` (= footnote), `-chip-text` (= label), `-clock`
  (= data), `-speed-text` (= body), `-brand` (= `--dw-text-brand`), and the visualizer's `--app-viz-title`
  (17, now the artist-hero 18), `-artist`, `-album`, `-text`, `-small` (11, now 12), `-hint`; its three lines'
  19px leading is `--dw-leading-tight` (the cover's 56px tall in all). Every field rule moved from
  `--dw-text-body` to `--dw-text-field` (app.css, signin.css, the bench's, and the desktop's coarse-pointer
  block). `--app-pin-title-size` (Home's pinned cards, 14px on both frames) was left as it is. Three things a
  size token moved that are not a list's rows: **the sign-in card's button** reads `--app-signin-button-text`
  (`--dw-text-field`, 17px on every frame - the card is the phone's, centred, on a desktop too, and its button had
  dropped to the desktop's 14px body under its own 17px fields); **a source card's Get** reads `--dw-text-heading`,
  Search's Get's size, not the data size (it was 14px through `--dw-text-data`, and grew with it to 15: it is 15px
  on a phone now, as Search's Get, and 13 on a desktop); and **the turntable's bench** (`/player/lab/`), which links
  theme.css and has no desktop frame, takes the desktop scale in a window 1024px or wider as the app does - its body
  and buttons 14px there (17 before), its labels 12 (11), its headings and title 13 and 28 as before, its fields
  17. test_type.py pins that every rule sized by the data token is in the data face or one of five desktop rules
  it names.
- **The data face only for data** - numbers, times, ids, paths, the turntable's readouts - never a sentence or a
  count: off the Requests tab's badge, an Arriving card's brief ("6 of 10", "2nd in line", "starting" - the
  Downloading line's "files · MB/s" keeps it), the Library's count ("69 albums", now 13px text), You's and the
  sidebar's Needs a look badges, Needs a look's chip counts, and a source card's Tracks ("10 of 12") and Starts
  ("after 3 others"); Quality, Size and the score keep it. Debug's values that read as phrases are in the text
  face too - Format, Sent as, Resampled, Normalization, the turntable's Ready and Clock step (2.0.7 had already
  moved its notes); only Navidrome's field names keep `mono` (debug.sim pins that `mono: true` is in those two
  rows alone).
- **`--dw-text-3` #7d7d92 to #8e8ea3**: 3.6:1 on a popover and 3.9 on a card before, where the Edit panel, the
  inspector and the log draw it at 12-13px; now at least 4.52 (the popover) on every surface, both frames, and
  still the quietest grey. Dark only, so one value.
- **Token hygiene**: player.css's `--pl-text-title-2` (the 20px artist line, beside section 10's 28px
  `--dw-text-title-2`) is `--pl-text-artist-hero`; its type is tokens only (test_type.py). The six leading tokens
  were kept (the review's four would have moved lines); `tabular-nums` on the mono rules was left - harmless.
- **`dir="auto"`** straight after the class of every title, artist and byline (hero, track rows, Now Playing,
  the mini player, the player bar, the visualizer, tiles, Info's names and lines, the artist's name, result rows,
  pinned cards and their lines, Requests' titles and lines, an Arriving card's artist, the album you don't have's
  tracks, the sources' "for ..." with the album isolated in a `<bdi>`, Held by nobody's rows, the sidebar's
  playlists, a band's members, Which artist is this?'s names, the playlist picker's): an Arabic album's title is
  right to left, its own words' direction. The first build had missed the album you don't have's tracklist and the
  lines under a title; test_type.py's list of 32 classes is checked against every element that draws one. The
  main page's editors, which the Edit panel hosts as they are (MetadataEditor, TrackTagEditor, the delete dialog),
  name their album and artist with generic classes and are left as they were.
  **Its direction, not its side**: dir="auto" also makes `start` the right edge for an RTL line, so wherever a name's
  alignment was inherited `start` it moved: the recheck measured an Arabic artist's name flush right over a page
  whose Play, albums and facts start at the left (x 1344-1408 of 264-1408 on a desktop, 292-370 of 20-370 on a
  phone), and Now Playing's song flush right over its left-aligned byline. player.css's
  `:where([dir="auto"]:not(button)) { text-align: -webkit-match-parent; text-align: match-parent }` gives every such
  line the alignment its parent has in the page's own direction (left, or a centred parent's centre), at zero
  specificity so a rule of its own still wins; buttons keep the browser's centring. Chromium 154 reads only the
  prefixed spelling (it drops the plain one), Firefox only the plain one. Measured after, in Chromium at 390 and
  1440: both lines start at the left edge, and every other dir="auto" line on Home, the album, Now Playing, the
  artist and the Library computes the same alignment as before. Not measured: the screens the test library has no
  Arabic name on (the visualizer, Requests, the album you don't have, the sources, Held by nobody, a band's
  members, the picker) - the rule covers them the same way - and Safari, whose WebKit has the prefixed value
  (its own stylesheet uses it for list items). test_type.py pins the rule and that no app rule sets
  `start`/`end`, or a non-physical alignment on a name's class.
- **Latin Extended trimmed**: Google's latin-ext (164 KB) carried IPA, phonetic and Latin Extended-C/D letters no
  name needs. `noto-sans-latin-ext-europe.woff2` (68 KB, a NEW name - fonts are served immutable for a year) keeps
  Latin Extended-A and -B, the African reference letters (ɓ ɔ ɖ ɗ ə ɛ ɣ ɨ ɩ ɲ ʉ ʋ ʒ - the review's 66 KB trim
  dropped ə, Azerbaijani's), the modifier letters romanised names use (ʹ ʺ ʾ ʿ ˈ ː - "Saʿīd"), Latin Extended
  Additional less Vietnamese's own file's range, the currency signs, ℓ and the dagger †. The first build dropped
  the modifier letters and † with the IPA block: Google's Latin face claims U+2000-206F but its file has no †
  (Justice's album), which Google's latin-ext had carried, so a dagger went to the fallback's Arial. The same file
  again: `pyftsubset --no-hinting --flavor=woff2` from Noto Sans 2.015 pinned at width 100 (the first build's
  recipe, which reproduces its file byte for byte), 72 bytes bigger; SemiCondensed's latin-ext the same from the
  87.5 instance (77 KB). **The files' own characters are in the suite now**: tests/fixtures/font_cmaps.json is
  each file's cmap, written by tests/fixtures/font_cmaps.py with fontTools (which the suite hasn't - nor the brotli
  a woff2's tables need) and kept to its file by sha256, so a rebuilt file without the list run again fails.
  test_type.py checks what each family DRAWS - each face's range as far as its file has it - for every letter
  and mark of its list (every European language's, the African letters, Vietnamese, Greek, Cyrillic, the
  modifier letters and †), in all three families, and that nothing Google's latin-ext served left Noto but the
  IPA, phonetic, modifier and Latin Extended-C/D letters the trim was for. Arrows and shapes the app uses
  (→ ↗ ▶ ✕) were never in a Noto subset and still come from the system.
- **A fallback sized to Noto Sans** (`Noto Sans Fallback`, second in `--font-family`): `local()` Arial (ArialMT,
  Liberation Sans, Arimo) at `size-adjust: 107.14%` - Noto's average English letter over Arial's, measured with
  fontTools - with Noto's ascent and descent as overrides divided by that (99.77%, 27.35%), a bold face for 600-700,
  and only over the characters Noto Sans's seven files have (their cmaps' union, 70 ranges as theme.css writes them), so it never draws
  what Noto Sans lacks. The first build gave it the union of Noto's faces' RANGES, which claim 85 printable
  characters the files haven't (Coptic's in the Greek block, and most of U+2000-206F's punctuation and spaces) - the U+2010 hyphen MusicBrainz writes in "Jay‐Z" and "Wu‐Tang Clan" among them - so those were
  drawn in Arial, 7% grown, for good, where 2.0.8 drew them in the system face; they go to the system face again.
  Safari reads size-adjust (17+) but not the overrides; it is on screen for a moment, on a first load.
- **Loading**: the page preloads Noto Sans's and SemiCondensed's Latin files (nearly every screen has a large
  title); the mono's Latin file comes when text needs it - an album page, Now Playing - and its other scripts' as
  Noto Sans's do. The bench
  page preloads only Noto Sans's (it draws no large title). A first visit to Home now fetches 76 KB of fonts
  (was 36); a Polish name 68 KB of Latin Extended (was 164), plus 76 KB more if it is in a title.

**Measured** (headless Chromium as deadwax.test over plain http, logins off, my own deadwax on 8111 over a stand-in
Navidrome on 4541 with the review's library plus a Polish, a Vietnamese, a Turkish and a various-artists album;
390x844 and 1440x900; before = HEAD 821456c served from an export on 8113): baselines as above; every title in
SemiCondensed, including Polish, Cyrillic and Vietnamese ones (their SemiCondensed files loaded); the Arabic album's
title and artist `direction: rtl`; body line height 23.12px at 17px; no console errors. Shots, before and after, in
`deadwax-scratch/work/fonts209-builder/rp/{before,after}-{phone,desk}/shots/`. **Not seen**: an iPhone (SF Mono
was never the data face there now, but the baselines were measured only in Chromium), Safari's `text-wrap:
balance` (17.5+; older ones wrap as before), and the fallback on a slow first load.

**After review** (the same rig, mine on 8114 over a stand-in on 4542, a playlist of twelve songs added to it): a
playlist row's length on its title's line, 0px on both frames (8.2 and 7.5 before the fix); CDP's
`CSS.getPlatformFontsForNode` on "Justice †", "Saʿīd ʾAbd", "Czesław/Niemen 1969", "Кино/Группа крови", "Mỹ
Tâm/2001" and "Βαγγέλης/Ωμέγα" in each of the three stacks: every glyph in the bundled face (the dagger, the
ayin and the ł were Liberation's before); "Jay‐Z"'s U+2010 in the system face, as in 2.0.8, not the fallback's
Liberation Sans.

**Pinned**: tests/test_type.py (21 tests: the files and licences, the files' own characters kept to them, the
descriptors, the ranges and what each family draws of the names' letters and marks, the fallback, the stacks, the preloads and their headers, the scale per frame, every field's size, the
pinned lines and player.css's tokens, the track row and a playlist's, the data face off prose and the data size
only on data, the sign-in button's size, the title face and balance, the
contrast, dir="auto" and the side it leaves a name on); ui/test/titles.sim.cjs (LONG_TITLE, code points, the three pages); debug.sim (the data face
on the field names' rows only); test_app_css / test_app_desktop_css / test_lab_page moved to `--dw-text-field` and
the folded tokens.
