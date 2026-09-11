# Quest content seeds

Curated development content. **Not** the worldwide catalogue — that is a
later phase, reviewed before it goes near production.

## Files

- `places.json` — destinations. Coordinates only where they are known;
  anything uncertain carries `needsLocationReview: true` and is seeded
  unpublished, so it cannot reach a user until a human checks it.
- `quests.json` — the quests themselves, with their dimensions.
- `chains.json` — multi-stage, sequential-group and cross-country chains.
- `collections.json` — journeys.
- `partners.json` — demo sponsors. Every one has `isDemo: true`.

## Running

```bash
DATABASE_URL=… npm run seed:quests          # idempotent, safe to repeat
DATABASE_URL=… npm run seed:quests -- --prune   # also removes seeded rows no longer in the files
```

## Why every row has a `seedKey`

Idempotency is keyed on it, not on the title. Titles get edited — that is the
point of curated content — and keying on one would insert a second copy every
time somebody fixed a typo. The key is stable and never reused.

`--prune` deletes only rows whose `seed_key` is in the `bsheel:` namespace and
absent from the files. It cannot touch user-authored quests, because those
have no seed key at all.

## Safety

`validate.mjs` runs before any insert and refuses content that:

- names a real business as a paying partner (demo partners only)
- invents coordinates (a place needs real ones or `needsLocationReview`)
- asks for trespass, climbing, traffic violation, or disruption of worship
- points a chain step at a missing quest, or a collection at a missing one

A quest that fails validation stops the whole run. Partial content is worse
than none: half a chain is a dead end a user can walk into.
