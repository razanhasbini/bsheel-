-- ============================================================
-- XP idempotency regression guard
--
-- Verifies migration 0054 stays intact: once a submission has
-- been approved and XP awarded, re-approving it (after a
-- reject → appeal → approve cycle, or any other path) must NOT
-- award XP a second time.
--
-- Run with: psql -f supabase/tests/xp_idempotency_test.sql
-- Wrapped in a transaction so nothing persists.
-- ============================================================

BEGIN;

-- Clean slate using deterministic UUIDs.
DO $$
DECLARE
  v_user_id uuid := '11111111-1111-1111-1111-111111111111';
  v_quest_id uuid := '22222222-2222-2222-2222-222222222222';
  v_user_quest_id uuid := '33333333-3333-3333-3333-333333333333';
  v_submission_id uuid := '44444444-4444-4444-4444-444444444444';
  v_starting_xp integer := 0;
  v_quest_xp integer := 50;
  v_xp_after_first_approval integer;
  v_xp_after_second_approval integer;
  v_quests_completed_after integer;
BEGIN
  -- Seed auth user, profile, quest, user_quest
  INSERT INTO auth.users (id, email) VALUES (v_user_id, 'xp-test@example.com')
    ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.profiles (id, username, xp, level, quests_completed)
    VALUES (v_user_id, 'xp_test_user', v_starting_xp, 1, 0);
  INSERT INTO public.quests (id, title, description, xp_reward, is_active)
    VALUES (v_quest_id, 'Test', 'Test quest', v_quest_xp, true);
  INSERT INTO public.user_quests (id, user_id, quest_id, status, expires_at)
    VALUES (v_user_quest_id, v_user_id, v_quest_id, 'submitted', now() + interval '1 hour');
  INSERT INTO public.submissions (id, user_quest_id, user_id, media_url, media_type, status)
    VALUES (v_submission_id, v_user_quest_id, v_user_id, 'https://x', 'image', 'pending');

  -- First approval → should award XP.
  UPDATE public.submissions SET status = 'approved' WHERE id = v_submission_id;
  SELECT xp INTO v_xp_after_first_approval FROM public.profiles WHERE id = v_user_id;

  IF v_xp_after_first_approval <> v_starting_xp + v_quest_xp THEN
    RAISE EXCEPTION 'FAIL: first approval did not award XP correctly. Expected %, got %',
      v_starting_xp + v_quest_xp, v_xp_after_first_approval;
  END IF;

  -- Reject, then re-approve → must NOT re-award.
  UPDATE public.submissions SET status = 'rejected' WHERE id = v_submission_id;
  UPDATE public.submissions SET status = 'approved' WHERE id = v_submission_id;
  SELECT xp, quests_completed
    INTO v_xp_after_second_approval, v_quests_completed_after
    FROM public.profiles WHERE id = v_user_id;

  IF v_xp_after_second_approval <> v_xp_after_first_approval THEN
    RAISE EXCEPTION 'FAIL: double-XP regression. Expected % after re-approval, got %',
      v_xp_after_first_approval, v_xp_after_second_approval;
  END IF;

  IF v_quests_completed_after <> 1 THEN
    RAISE EXCEPTION 'FAIL: quests_completed incremented more than once. Got %',
      v_quests_completed_after;
  END IF;

  RAISE NOTICE 'OK: XP idempotency holds. xp=% quests_completed=%',
    v_xp_after_second_approval, v_quests_completed_after;
END $$;

ROLLBACK;
