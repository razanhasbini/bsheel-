# app_core

Pure-Dart foundations shared by both applications: design tokens, logging and
small utilities. No Flutter widgets, no networking, no models.

## What's here

| Area | Contents |
|---|---|
| `theme/` | `QuestColors`, `QuestSpacing`, `QuestTypography`, `QuestTheme` |
| `logger` | `AppLogger` — the only logging path; never `print` |
| `utils/` | date/time formatting, error mapping helpers |

## Theme is the single source of truth

Every colour, spacing value and text style in the mobile app comes from here.
Reskinning the app means editing these three files and nothing else.

Prefer the context helpers in widgets — `QuestColors.bg(context)`,
`cardBg(context)`, `text(context)`, `textDim(context)` — so a future
multi-theme setup needs no call-site changes.

The app is light-only (Arcade Pop). The `QuestColors.dark*` and `textPrimary`
tokens are "ink panel" colours used *inside* the light design (splash screen,
video overlays, arcade cards) — they are not a dark mode.

A genuinely one-off decorative colour (pixel art, a gradient stop) is allowed
only as a private `static const` in the file that uses it, with a
`// Screen-specific colour — not a theme token.` comment.

## Depends on

Nothing. This package sits at the bottom of the graph, which is why it must
stay pure Dart.
