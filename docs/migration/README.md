# Backend migration control room

This directory is the audit trail for replacing Supabase with the NestJS backend. The copied Supabase implementation remains an immutable behavior reference until every parity row is implemented and verified. It is not the destination architecture.

## Non-negotiable parity rule

For each behavior, read in this order:

1. the newest definition in `supabase/migrations/` (read every redefinition, not only the first);
2. the matching canonical function in `supabase/functions_canonical/` when present;
3. the repository implementation in `packages/app_repositories/`;
4. the Dart model in `packages/app_models/` and constants in `packages/supabase_contracts/`;
5. every mobile/admin caller, provider, route, and error-state branch;
6. tests, security notes, `README.md`, `CLAUDE.md`, and `FIXLOG.md`.

A row is `VERIFIED` only when contract, integration, and UI tests demonstrate equivalent results and side effects. “The endpoint exists” is not parity.

## Migration phases

1. Inventory and freeze the legacy snapshot.
2. Establish the Nest modular-monolith platform and new PostgreSQL baseline.
3. Port domains behind versioned REST/WebSocket contracts.
4. Add `Api*Repository` Dart implementations while preserving existing repository interfaces and models.
5. Run dual-backend contract fixtures and golden user journeys.
6. Rehearse data migration, reconcile counts/checksums, and shadow-read production traffic.
7. Canary the new backend, retain rollback, then remove Supabase dependencies only after the observation window.

Do not delete `supabase/`, `cloudflare/`, or any `Supabase*Repository` during implementation. They are the parity oracle and rollback path.

The Nest Flutter composition roots are isolated under each app's
`lib/core/backend/` directory. Canary builds will use `BACKEND_MODE=nest` and
`NEST_API_URL=<absolute /api/v1 URL>` only after all providers used by that
journey have contract fixtures. Production remains on `legacy` by default
during the strangler phase; both modes use one repository bundle and one
rotating secure token store per application.

`scripts/legacy-migration-allowlist.txt` records every tracked Flutter file
that has crossed the backend-neutral boundary. The snapshot verifier still
byte-checks every unlisted implementation file, so intentional cutover work
cannot hide unrelated source drift.
