# shared_ui

Reusable Flutter widgets shared by the mobile app and the admin dashboard.

## What belongs here

A widget belongs in `shared_ui` when it is used by more than one feature and
carries no feature-specific logic:

- Arcade primitives (buttons, cards, pills, dialogs)
- `PixelAvatar` and other identity chrome
- Loading, empty and error states

## What does not belong here

- Anything that reads a repository or a provider. Widgets here take data and
  callbacks; they do not fetch.
- Anything used by exactly one feature — keep it in that feature's
  `presentation/widgets/`.
- Colours, spacing or text styles of its own. They come from `app_core`.

## Depends on

`app_core` only, for the design tokens.
