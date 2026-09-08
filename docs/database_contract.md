# Database contract

## Where the schema lives

`backend/migrations/` is the only source of truth for the schema. There is no
hand-maintained copy in this document on purpose: a second description of a
schema drifts from the first, and then you have two answers and no way to tell
which is right. The previous version of this file did exactly that and was
wrong by the time anyone read it.

To see the current shape:

```bash
cd backend
DATABASE_URL=postgresql://bsheel:bsheel@127.0.0.1:5432/bsheel_scratch npm run db:migrate
PGPASSWORD=bsheel psql -h 127.0.0.1 -p 5432 -U bsheel -d bsheel_scratch -c '\d+ submissions'
```

A table-by-table overview is in the README; the domain boundaries that own
each table are in `docs/architecture.md`.

## Rules for changing it

### 1. Forward-only, and immutable once applied

`backend/scripts/migrate.mjs` records a SHA-256 checksum per file and **refuses
to run when an applied migration's contents have changed**. If a migration is
wrong, do not edit it — add the next numbered file that corrects it.

New migrations are `NNNN_short_description.sql` with the next number. Never
renumber an existing one; the number is its identity in the ledger.

### 2. Wrap every migration in a transaction

```sql
BEGIN;
  ALTER TABLE …;
COMMIT;
```

Without it, a failure at statement N leaves statements 1..N-1 committed *and*
the file unrecorded, so the next run replays the whole thing over a
half-migrated database.

The one exception is `CREATE INDEX CONCURRENTLY`, which cannot run inside a
transaction. Put those statements outside the block and say why in a comment.

### 3. Backward compatible across one deploy window

During a rolling release, the old and new code both run against the same
schema. So a rename is three releases, not one:

1. add the new column, write to both, read from the old
2. backfill, then switch reads to the new column
3. drop the old column

A single-step rename takes the old replicas down the moment the migration
lands.

### 4. Constraints belong in the database

Uniqueness, legal values and referential integrity are the database's job, not
the application's. An application-level check is an optimisation for a nicer
error message; it is never the guard.

Specifically, keep in SQL:

- unique indexes behind idempotent actions (follows, reactions, saved posts and
  quests, one active quest per user)
- `CHECK` constraints on status and enum-like columns
- foreign keys with a deliberate `ON DELETE` — think about whether a delete
  should cascade, null out, or be restricted, and encode that decision

When application code and a constraint disagree, the constraint wins and the
application gets an error. That is the correct outcome: a bug surfaces instead
of writing bad data.

### 5. Translate constraint violations into stable error codes

A raw `23505` reaching the client is useless to it. Catch the violation in the
repository, inspect the constraint name, and throw a domain exception with a
stable machine-readable code:

```ts
if (constraint.includes('username')) {
  throw new ConflictException({ code: 'USERNAME_TAKEN', message: '…' });
}
```

Clients branch on `error.code`, never on the message. This matters: collapsing
two different conflicts into one code means a form cannot tell the user which
field to fix.

### 6. Critical transitions lock and run in one transaction

Anything that reads state, decides, then writes must hold a lock across all
three — otherwise two concurrent requests both pass the check. Use
`SELECT … FOR UPDATE` on the aggregate, or an advisory lock per user where the
guard spans rows (quest assignment does this).

This covers: quest assignment, moderation and appeals, XP award and revoke,
reaction toggling, follow, quest deletion.

### 7. State change and event emission share the transaction

A row that changes and an event that announces the change are inserted
together, in one transaction, with the event going to `outbox_events`. A
publisher then claims events with `SKIP LOCKED` and enqueues them.

Never emit to a queue from inside a request handler before the transaction
commits: the job can be picked up and act on state that then rolls back.

Consumers record `processed_messages` only after the real side effect
completes, so a retry cannot double-award XP or send a notification twice.

### 8. Media never goes in the database

Store object keys. Bytes live in object storage, private, served through
short-lived signed URLs.

### 9. Every schema change needs a test

An integration test in `backend/test/` that would fail without the migration.
This is not ceremony: unparameterised knowledge of the schema is exactly what
broke the legacy system — a query referenced a column that did not exist and
failed silently every hour for a day, having never once succeeded.

## Checklist for a schema change

1. Write the migration as the next number, wrapped in `BEGIN; … COMMIT;`.
2. Update the repository, service and DTO that use it.
3. Add or update the domain value constants in
   `packages/supabase_contracts/lib/statuses.dart` if you added a status or
   enum-like value.
4. Update the Dart model in `packages/app_models/lib/` if the API shape changed.
5. Add an integration test that fails without the migration.
6. Verify a clean replay: `npm run db:migrate` against an empty database, then
   `npm run db:migrate:check`.
7. Run `npm run test:e2e`.
8. Note the change and its reason in the commit message.
