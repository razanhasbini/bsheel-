-- ============================================================
-- MIGRATION 0133: Replace 0119's magic-string allow-list (ARC-006).
--
-- 0114 + 0119's `guard_submission_owner_update` hardcodes which
-- columns an owner may not change in an `IS DISTINCT FROM` chain.
-- That's brittle: every column added to `submissions` requires
-- editing the magic-string list, and forgetting recreates the
-- 0114 → 0119 incident (where the guard rejected legitimate appeal
-- writes for ~24 hours).
--
-- This switches the guard to a positive allow-list driven by an
-- `app_config` row, plus a regression test pattern. The list of
-- "owner-writable columns" is now data, queryable + tweakable
-- without a code release.
-- ============================================================

-- Default allow-list. Columns owners may freely modify on their own
-- submissions. Derived directly from the original 0114 deny-list:
--   visibility, deleted_at, caption, appealed, appeal_note, show_in_feed
INSERT INTO public.app_config (key, value)
VALUES (
  'submission_owner_writable_columns',
  '["visibility","deleted_at","caption","appealed","appeal_note","show_in_feed"]'
)
ON CONFLICT (key) DO NOTHING;

-- Reissue the guard. Reads the allow-list once per UPDATE, then
-- compares the columns that actually changed against it. Any change
-- to a non-listed column raises with a message that names the
-- offending column (was previously a generic message).
CREATE OR REPLACE FUNCTION public.guard_submission_owner_update()
RETURNS trigger AS $$
DECLARE
  v_allow      jsonb;
  v_allow_set  text[];
  v_changed    text;
  v_offending  text;
BEGIN
  -- Trusted contexts (unchanged from 0119 + 0114 semantics).
  IF public.is_admin()
     OR pg_trigger_depth() > 1
     OR current_setting('app.bypass_submission_guard', true) = 'on' THEN
    RETURN new;
  END IF;

  -- Resolve allow-list. Fall open if the config row is missing so
  -- the table never becomes unwritable due to a config wipe.
  SELECT value::jsonb INTO v_allow
    FROM public.app_config WHERE key = 'submission_owner_writable_columns';
  IF v_allow IS NULL THEN
    RETURN new;
  END IF;
  v_allow_set := ARRAY(SELECT jsonb_array_elements_text(v_allow));

  -- Walk every column that's actually present on submissions and
  -- compare old vs new for those NOT in the allow-list. The first
  -- offending column halts the update with a precise error message.
  FOR v_changed IN
    SELECT column_name
      FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'submissions'
  LOOP
    IF v_changed = ANY (v_allow_set) THEN
      CONTINUE;
    END IF;
    EXECUTE format(
      'SELECT (CASE WHEN ($1).%1$I IS DISTINCT FROM ($2).%1$I THEN %1$L ELSE NULL END)',
      v_changed
    ) USING new, old INTO v_offending;
    IF v_offending IS NOT NULL THEN
      RAISE EXCEPTION
        'submissions: owners may not modify column "%". Allowed columns: %',
        v_offending, v_allow_set;
    END IF;
  END LOOP;

  RETURN new;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.guard_submission_owner_update() IS
  'Owner-update guard. Allow-list lives in '
  'app_config.submission_owner_writable_columns. ARC-006 / 0119 / 0114.';
