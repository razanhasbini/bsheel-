# supabase_contracts

Domain value constants shared by the clients: statuses, categories,
difficulties, roles, notification types, and the field names the API uses.

> **The package name is historical** and no longer accurate — nothing here
> talks to Supabase. It is a plain constants package. Renaming it touches every
> importing file, so it is a deliberate, separate change.

## Why this exists

These strings are also database `CHECK` constraint values. A typo in one does
not fail at compile time — it fails at write time, in production, on a value
the database rejects. Declaring them once means the compiler catches the typo
instead.

```dart
// yes
status: SubmissionStatus.pending

// no — a silent write failure waiting to happen
status: 'pendign'
```

## What belongs here

- Status and enum-like value sets that the database constrains
- Quest categories and difficulties
- Admin roles, notification types, media types, visibility values
- The API's JSON field names

## What does not

- Anything with behaviour. This package is constants only, which is why it is
  pure Dart and sits at the bottom of the dependency graph.
- Table or RPC names. The clients no longer speak SQL; they call HTTP routes.
