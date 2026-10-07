# The interface: CSS, panels, phones and the design system

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
