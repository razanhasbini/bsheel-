# Read-only access for the legacy import

The importer reads the old Supabase database directly rather than through
PostgREST, for three reasons:

* `auth.users` holds the email addresses, and PostgREST does not expose the
  `auth` schema at all. Without emails, imported accounts cannot sign in to
  the new backend.
* Migration `0143_emergency_pentest_lockdown.sql` closed the anonymous
  policies after a pentest confirmed the publishable key allowed mass reads
  of profile, feed and submission data. The anon key in `quest-app` is
  therefore useless here, by design.
* Paging 146-migration-deep tables over HTTP is slow and easy to get wrong.

Run this **once**, in the Supabase dashboard SQL editor, as `postgres`.
Replace the password with one you generate; nothing here needs to match
anything on the Bsheel side.

```sql
-- 1. A login role with no rights beyond reading four tables.
CREATE ROLE bsheel_import_ro WITH
  LOGIN PASSWORD 'REPLACE-WITH-A-GENERATED-PASSWORD'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

-- 2. Connect and schema usage. Usage alone grants no table access.
GRANT CONNECT ON DATABASE postgres      TO bsheel_import_ro;
GRANT USAGE   ON SCHEMA   public        TO bsheel_import_ro;
GRANT USAGE   ON SCHEMA   auth          TO bsheel_import_ro;

-- 3. SELECT on exactly the tables the import needs, and nothing else.
GRANT SELECT ON public.profiles      TO bsheel_import_ro;
GRANT SELECT ON public.quests        TO bsheel_import_ro;
GRANT SELECT ON public.user_quests   TO bsheel_import_ro;
GRANT SELECT ON public.submissions   TO bsheel_import_ro;

-- 4. Only the auth columns we actually use. Column-level grants keep
--    password hashes, recovery tokens and MFA factors out of reach even
--    if the importer is wrong or malicious.
GRANT SELECT (id, email, created_at, last_sign_in_at, email_confirmed_at)
  ON auth.users TO bsheel_import_ro;

-- 5. Row-level security still applies to this role, and the policies test
--    `auth.uid()`, which is NULL on a direct connection — so without this
--    the role would connect successfully and read zero rows. BYPASSRLS is
--    the honest way to say "this is an operator, not an app user".
--    If your Supabase tier refuses it, use the policy fallback below.
ALTER ROLE bsheel_import_ro BYPASSRLS;
```

If `ALTER ROLE ... BYPASSRLS` errors with insufficient privilege, grant the
same effect narrowly instead — read-only, and scoped to this one role:

```sql
CREATE POLICY import_ro_read ON public.profiles
  FOR SELECT TO bsheel_import_ro USING (true);
CREATE POLICY import_ro_read ON public.quests
  FOR SELECT TO bsheel_import_ro USING (true);
CREATE POLICY import_ro_read ON public.user_quests
  FOR SELECT TO bsheel_import_ro USING (true);
CREATE POLICY import_ro_read ON public.submissions
  FOR SELECT TO bsheel_import_ro USING (true);
```

Then give the importer a connection string. Supabase's direct-connection
host is on the dashboard under Settings → Database; use the **session**
(port 5432) endpoint, not the transaction pooler, because the import runs
one long read transaction:

```
LEGACY_DATABASE_URL=postgresql://bsheel_import_ro:PASSWORD@db.<ref>.supabase.co:5432/postgres?sslmode=require
```

## When you are done

The role has served its purpose after one successful import. Revoking it is
one statement, and worth doing rather than leaving a standing credential:

```sql
DROP ROLE bsheel_import_ro;
```

## Separately, and more urgently

`CLAUDE.md` records a `service_role` JWT with a 2036 expiry in the
predecessor repository's git history, still valid against this instance.
`service_role` bypasses RLS completely, so that key is a live master
credential for the data this import is reading. Removing a file from a
branch tip is not rotation. See `docs/security/SECRET_ROTATION_RUNBOOK.md`.
