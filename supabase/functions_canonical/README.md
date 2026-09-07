# Canonical RPC bodies

This directory pins the **current authoritative source** for the RPCs that
have been redefined many times across migrations and are still load-bearing
in prod. ARC-012 / audit follow-up.

When you change one of the RPCs below, **edit the file here** and add a
new migration that `\i`-includes it (or copies the body). Don't keep
copying the body inline into a fresh migration — that's how we accumulated
10 versions of `get_feed`.

## What lives here

| RPC | File | Last canonical migration |
|---|---|---|
| `get_feed(p_limit, p_offset, p_sort, p_scope)` | `get_feed.sql` | 0149 |
| `get_submission_detail(p_submission_id)` | `get_submission_detail.sql` | 0134 |
| `compute_level(p_xp)` | `compute_level.sql` | 0132 |
| `appeal_submission(p_submission_id, p_appeal_note)` | `appeal_submission.sql` | 0149 |
| `vote_collab(p_group_id, p_submission_id)` | `vote_collab.sql` | 0149 |

Listed in earlier revisions of this table but **never actually written**:
`assign_random_quest.sql` and `guard_submission_owner_update.sql`. Their
authoritative bodies remain inline in `applied/0109` and `applied/0133`
respectively. Do not trust a row here without checking the file exists.

> **Why this table matters.** Between 0140 and 0149 this file claimed the
> authoritative `appeal_submission` body was 0119's. It was not — 0140 had
> reissued it, dropping 0119's `set_config('app.bypass_submission_guard')`
> line, which broke every non-admin appeal. Anyone reconciling the RPC
> against the "canonical" 0119 body would have seen the bypass and assumed
> production had it. Keep this column honest.

## Why not move ALL RPCs here?

Many RPCs have only been written once or twice — keeping their definition
in the migration that introduced them is simpler. Pin them here only when
you find yourself reaching for the "redefine this RPC" pattern for the
third+ time.

## Editing pattern

1. Edit the canonical file here.
2. **Copy the body inline** into a new top-level migration.
3. Bump the "Last canonical migration" column above.

> ⚠️ **Do NOT use `\i ../functions_canonical/<file>.sql` in a migration.**
> An earlier version of this README recommended it; it cannot work:
>
> - `.github/workflows/deploy-server.yml` rsyncs only `supabase/functions/`
>   and `supabase/migrations/` to the server. This directory never ships.
> - `scripts/server-deploy.sh` runs `psql ... < "$f"` — the file arrives on
>   **stdin**, so a relative `\i` has no directory to resolve against.
>
> With `ON_ERROR_STOP=1` the failed include would abort the whole deploy,
> and because `server-deploy.sh` only records a filename after the file
> succeeds, the migration would retry and fail on every subsequent deploy.

Yes, this means the body is duplicated between the migration and the file
here. That is the trade-off: the migration is the thing that actually runs,
and this directory is the place you read to find out what *should* be
running. When they disagree, production wins — and that disagreement is
itself the bug worth chasing.
