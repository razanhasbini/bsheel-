BEGIN;

-- ===========================================================================
-- 1. admin_audit_log is append-only, enforced by the database
-- ===========================================================================
--
-- CLAUDE.md: "Sensitive admin actions append an immutable audit record."
-- Nothing enforced that. Since 0001 the table has carried a primary key and
-- two indexes and nothing else, so any connection could rewrite a row's
-- before_state or DELETE the record of a takedown, and the log would not show
-- that it had happened. An audit log an admin can silently edit is not
-- evidence of anything.
--
-- Why a trigger rather than table privileges. The API connects as the role
-- that owns this schema, and an owner is not restrained by its own table
-- privileges: after
--   REVOKE UPDATE, DELETE, TRUNCATE ON t FROM <owner>;
-- has_table_privilege(<owner>, 't', 'DELETE') still returns true and the
-- DELETE still succeeds, because ownership carries those rights implicitly
-- and GRANT/REVOKE only describe what the owner has handed to other roles.
-- Row-level security has the same hole -- the owner bypasses its own policies
-- unless the table is ALTERed to FORCE RLS -- which is why the legacy
-- system's deny-update/deny-delete RLS policies (its migration 0142, cited in
-- docs/security/SECURITY_REMEDIATION_2026_05_17.md as "tamper-proof audit
-- log") did not protect this table either. A BEFORE trigger runs for every
-- writer, owner included, so the trigger is the real guard. The REVOKE at the
-- end of this section is defence in depth for any future least-privilege or
-- read-only role, and it states the intent where \dp shows it.
--
-- It takes two triggers, not one: TRUNCATE does not fire row-level triggers,
-- so a BEFORE UPDATE OR DELETE ... FOR EACH ROW trigger on its own would
-- leave `TRUNCATE admin_audit_log` as an unguarded way to erase the entire
-- log. The statement-level BEFORE TRUNCATE trigger closes that.
--
-- What the application still needs works untouched: INSERT and SELECT are not
-- trigger events here, and every writer in backend/src (the admin repository
-- base, admin operations, quests, submissions, map and the Telegram
-- integration) only ever inserts.
--
-- The one remaining way out is ALTER TABLE ... DISABLE TRIGGER, which
-- requires ownership and is a deliberate DDL statement rather than a stray
-- UPDATE. That is the intended path for the retention policy
-- docs/PRIVACY_POLICY.md still leaves undefined; nothing in the application
-- can reach it by accident.

-- The actor foreign key has to go, and it is a defect in its own right rather
-- than a casualty of the trigger. ON DELETE SET NULL means deleting a user
-- REWRITES this table: PostgreSQL runs
--   UPDATE ONLY "public"."admin_audit_log" SET "actor_id" = NULL WHERE ...
-- on the deleter's behalf, so an account deletion silently erased who
-- performed every admin action that account had taken. Because that internal
-- statement is an ordinary UPDATE it also fires the trigger below, which
-- would make DELETE FROM users fail outright and break the account-deletion
-- job in src/infrastructure/messaging/domain-events.repository.ts.
--
-- The column keeps the uuid as recorded instead. docs/PRIVACY_POLICY.md
-- already says audit logs are kept, and once the users row is gone the id no
-- longer resolves to a name or an email; every reader of this table already
-- LEFT JOINs profiles and renders a missing actor as '(system)'.
ALTER TABLE admin_audit_log DROP CONSTRAINT admin_audit_log_actor_id_fkey;

CREATE FUNCTION admin_audit_log_append_only() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  -- restrict_violation (23001) rather than plpgsql's default P0001, so a
  -- caller sees an integrity-constraint class code for what is an integrity
  -- rule of the table. Nothing in the application catches it: no code path
  -- attempts either operation, and one that starts to should fail loudly.
  RAISE EXCEPTION 'admin_audit_log is append-only; % is not permitted', TG_OP
    USING ERRCODE = 'restrict_violation',
          HINT = 'Append a new audit row instead. Expiring history is ALTER TABLE admin_audit_log DISABLE TRIGGER, owner only.';
END;
$$;

CREATE TRIGGER admin_audit_log_append_only_rows
  BEFORE UPDATE OR DELETE ON admin_audit_log
  FOR EACH ROW EXECUTE FUNCTION admin_audit_log_append_only();

CREATE TRIGGER admin_audit_log_append_only_truncate
  BEFORE TRUNCATE ON admin_audit_log
  FOR EACH STATEMENT EXECUTE FUNCTION admin_audit_log_append_only();

REVOKE UPDATE, DELETE, TRUNCATE ON admin_audit_log FROM PUBLIC;

-- ===========================================================================
-- 2. quests.category is a closed set
-- ===========================================================================
--
-- 0001 bounded the length (1..80 characters) and nothing else, so category was
-- free text. A typo created a new de-facto category that no screen would ever
-- surface again, and every client switches on the value: QuestCategory in
-- packages/app_contracts/lib/statuses.dart calls itself "Quest category CHECK
-- constraint values" and apps/admin_web's quest_management_page.dart lists
-- "every category the CHECK constraint allows" -- a constraint that did not
-- exist.
--
-- The five below are the reconciled set, and the reconciliation needed no
-- decision: statuses.dart, the already-closed @IsIn on
-- SubmitQuestSuggestionDto, QUEST_CATEGORIES in the Telegram admin bot and
-- the admin panel's filter row all name the same five, and every one of the
-- 246 quests imported from the legacy database is a member.
--
-- Existing data, checked before writing this. Eleven of the local database's
-- thirty-two quests sat outside the set and all eleven were test debris:
-- eight 'e2e' rows from the integration harness (which hard-coded that
-- string), two 'creative' probes and one 'a6'. So no real quest is
-- reclassified here, but the statements below are written for a database
-- where one might be:
--
--   * case and whitespace are folded first, because 'Fitness ' is the same
--     category as 'fitness' and rejecting it would be pedantry;
--   * 'creative' folds into 'creativity' -- the same category under a
--     different spelling;
--   * anything still outside the set is a value nobody chose deliberately.
--     Dropping the row is not an option (attempts and submissions reference
--     it) and picking a category on its author's behalf is a guess, so the
--     row is parked in 'adventure' AND deactivated: that takes it out of the
--     random picker until a human recategorises it, while its history stays
--     intact. Each such row gets its own audit record, so the change is on
--     the record rather than in migration output nobody keeps.
UPDATE quests SET category = lower(btrim(category)), updated_at = now()
WHERE category <> lower(btrim(category));

UPDATE quests SET category = 'creativity', updated_at = now()
WHERE category = 'creative';

WITH quarantined AS (
  SELECT id, category, is_active FROM quests
  WHERE category NOT IN ('fitness', 'creativity', 'social', 'learning', 'adventure')
), recorded AS (
  -- A data-modifying CTE always executes, even unreferenced, and every CTE
  -- here sees the same snapshot -- so this records the pre-change values.
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, before_state, after_state)
  SELECT NULL, 'quest.category_quarantined', 'quest', id::text,
         jsonb_build_object('category', category, 'is_active', is_active),
         jsonb_build_object('category', 'adventure', 'is_active', false,
                            'reason', 'migration 0027 closed the quest category set')
  FROM quarantined
  RETURNING 1
)
UPDATE quests SET category = 'adventure', is_active = false, updated_at = now()
WHERE id IN (SELECT id FROM quarantined);

-- Reuses the constraint name from 0001: the closed set subsumes its 1..80
-- character bound, and keeping one constraint per column keeps the name
-- stable for anyone reading an error.
ALTER TABLE quests DROP CONSTRAINT quests_category_check;
ALTER TABLE quests ADD CONSTRAINT quests_category_check
  CHECK (category IN ('fitness', 'creativity', 'social', 'learning', 'adventure'));

-- quest_suggestions.category is copied verbatim into quests when an admin
-- approves a suggestion (admin-moderation.repository.ts), so leaving that
-- column open would turn an old suggestion row into a constraint violation --
-- a 500, since nothing maps 23514 to a status code -- on the approve path.
-- Its intake DTO has always been closed to the same five, and the local rows
-- are all members, but the same folding is applied for safety. There is no
-- is_active here to quarantine with, and rejecting a stranger's suggestion is
-- not a migration's call, so an unrecognised value is folded to 'adventure'
-- and recorded; an admin still reads the title and description before
-- approving.
UPDATE quest_suggestions SET category = lower(btrim(category))
WHERE category <> lower(btrim(category));

UPDATE quest_suggestions SET category = 'creativity' WHERE category = 'creative';

WITH quarantined AS (
  SELECT id, category FROM quest_suggestions
  WHERE category NOT IN ('fitness', 'creativity', 'social', 'learning', 'adventure')
), recorded AS (
  INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, before_state, after_state)
  SELECT NULL, 'quest_suggestion.category_quarantined', 'quest_suggestion', id::text,
         jsonb_build_object('category', category),
         jsonb_build_object('category', 'adventure',
                            'reason', 'migration 0027 closed the quest category set')
  FROM quarantined
  RETURNING 1
)
UPDATE quest_suggestions SET category = 'adventure'
WHERE id IN (SELECT id FROM quarantined);

ALTER TABLE quest_suggestions DROP CONSTRAINT quest_suggestions_category_check;
ALTER TABLE quest_suggestions ADD CONSTRAINT quest_suggestions_category_check
  CHECK (category IN ('fitness', 'creativity', 'social', 'learning', 'adventure'));

COMMIT;
