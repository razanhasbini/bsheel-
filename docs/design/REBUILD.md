# Rebuilding the mobile app to the frames

## Use the rendered images, not the HTML

`export/` (beside this repo, at `~/Desktop/Bsheel Hackathon/export`) holds
every screen as a rendered JPEG/PNG — 21 mobile screens at 390x844, 5 state
panels, 6 component cards, 19 notification cards, 11 admin frames, 3 map
screens. `export/INDEX.md` lists them all.

**Read the image.** It is a far better specification than the inline CSS in
the `.dc.html`, and it is unambiguous about the things that actually caused
drift here — grounds, shadow colours, and shape. Use the HTML only to confirm
an exact pixel value once you can already see what you are building.

Reading `export/mobile/03-home-no-quest.jpg` immediately settled three
questions the HTML had left open, including one I had got wrong: the status
indicator on a recent-quest row is a **circle**, not a stadium. `h10` at `r5`
is only round when the width is 10 too, and I had left it at 8.

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

### The coloured-shadow system is wider than the spec text says

The written spec mentions violet on the active hero and jade on a cleared
quest. The renders show the rule is broader:

| Surface | Shadow |
|---|---|
| Active-quest hero | violet 6px |
| Empty-home slot machine | coral 6px |
| Recent-quest row | 3px in the **status** colour (jade done, muted expired) |
| **Feed post card** | 3px in the **category** colour — jade LEARNING, gold ADVENTURE |
| Everything else | ink |

The feed one is only visible in `export/mobile/09-feed.jpg`; no prose
describes it.

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

## Elements in the renders that do not exist in the app

Not styling gaps — missing functionality. Each needs plumbing before it can
be drawn, and a toggle that cannot persist is worse than an absent one.

| Render | Missing |
|---|---|
| `mobile/21-settings.jpg` | The push-notifications toggle, with its warning "Off means you won't be told if a submission is rejected". No such toggle exists; it needs a notification preference to write to. The spec singles this out, because turning that trigger off is what makes the appeal flow unreachable. |
| `map/*.jpg` | The whole map feature. |

## Two of these are rewrites, not restyles

**The feed.** The app is a vertical `PageView` where every post is a
full-screen page (`features/feed/presentation/widgets/reels_card.dart`, a
TikTok-style player). `export/mobile/09-feed.jpg` shows a scrolling list of
bordered cards, each with a visible header, media block, title, body and
action row, several per screen. That is a different architecture, not a
different skin — budget for it accordingly and expect the `PageController`,
its page-index state and the video autoplay logic to come out.

**The map does not exist.** `export/map/` has three frames — a map screen
with real Natural Earth geometry, a geometry legend, and country progress.
There is no map feature anywhere in `apps/mobile_app`. It is new work, not a
conformance pass, and it needs a product decision before anyone starts.

Also in `export/` but out of scope for the app: 21 deck slides and 12
marketing graphics.

## Not done — the remaining work, by frame

Open the render first; the HTML line range is there only for confirming a
value once you can see what you are building.

| Render in `export/` | HTML lines | Owner file(s) |
|---|---|---|
| `mobile/15-splash.jpg`, `mobile/01-onboarding-1.jpg`, `mobile/02-onboarding-4.jpg` | 30–95 | `features/splash/**`, `features/onboarding/**` |
| `mobile/03-home-no-quest.jpg` ✅, `mobile/04-home-active-quest.jpg`, `panels/panel-01.jpg` (hero state set) | 96–339 | `features/quests/**` |
| `mobile/05-slot-machine.jpg`, `mobile/06-quest-detail.jpg`, `mobile/07-submit-proof.jpg`, `mobile/08-submission-rejected.jpg` | 340–519 | `features/quests/**`, `features/submissions/**` |
| `mobile/09-feed.jpg` ⚠️ rewrite, `mobile/10-comments.jpg`, `mobile/20-post-detail.jpg` | 520–681 | `features/feed/**`, `features/comments/**` |
| `mobile/12-profile.jpg`, `mobile/13-leaderboard.jpg`, `mobile/14-collab.jpg` | 682–870 | `features/profile/**`, `features/leaderboard/**`, `features/collab/**` |
| `mobile/16-login.jpg`, `mobile/17-signup.jpg` | 871–990 | `features/auth/**` |
| `mobile/18-search.jpg`, `mobile/19-quest-history.jpg`, `mobile/21-settings.jpg`, `panels/panel-02..05.jpg` | 991–1246 | several |
| `mobile/11-notifications.jpg` + all 19 `notifications/notif-*.jpg` | 1247–1375 | `features/notifications/**` |
| `admin/01-login.jpg` … `admin/11-sidebar.jpg` (11 frames) | — | `apps/admin_web/**` |
| `map/01-map-screen.jpg`, `map/02-geometry-legend.jpg`, `map/03-country-progress.jpg` | — | **does not exist yet** |

✅ = done and verified against the render. ⚠️ = structural rewrite, see above.

`components/component-01-buttons.jpg` … `component-06-media-skeleton.jpg` are
the component sheet, already implemented in `shared_ui`. Check against them
before building anything screen-local.

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
