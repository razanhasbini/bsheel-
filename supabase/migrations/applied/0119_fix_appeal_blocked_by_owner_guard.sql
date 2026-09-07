-- ============================================================
-- MIGRATION 0119: Unblock the appeal flow.
--
-- 0114 added `guard_submission_owner_update`, a BEFORE-UPDATE
-- trigger that prevents non-admin owners from changing
-- `status`, `reviewed_by`, `review_note`, `reviewed_at`,
-- `submitted_at`, `media_*`, `xp_awarded`, `user_*`.
--
-- Problem: 0052's `appeal_submission()` is SECURITY DEFINER but
-- still updates the submission as the calling owner (auth.uid()
-- stays the same), so the guard fires and rejects the appeal —
-- the user sees "Failed to submit appeal: ... owners may only
-- modify visibility, deleted_at, caption, ...".
--
-- Fix: a transaction-local GUC, `app.bypass_submission_guard`,
-- that internal RPCs can flip to `on` to declare themselves
-- trusted callers. The trigger honours the flag the same way
-- it already honours `is_admin()` and `pg_trigger_depth() > 1`.
--
-- The flag is set with `set_config(..., true)` (the third arg
-- scopes it to the current transaction), so it cannot leak to
-- a later request even if the same connection is reused.
-- ============================================================

-- ── 1) Update the guard to recognise the bypass GUC ─────────────
CREATE OR REPLACE FUNCTION public.guard_submission_owner_update()
RETURNS trigger AS $$
BEGIN
  -- Trusted contexts:
  --   * admin caller
  --   * cascaded update from another trigger (e.g. 0110 XP revoke)
  --   * internal RPC that opted-in via set_config(..., true)
  IF public.is_admin()
     OR pg_trigger_depth() > 1
     OR current_setting('app.bypass_submission_guard', true) = 'on' THEN
    RETURN new;
  END IF;

  IF (new.status        IS DISTINCT FROM old.status)        OR
     (new.user_id       IS DISTINCT FROM old.user_id)       OR
     (new.user_quest_id IS DISTINCT FROM old.user_quest_id) OR
     (new.media_url     IS DISTINCT FROM old.media_url)     OR
     (new.media_type    IS DISTINCT FROM old.media_type)    OR
     (new.reviewed_by   IS DISTINCT FROM old.reviewed_by)   OR
     (new.review_note   IS DISTINCT FROM old.review_note)   OR
     (new.reviewed_at   IS DISTINCT FROM old.reviewed_at)   OR
     (new.submitted_at  IS DISTINCT FROM old.submitted_at)  OR
     (new.xp_awarded    IS DISTINCT FROM old.xp_awarded) THEN
    RAISE EXCEPTION
      'submissions: owners may only modify visibility, deleted_at, caption, appealed, appeal_note, show_in_feed';
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql;

-- ── 2) Reissue appeal_submission with the bypass flag ───────────
-- Same body as 0052 except for the set_config line at the top.
-- Re-using the original ownership / status / appealed checks so
-- a malicious caller can't abuse the bypass — the function still
-- only allows the strict "appeal a rejected submission you own,
-- once" transition before flipping the flag.
CREATE OR REPLACE FUNCTION public.appeal_submission(
  p_submission_id uuid,
  p_appeal_note text
)
RETURNS void AS $$
DECLARE
  v_submission RECORD;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id, user_id, status, appealed, user_quest_id
    INTO v_submission
    FROM public.submissions
    WHERE id = p_submission_id;

  IF v_submission IS NULL THEN
    RAISE EXCEPTION 'Submission not found';
  END IF;

  IF v_submission.user_id != auth.uid() THEN
    RAISE EXCEPTION 'Not your submission';
  END IF;

  IF v_submission.status != 'rejected' THEN
    RAISE EXCEPTION 'Only rejected submissions can be appealed';
  END IF;

  IF v_submission.appealed THEN
    RAISE EXCEPTION 'Already appealed';
  END IF;

  -- Open the trapdoor for the duration of this transaction only.
  PERFORM set_config('app.bypass_submission_guard', 'on', true);

  UPDATE public.submissions
    SET status = 'pending',
        appeal_note = p_appeal_note,
        appealed = true,
        reviewed_by = NULL,
        review_note = NULL,
        reviewed_at = NULL
    WHERE id = p_submission_id;

  UPDATE public.user_quests
    SET status = 'submitted'
    WHERE id = v_submission.user_quest_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
