# Source audit

The migration snapshot was copied from the clean legacy commit `c739439bce0508dc1a29ceea63b3a4cf548d3ca4`. It includes both Flutter apps, shared packages, all Supabase SQL/Edge Functions, Cloudflare workers, seeds, tests, deployment scripts, and operational documentation. Git history and generated caches were intentionally not copied.

Audit scope discovered at migration start:

- 638 tracked legacy files in the source repository;
- 411 app/shared/backend-related files under `apps`, `packages`, `supabase/functions`, and `cloudflare`;
- approximately 122,000 lines in those paths;
- 150 numbered database migrations, including frozen history and pending top-level migrations;
- 19 client-visible tables and 36 named client RPC contracts, plus SQL-only functions/triggers;
- two Flutter applications and five shared Dart packages.

The legacy schema-drift check already failed before migration because its allow-lists omit newer contracts and flag some legitimate hardcoded web tables. That pre-existing failure is recorded here so it is not mistaken for a migration regression. The new OpenAPI contract and parity tests replace regex-only drift detection.

Run `scripts/verify-legacy-snapshot.sh` from the new repository while the original checkout is still available to verify that every non-allowlisted Flutter, Supabase, and Cloudflare implementation file remains byte-identical. Repository-level CI/dependency configuration is intentionally allowed to evolve for the new stack. Every intentional tracked-file change must be recorded explicitly in `scripts/legacy-migration-allowlist.txt`; this keeps the strangler cutover auditable while all untouched application source remains byte-checked.
