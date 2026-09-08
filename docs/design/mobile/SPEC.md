# Bsheel Mobile App — UI/UX spec

Design reference for `apps/mobile_app`. Open **`Bsheel Mobile App.dc.html`** in a
browser to see every frame; keep `support.js` in the same folder.

Covers all 28 routes in `route_names.dart`, all 19 `NotificationType` values,
the component library, and every non-happy-path state.

---

## 1. Theme

**Arcade Pop, unchanged.** These are the values already in
`packages/app_core/lib/theme/quest_colors.dart` — the design does not ask you to
reskin the app. Use `QuestColors` as-is.

| Token | Hex | Use |
|---|---|---|
| `osBg` | `#FFF9EE` | page ground |
| `osSurface` | `#FFF1D6` | headers, bottom nav, secondary panels |
| `osCard` | `#FFFFFF` | cards, inputs |
| `osTextPrimary` | `#1A1330` | text, every border, every shadow |
| `osTextSecondary` | `#5B5170` | secondary text |
| `osTextMuted` | `#938AA8` | placeholders, disabled |
| `osPrimary` | `#6B3BFF` | primary action, navigation |
| `osSuccess` | `#17C27B` | approved, positive |
| `osRed` | `#FF5A6E` | rejected, streak, destructive |
| `osAccent` | `#FFC224` | waiting, XP, Quest of the Day |
| `osCool` | `#4CC9F0` | informational accent |
| `darkBg` | `#1A1330` | ink panels — hero, splash, collab |

Two values the design adds, both for text-on-cream only where the token colours
would fail contrast:

- `#C0392F` — red text on cream (`osRed` at 13px on cream is too light)
- `#0F7A4E` / `#8A5F09` — green and amber label text on cream

### Contrast rule

**On coral, gold, jade and sky grounds, text is ink `#1A1330` — never white.**
White on `#FF5A6E` measures 3.03:1 and fails; ink measures 5.88:1. This follows
the `accentYellowInk` convention already in the file. Never use `withAlpha()` on
type sitting on an accent ground — full-opacity ink, and let size and weight
carry hierarchy.

### Shape

- Borders: `2px solid #1A1330` on every card, input, button, chip and tile.
- Shadows: hard offset, zero blur — `BoxShadow(color: ink, offset: Offset(x,y), blurRadius: 0)`.
  - 3px small cards and chips · 4px stat tiles and secondary buttons ·
    5px primary buttons and media · 6px hero panels · 8px phone-level frames.
- Radii: 9–14px controls · 12–16px cards · 18px hero panels · 999px pills.
- A **coloured** shadow marks the one item on screen that matters most
  (`#6B3BFF` on the active-quest hero, `#17C27B` on a cleared quest). Everything
  else takes an ink shadow.

### Type

Already bundled. `QuestTypography` needs no changes.

| Role | Family | Weight |
|---|---|---|
| Display | Syne | 800 via `fontVariations` wght axis |
| Body | DM Sans | 400 / 500 / 600 |
| Label, data, timers | JetBrains Mono | 700 |

**ALL CAPS is for labels and headers only** — four words or fewer. Sentences
stay normal case. The current onboarding subtitles run four lines of caps; that
is the one place the design deliberately keeps existing copy verbatim so you can
see the cost. With Lebanese Arabizi shipping as a second locale this matters
more than usual.

Minimum sizes: 9px only for mono labels with letter-spacing; 13px body;
**44pt minimum on every touch target** — including feed vote buttons and comment
reply, which are currently below that.

---

## 2. Route coverage

Every frame carries its route label in the file.

**Auth** — splash, login (drawn with a field error), signup, forgot password,
reset password, password updated, onboarding 1 and 4 of 4.

**Home** — no active quest, active quest with live countdown, plus a state set
covering pending review, TIME OVER, and suspended/banned. Order is fixed:
name → headline → stat tiles → QOTD ticket → hero → recent quests → weekly XP →
friend activity → streak. Only the hero zone is status-driven.

**Quest flow** — slot machine (three options), quest detail, submit proof,
submission status (rejected with appeal open), plus a state set for approved,
appealed-pending, and re-rejected/final.

**Social** — feed, comments with threaded reply and mention, notifications,
post detail.

**Progression** — profile, leaderboard with sticky self-row, collab
head-to-head with public voting.

**Secondary** — search, quest history, settings, edit profile, another user's
profile, join collab by code, blocked users.

---

## 3. Notifications

All 19 types are drawn in section 08 with the destination each one routes to,
matching the switch in `notifications_page.dart`:

| Routes to | Types |
|---|---|
| Submission status | `submission_approved`, `submission_rejected`, `new_submission`, `appeal_submitted` |
| Home | `quest_assigned`, `quest_expired`, `quest_timer_warning`, `pending_review_reminder`, `announcement` |
| Post detail | `reaction_received`, `reaction_milestone`, `new_comment`, `comment_reply`, `mention`, `follow_quest_completed` |
| User profile | `new_follower` |
| Leaderboard | `leaderboard_overtaken`, `top_10_entry` |
| Profile | `level_up` |

Colour maps to meaning, not to type: jade approved, coral rejected or urgent,
gold waiting, violet progression and social, white informational.

**Read vs unread** is carried by border weight and shadow, never by fill or
dimmed text. Unread keeps the 2px ink border and hard shadow; read drops the
shadow and thins the border to 1px.

---

## 4. The one change worth making first

`CLAUDE.md` states that exactly three things route to
`submission_status_page.dart`, and the notification tap is the primary one. Two
of the three are transient. **If push delivery breaks, a rejected user cannot
find the appeal at all.**

The QUEST HISTORY frame adds a fourth, durable route: the REJECTED group renders
a coral row with its own APPEAL button and a `1 APPEAL AVAILABLE` label. It
costs one row change and removes the dependency on FCM entirely.

Related: the Settings frame labels the push toggle with the real consequence —
"Off means you won't be told if a submission is rejected" — rather than a bare
switch.

---

## 5. Scenarios

| Scenario | Rule |
|---|---|
| Loading | Skeletons keep the 2px border in muted violet-grey and match real row shapes. No spinner. |
| Empty | Every empty state names one thing to do next. |
| Error | Say what did *not* happen before offering retry. |
| Suspended / banned | QOTD ticket is hidden entirely, not disabled. |
| Blocked | Profile reachable but stripped, so it never reads as a deleted account. Blocks cut both directions. |
| Rate limit | State the real reset time; the limit is server-authoritative, so don't hide the button. |
| Hidden vs deleted | Hidden is reversible and says so; permanent deletion offers no action. |
| First run | Suppress stat tiles, XP meter and streak at zero rather than showing `0`. |
| Timer under 5 min | Countdown moves to a coral chip. |

---

## 6. Components

Section 09 covers buttons (five states), category tags vs status pills, inputs
with focus and error, meters, timers, avatars, the bottom nav, and media
placeholders and skeletons.

Two rules worth carrying into code:

- **Shadow depth is the weight scale.** 5px primary, 4px secondary, none
  disabled. A disabled control also swaps to a dashed border so it reads as
  unavailable rather than merely dim.
- **Category tags are 8px-radius squares; status pills are fully round.** The
  shape tells them apart before the text does.

---

## 7. Files

```
Bsheel Mobile App.dc.html   every frame, in order
support.js                  runtime — do not edit
SPEC.md                     this file
```

These are design references, not shippable code — plain HTML with inline styles.
Read the values off them and implement in Flutter. The admin console has its own
package; it now uses the same Arcade Pop tokens, which means
`bsheel_design.dart` needs rewriting to match `QuestColors`.
