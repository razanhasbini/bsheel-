# app_models

Shared data models: the shapes the API returns, decoded once and used
everywhere.

## Conventions

- **`fromJson` is defensive.** The API is the contract, but a model must not
  crash the UI on a missing or wrongly-typed field. Coerce with an explicit
  default and make the default obvious (`(json['xp'] as num?)?.toInt() ?? 0`).
- **Field names follow the API**, which is snake_case. The constant names for
  those keys live in `supabase_contracts`.
- **Models are immutable.** Add a `copyWith` when a screen needs to vary one
  field; do not add setters.
- **No networking and no Flutter.** A model must be testable in a plain Dart
  test with a map literal.

## Where a model must not live

If a shape is used by exactly one feature and never crosses a repository
boundary, keep it in that feature. This package is for shapes shared across
features or apps — duplicating a model per feature is how two definitions of
the same thing start to disagree.

## Depends on

`app_core` and `supabase_contracts`. Both are pure Dart, so this package is
too.
