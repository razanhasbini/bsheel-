# Bsheel Admin Panel — UI/UX spec

Design reference for `apps/admin_web`. Open **`Bsheel Admin Panel.dc.html`** in a
browser to see every frame. `AdminSidebar.dc.html` and `support.js` must stay in
the same folder.

The design covers all 21 routes in `admin_route_names.dart` plus nine
non-happy-path scenarios.

---

## 1. Theme decision

The admin panel is drawn in **Arcade Pop** — the same system as the mobile app,
not the black-and-white language currently in
`apps/admin_web/lib/core/theme/bsheel_design.dart`.

This is a deliberate change. Implementing it means rewriting `BsheelColors`,
`BsheelType` and `BsheelRadii` to the values below. No widget code needs to
change if those three files are the only source of colour, per the existing rule
in CLAUDE.md.

### Colour

Values are the mobile app's `QuestColors`, reused verbatim.

| Token | Hex | Use |
|---|---|---|
| `bg` | `#FFF9EE` | page ground |
| `surface` | `#FFF1D6` | headers, sidebars, secondary panels |
| `card` | `#FFFFFF` | cards, table bodies, inputs |
| `ink` | `#1A1330` | text, all borders, all shadows |
| `inkSoft` | `#5B5170` | secondary text |
| `inkMuted` | `#938AA8` | placeholders, disabled |
| `primary` | `#6B3BFF` | navigation active, primary action |
| `success` | `#17C27B` | approve, live, in-sync |
| `danger` | `#FF5A6E` | reject, ban, remove, fault |
| `accent` | `#FFC224` | anything waiting on a person |
| `cool` | `#4CC9F0` | informational accent |
| `dangerText` | `#C0392F` | red text on cream (passes 4.5:1) |

**Contrast rule, non-negotiable.** On coral, gold, jade and sky grounds, text is
always ink `#1A1330` — never white. White on `#FF5A6E` measures 3.03:1 and
fails; ink measures 5.88:1. This mirrors the existing `accentYellowInk`
convention. Never use alpha-muted type on an accent ground; use full-opacity ink
and let size and weight carry the hierarchy.

### Shape

- Borders: `2px solid #1A1330` on every card, input, button, chip and tile.
- Shadows: hard offset, zero blur. `BoxShadow(color: ink, offset: Offset(x, y), blurRadius: 0)`.
  - 3px cards and small buttons · 4px stat tiles and primary buttons ·
    5px tables · 6px hero panels · 8–10px page frames.
- Radii: 9–11px controls · 12–14px cards · 16px page frames · 999px pills.
- A coloured shadow (`#6B3BFF`, `#FF5A6E`, `#17C27B`) marks the one item in a
  list that needs attention. Everything else takes an ink shadow.

### Type

Fonts are already bundled in the mobile app's `pubspec.yaml`.

| Role | Family | Weight | Notes |
|---|---|---|---|
| Display | Syne | 800 (`fontVariations` wght axis) | page and card titles, numerals |
| Body | DM Sans | 400 / 500 / 600 | sentences |
| Label / data | JetBrains Mono | 700 | labels, ids, timestamps, counts, table headers |

**ALL CAPS is for labels and headers only** — anything four words or shorter.
Sentences stay normal case. This matters more than usual because the product
ships a second locale (Lebanese Arabizi).

Minimum sizes: 9px only for mono labels with letter-spacing; 13px body; 44px
minimum touch/click target on every control.

---

## 2. Route coverage

Every frame is labelled in the file with its route path.

| Route | Frame | Notes |
|---|---|---|
| `/login` | ✅ | shown in the `You are not authorized.` error state |
| `/confirm-email` | ✅ | includes resend cooldown |
| `/delete-account` | ✅ | public; type-DELETE confirmation |
| `/privacy` | ✅ | public; includes a "what moderators see" section |
| `/` | ✅ | dashboard |
| `/moderation` | ✅ | queue rail, inside the review frame |
| `/moderation/review/:id` | ✅ | drawn as the appeal / second-review case |
| `/moderation/history` | ✅ | filters, pagination, CSV export |
| `/appeals` | ✅ | overturn / uphold |
| `/reports` | ✅ | content report and user report |
| `/users` | ✅ | list + detail rail, suspend and ban |
| `/quests` | ✅ | quest bank, category filters, retired state |
| `/qotd` | ✅ | schedule, unscheduled-day warning |
| `/feed` | ✅ | visible / hidden / deleted |
| `/injection` | ✅ | drawn in its blocked state |
| `/xp` | ✅ | reconciliation audit with drift table |
| `/announcements` | ✅ | broadcast composer + recently sent |
| `/auto-notifications` | ✅ | per-trigger toggles |
| `/settings` | ✅ | feature flags + runtime config |
| `/web-signups` | ✅ | waitlist, bulk invite |
| `/web-quest-suggestions` | ✅ | accept into bank / discard |

Full-width 1280px shells are used where the work happens (dashboard, moderation,
history, appeals, quests, users, reports). The remaining pages are drawn as
640px content panes — the sidebar is identical on all of them, so it is omitted
rather than redrawn.

---

## 3. Sidebar

Sixteen destinations in this order, grouped by how often a moderator touches
them:

`DASHBOARD · MODERATION · APPEALS · HISTORY · FEED · QUESTS · QUEST OF THE DAY ·
USERS · XP · ANNOUNCEMENTS · AUTO NOTIFICATIONS · REPORTS · INJECTION ·
WEB SIGNUPS · QUEST SUGGESTIONS · SETTINGS`

- Ink `#1A1330` ground, 230px fixed width.
- Active row: violet fill, 2px cream border, white label.
- Badge counts on Moderation, Appeals and Reports only — the three queues that
  represent work waiting on a person. Coral when inactive, gold when active.
- Footer shows the signed-in moderator and their role.

---

## 4. Interaction notes

**Moderation review is the panel's centre of gravity.** Everything else is
support. The layout is queue rail → evidence → decision, left to right, so the
moderator's eye lands on the decision last.

- Keyboard: `J` / `K` move through the queue, `A` approve, `R` reject.
- Reviewer context (approval rate, prior rejections, reports against, appeal
  spent) sits beside the decision buttons, never below the fold.
- On an appealed submission, the first decision and its reasons are shown
  inline. A moderator should never have to leave the page to see why the
  submission was rejected the first time.
- `RE-REJECTION IS FINAL — NO FURTHER APPEALS` sits directly under the buttons.

**Colour carries meaning.** Jade approves, coral rejects, gold marks anything
waiting on a person, violet is navigation and primary action. Do not use these
decoratively.

**Destructive actions never sit next to their opposite** at the same visual
weight. Approve is a filled jade button; Reject is filled coral. Both are
deliberate, neither is an accident.

---

## 5. Scenarios

All nine are drawn in section 07 of the file.

| Scenario | Rule |
|---|---|
| Loading | Skeletons match the real row shapes so nothing jumps. No spinner. |
| Empty | Every empty state names one thing to do next. `ALL CLEAR` offers the appeals queue. |
| Error | Say what did *not* happen — "no decision has been recorded" — then offer retry. |
| Offline | Persistent bar, not a toast. Actions stay enabled and queue locally. |
| Suspended / banned | QOTD ticket is hidden entirely, not disabled. |
| Blocked user | Profile is reachable but stripped, so a block never reads as a deleted account. |
| Rate limit | State the real reset time. The limit is server-authoritative; don't hide the button. |
| Hidden vs deleted | Hidden is reversible and says so. Permanent deletion offers no action. |
| First run | Suppress stat tiles, XP meter and streak at zero rather than showing `0`. |

---

## 6. Two open issues found while designing

Neither is a design problem — both are product gaps the design exposed.

**1. Turning off `submission_rejected` breaks the appeal flow.**
`CLAUDE.md` states that exactly three things route to
`submission_status_page.dart`, and the notification tap is the primary one. The
`/auto-notifications` page currently lets a moderator switch that trigger off in
one tap. The design shows a warning; it should probably be a confirm dialog, and
arguably the trigger should not be switchable at all.

**2. An unscheduled Quest of the Day fails silently.**
If no QOTD is queued for a date, the ticket simply does not render and nothing
in the admin surfaces that. The `/qotd` frame flags an unscheduled day in coral
for this reason. Consider a dashboard warning when the next 48 hours are empty.

---

## 7. Files

```
Bsheel Admin Panel.dc.html   every frame, in order
AdminSidebar.dc.html         the sidebar, one `active` prop
support.js                   runtime — do not edit
SPEC.md                      this file
```

These are design references, not shippable code. They are plain HTML with inline
styles; read the values off them and implement in Flutter.
