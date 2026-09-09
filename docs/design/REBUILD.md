# Rebuilding the mobile app to the frames

Working notes for finishing the screen-by-screen match to
`mobile/Bsheel Mobile App.dc.html`. Written mid-job so it can be picked up
without re-deriving anything.

## The thing to understand first

`mobile/SPEC.md` section 1 says, in its own words: *"the design does not ask
you to reskin the app."* That is true of the **tokens** — `QuestColors`
already holds every value the design uses. It is **not** true of the screens.

So a lot of the app already conforms exactly (the home stat tiles, the fixed
home ordering, the bottom-nav structure) and will look unchanged after a
correct pass. The real differences are specific and findable:

| Kind of difference | Example found |
|---|---|
| Ink shadow where the frame draws a **coloured** one | slot machine wanted coral 6px; hero wanted violet 6px |
| Navy ground where the frame draws **white** | slot machine card |
| Black panel where the frame draws **cream** | slot machine reels (`#FFF1D6`) |
| Bespoke art the frame does not have | a hand-painted Pac-Man scene in the reels |
| `2.5px` borders | the design is **2px everywhere**, without exception |

**The coloured shadow is the load-bearing signal.** The spec reserves it to
mark the single most important thing on a screen — violet on the active-quest
hero, jade on a cleared quest, coral on the empty-home card. Everything else
takes ink. The app was using ink for all 17 shadows on home.

## Values read off the frames

Measured from the inline styles, so these are literal, not interpreted.

### Radii — note these differ by role
- `11` small buttons, icon buttons, chips, pills-that-are-buttons
- `12` list rows, reels, media thumbs
- `13` text inputs and the comment composer
- `14` full-width buttons, stat tiles
- `16` component cards
- `18` hero panels and the slot-machine card
- `36` the phone frame itself
- `999` status pills, language chips

### Shadow depths
`3px` small cards, chips, icon buttons, list rows · `4px` stat tiles,
secondary buttons, bottom nav · `5px` primary buttons · `6px` hero panels ·
`8px` the phone frame

### Recurring elements

| Element | Spec |
|---|---|
| Icon / back button | 44pt, `r11`, white ground, ink 3px shadow, 15px glyph |
| Bell | 44pt, `r12`, **gold** ground, 3px shadow; badge `h20 r10` coral with **ink** text |
| Stat tile A | gold ground, `r14`, 4px shadow, 12/14 padding; label mono 10, value Syne 800 32, sub mono 9 — all `#2A1B00` |
| Stat tile B | violet ground, same geometry, all text **white** |
| QOTD ticket | sky ground, 4px shadow, 11/13 padding; icon box `h34 r9` cream; TAKE button `h38 r9` **ink ground, cream text** |
| List row | white, `r12`, **3px shadow in the status colour**, 11/13 padding; status bar `h10 r5` 2px ink border |
| Vote button (active) | violet ground, **white** text, `r11`, 3px shadow |
| Vote button (idle) | white ground, ink text, `r11` |
| Comment composer | `r13` white, placeholder `#938AA8`; send `r13` violet + white, 3px shadow |
| Language chip | active = ink ground + cream text, `r999`; idle = `#FFF1D6`, `r999` |
| Confirm button | jade ground, **ink** text, `r11`, 3px shadow |
| Destructive text | `#C0392F` (`QuestColors.osRedText`) — never coral itself as small type |

### Type
Syne 800 for display (28 name, 44 headline, 32 stat value, 22–23 page title,
19 secondary title) · DM Sans 400/500/600 for sentences (13–16) · JetBrains
Mono 700 for every label, id, timestamp and count (9–12), and for timers.

## Done so far

- `shared_ui` controls matched to component sheet section 09: button variants
  and fills corrected (PRIMARY is **violet**, not gold), 56pt height, plus new
  `ArcadeToggle`, `ArcadeMeter`, `ArcadeSegments`, `ArcadeTimer`.
- Home slot machine: white card + coral 6px shadow; three cream reels
  replacing the Pac-Man strip.
- Home active-quest hero: violet 6px shadow, 2px border.

## Not done — the remaining work, by frame

Line ranges are into `mobile/Bsheel Mobile App.dc.html`. The file is
inline-styled, so every value is literal — read it, do not infer.

| Section | Lines | Screens | Owner file(s) |
|---|---|---|---|
| 01 ENTRY | 30–95 | splash, onboarding 1 & 4 | `features/splash/**`, `features/onboarding/**` |
| 02 HOME | 96–339 | remaining hero states: pending review, TIME OVER, suspended/banned | `features/quests/**` |
| 03 QUEST → PROOF → REVIEW | 340–519 | slot machine detail, quest detail, submit proof, submission status | `features/quests/**`, `features/submissions/**` |
| 04 SOCIAL | 520–681 | feed, comments, post detail | `features/feed/**`, `features/comments/**` |
| 05 PROGRESSION | 682–870 | profile, leaderboard (sticky self-row), collab head-to-head | `features/profile/**`, `features/leaderboard/**`, `features/collab/**` |
| 06 AUTH | 871–990 | login, signup, forgot, reset, updated | `features/auth/**` |
| 07 SECONDARY | 991–1246 | search, quest history, settings, edit profile, other profile, join collab, blocked users | several |
| 08 NOTIFICATIONS | 1247–1375 | all 19 types + routing | `features/notifications/**` |

Partition agents by **owner file** so they cannot collide. Four worked cleanly
before: quests+submissions / feed+comments+notifications / auth+onboarding+
splash / profile+leaderboard+collab+search+settings.

## Rules to hand every implementer

1. Colours from `QuestColors` only — the tokens already hold the design's
   values. Never a hardcoded hex.
2. **Contrast, non-negotiable.** On coral, gold, jade and sky, text is ink —
   never white. `QuestColors.onAccent(ground)`. An accent used *as* text on
   cream takes `QuestColors.onCream(accent)`; the fills fail at small sizes
   (coral 2.9:1, jade 2.2:1, sky 1.9:1, gold 1.6:1). White on violet, on the
   ink panels, and on the violet→coral gradients is correct and must stay —
   the gradient midpoint measures 4.56:1 for white against 3.43:1 for ink.
3. 44pt minimum on every hit area (`QuestSpacing.minTouchTarget`), applied to
   the hit box, not the paint.
4. Unbounded `Text` in a `Row` needs `Expanded`/`Flexible` + `maxLines` +
   `TextOverflow.ellipsis`. Chip rows become `Wrap`. Check at 320dp.
5. ALL CAPS for labels and headers only, four words or fewer. Sentences stay
   normal case — SPEC.md calls out the onboarding subtitles running four lines
   of caps as wrong.
6. Use `shared_ui`, never `lib/design/bs_widgets.dart`. That file is a second
   private component set (`ChunkyButton`, `ChunkyCard`, `BsChip`, `BsXpBar`,
   `BsSegBar`, `BsToggle`, `BsSectionHeader`, `BsMinTouch`) and pages mix the
   two, which is exactly why the look drifts and why no single edit changes
   it. Replace its usages as you go; it should end up deletable.
7. `withAlpha()`, never `withOpacity()`.

## Do not break these

- **The splash `onReady` callback.** `ArcadeSplashScreen`'s
  `AnimationController` status listener fires it once on completion, and
  `app_router.dart` then does `go(RoutePaths.home)`. It is the only thing that
  moves a user off the splash. Break it and the app hangs on a blank screen.
- **Home ordering**, which is fixed: name+bell → headline → two stat tiles →
  QOTD ticket → hero → recent quests → weekly XP → friend activity → streak.
  Only the hero zone is status-driven.
- **Notification routing** — match the existing switch in
  `notifications_page.dart`; the destinations are load-bearing, and one of
  them is the primary route to the appeal flow.

## Verify, every time

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
cd apps/mobile_app
flutter analyze --no-pub   # zero issues, not "no errors"
dart format .
flutter test               # analyze passing does NOT mean it renders
```

`flutter analyze` has passed in this repo while the app failed to compile into
a widget tree. Run the tests.

To see it: `flutter run -d chrome --web-port=3000
--dart-define=API_URL=http://127.0.0.1:3010/api/v1`. Port 3000 is required —
it is in the API's `CORS_ORIGINS`, and a random port fails every request with
a CORS error while the UI just sits there. Sign in as `sami@bsheel.test` /
`Str0ng-Passphrase-9`.
