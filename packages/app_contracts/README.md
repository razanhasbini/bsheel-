# app_contracts

Domain value constants shared by the clients: statuses, categories,
difficulties, roles, notification types, and the field names the API uses.

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
- Table names, RPC names or storage paths. The clients speak HTTP, so those
  went with the direct-database access that needed them. What remains under
  `EmbedKeys` are the JSON keys of objects the API nests in a response.
