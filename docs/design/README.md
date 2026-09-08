# Design handoff

The Arcade Pop specs both clients were built to. `admin/` covers
`apps/admin_web`, `mobile/` covers `apps/mobile_app`.

Each folder holds:

- **`SPEC.md`** — the written contract: colour tokens, the contrast rule, shape
  and shadow scales, type, route coverage, and the non-happy-path states. Read
  this first.
- **`Bsheel *.dc.html`** — every frame, in order. Open in a browser; keep
  `support.js` beside it or the page will not render.
- **`support.js`** — runtime for the HTML. Do not edit.

These are **references, not shippable code** — plain HTML with inline styles.
Read the values off them and implement in Flutter.

## Why they are in the repo

They previously lived in the folder *above* the repo, which had been
accidentally `git init`-ed and tracked `bsheel-` as a stray gitlink. That made
the specs invisible to anyone who cloned this repository, and made the working
copy show phantom changes after every commit. They belong with the code that
implements them.

## The one rule worth repeating here

**On coral, gold, jade and sky grounds, text is ink `#1A1330` — never white.**
White on coral measures 3.03:1 and fails WCAG AA; ink measures 5.88:1.

Do not decide this by eye at the call site — coral and jade in particular look
dark enough for white text and are not. Call the helper:

- `QuestColors.onAccent(ground)` / `BsheelColors.onAccent(ground)` — text sitting
  **on** an accent fill.
- `QuestColors.onCream(accent)` / `BsheelColors.onCream(accent)` — an accent used
  **as** text or an icon on cream, where the fills fail at small sizes (coral
  2.9:1, jade 2.2:1, sky 1.9:1, gold 1.6:1).

Alpha-muting type on an accent ground puts it back under AA, which is the thing
the helpers exist to prevent. Use full opacity and let size and weight carry the
hierarchy.
