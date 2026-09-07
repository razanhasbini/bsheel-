-- ============================================================
-- MIGRATION 0036: New notification types and DB-level triggers
-- Adds: quest_expired, level_up (in trigger), follow_quest_completed,
--       reaction_milestone, new_submission, appeal_submitted,
--       leaderboard_overtaken, top_10_entry
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. Quest expired notification
--    Extend expire_overdue_quests to notify quest owners.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_overdue_quests()
RETURNS void AS $$
DECLARE
  v_rec RECORD;
BEGIN
  -- Allow if called by an authenticated user OR by service_role (cron job).
  IF auth.uid() IS NULL AND current_setting('role', true) != 'service_role' THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Collect quests being expired so we can notify owners.
  FOR v_rec IN
    SELECT uq.id AS user_quest_id, uq.user_id
    FROM public.user_quests uq
    WHERE uq.status = 'assigned'
      AND uq.expires_at < now()
  LOOP
    -- Expire the quest
    UPDATE public.user_quests
      SET status = 'expired'
      WHERE id = v_rec.user_quest_id;

    -- Notify the quest owner
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_rec.user_id,
      'Quest Expired',
      'Your quest has expired. Generate a new one!',
      'quest_expired',
      v_rec.user_quest_id::text
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─────────────────────────────────────────────────────────────
-- 2. Level-up notification in handle_submission_approved trigger.
--    Replace the existing trigger function to also fire level_up
--    when the approval causes a level change.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_submission_approved()
RETURNS trigger AS $$
DECLARE
  quest_xp   integer;
  v_old_level integer;
  v_new_level integer;
BEGIN
  -- ── Approval ────────────────────────────────────────────────
  IF new.status = 'approved' AND (old.status IS NULL OR old.status != 'approved') THEN
    -- Update user_quest
    UPDATE public.user_quests
      SET status = 'approved', completed_at = now()
      WHERE id = new.user_quest_id;

    -- Get XP reward
    SELECT q.xp_reward INTO quest_xp
      FROM public.quests q
      JOIN public.user_quests uq ON uq.quest_id = q.id
      WHERE uq.id = new.user_quest_id;

    -- Capture old level before XP award
    SELECT level INTO v_old_level
      FROM public.profiles
      WHERE id = new.user_id;

    -- Award XP and increment quests_completed
    UPDATE public.profiles
      SET xp                = xp + coalesce(quest_xp, 10),
          quests_completed  = quests_completed + 1,
          level             = greatest(1, (xp + coalesce(quest_xp, 10)) / 100 + 1)
      WHERE id = new.user_id;

    -- Read new level after update
    SELECT level INTO v_new_level
      FROM public.profiles
      WHERE id = new.user_id;

    -- Approval notification
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      new.user_id,
      'Submission Approved!',
      'Your submission was approved! +' || coalesce(quest_xp, 10) || ' XP',
      'submission_approved',
      new.id::text
    );

    -- Level-up notification (if level increased)
    IF v_new_level > v_old_level THEN
      INSERT INTO public.notifications (user_id, title, body, type)
      VALUES (
        new.user_id,
        'Level Up! 🎮',
        'You reached Level ' || v_new_level || '!',
        'level_up'
      );
    END IF;
  END IF;

  -- ── Rejection ───────────────────────────────────────────────
  IF new.status = 'rejected' AND (old.status IS NULL OR old.status != 'rejected') THEN
    UPDATE public.user_quests
      SET status = 'rejected'
      WHERE id = new.user_quest_id;

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      new.user_id,
      'Submission Rejected',
      coalesce('Reason: ' || new.review_note, 'Your submission was not approved. Try again!'),
      'submission_rejected',
      new.id::text
    );
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─────────────────────────────────────────────────────────────
-- 3. Follower completes quest notification
--    Trigger: submissions AFTER UPDATE when status → 'approved'
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_follow_quest_completed()
RETURNS trigger AS $$
DECLARE
  v_submitter_name text;
  v_follower       RECORD;
BEGIN
  IF new.status = 'approved' AND (old.status IS NULL OR old.status != 'approved') THEN
    -- Get submitter display name
    SELECT coalesce(display_name, username, 'Someone')
      INTO v_submitter_name
      FROM public.profiles
      WHERE id = new.user_id;

    -- Notify each follower (max 100, skip submitter)
    FOR v_follower IN
      SELECT follower_id
      FROM public.follows
      WHERE following_id = new.user_id
        AND follower_id  != new.user_id
      LIMIT 100
    LOOP
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_follower.follower_id,
        v_submitter_name || ' completed a quest!',
        'Check out their post',
        'follow_quest_completed',
        new.id::text
      );
    END LOOP;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_follow_quest_completed ON public.submissions;
CREATE TRIGGER on_follow_quest_completed
  AFTER UPDATE OF status ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION public.handle_follow_quest_completed();

-- ─────────────────────────────────────────────────────────────
-- 4. Reaction milestone notification
--    Trigger: reactions AFTER INSERT
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_reaction_milestone()
RETURNS trigger AS $$
DECLARE
  v_total_reactions integer;
  v_owner_id        uuid;
BEGIN
  -- Count total reactions for this submission
  SELECT COUNT(*) INTO v_total_reactions
    FROM public.reactions
    WHERE submission_id = new.submission_id;

  -- Only fire on exact milestone counts
  IF v_total_reactions IN (10, 25, 50) THEN
    -- Get submission owner
    SELECT user_id INTO v_owner_id
      FROM public.submissions
      WHERE id = new.submission_id;

    -- Don't notify if reactor is the owner
    IF v_owner_id IS NOT NULL AND v_owner_id != new.user_id THEN
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_owner_id,
        '🔥 Your post is on fire!',
        v_total_reactions || ' people reacted to your quest post',
        'reaction_milestone',
        new.submission_id::text
      );
    END IF;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_reaction_milestone ON public.reactions;
CREATE TRIGGER on_reaction_milestone
  AFTER INSERT ON public.reactions
  FOR EACH ROW EXECUTE FUNCTION public.handle_reaction_milestone();

-- ─────────────────────────────────────────────────────────────
-- 5 & 6. New submission + appeal/resubmission for admins
--    Trigger: submissions AFTER INSERT OR UPDATE
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_submission_admin_notify()
RETURNS trigger AS $$
DECLARE
  v_submitter_name text;
  v_admin          RECORD;
BEGIN
  -- Get submitter name
  SELECT coalesce(display_name, username, 'Someone')
    INTO v_submitter_name
    FROM public.profiles
    WHERE id = new.user_id;

  -- 5. New submission (INSERT) → notify all admins
  IF TG_OP = 'INSERT' THEN
    FOR v_admin IN
      SELECT user_id FROM public.admins
    LOOP
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_admin.user_id,
        'New Submission',
        v_submitter_name || ' submitted proof for review',
        'new_submission',
        new.id::text
      );
    END LOOP;
  END IF;

  -- 6. Appeal/resubmission: status changes from 'rejected' → 'submitted'
  IF TG_OP = 'UPDATE'
     AND old.status = 'rejected'
     AND new.status = 'submitted' THEN
    FOR v_admin IN
      SELECT user_id FROM public.admins
    LOOP
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_admin.user_id,
        'Appeal Submitted',
        v_submitter_name || ' resubmitted after rejection',
        'appeal_submitted',
        new.id::text
      );
    END LOOP;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_submission_admin_notify ON public.submissions;
CREATE TRIGGER on_submission_admin_notify
  AFTER INSERT OR UPDATE OF status ON public.submissions
  FOR EACH ROW EXECUTE FUNCTION public.handle_submission_admin_notify();

-- ─────────────────────────────────────────────────────────────
-- 7 & 8. Leaderboard overtaken + Top 10 entry
--    Trigger: profiles AFTER UPDATE when level or xp increases
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_leaderboard_change()
RETURNS trigger AS $$
DECLARE
  v_old_rank    bigint;
  v_new_rank    bigint;
  v_passed_user RECORD;
  v_user_name   text;
BEGIN
  -- Only run when xp or level actually increases
  IF new.xp <= old.xp AND new.level <= old.level THEN
    RETURN new;
  END IF;

  -- Compute old rank: number of users who had strictly more xp before
  SELECT COUNT(*) + 1 INTO v_old_rank
    FROM public.profiles
    WHERE id != new.id
      AND xp > old.xp;

  -- Compute new rank: number of users who now have strictly more xp
  SELECT COUNT(*) + 1 INTO v_new_rank
    FROM public.profiles
    WHERE id != new.id
      AND xp > new.xp;

  -- 8. Top 10 entry: was outside top 10, now inside
  IF v_new_rank <= 10 AND v_old_rank > 10 THEN
    INSERT INTO public.notifications (user_id, title, body, type)
    VALUES (
      new.id,
      '🏆 You''re in the Top 10!',
      'You''ve entered the top 10 on the leaderboard!',
      'top_10_entry'
    );
  END IF;

  -- 7. Leaderboard overtaken: notify the user(s) this user just passed
  --    These are users whose xp was between old.xp and new.xp (exclusive of new.xp).
  IF v_new_rank < v_old_rank THEN
    SELECT coalesce(display_name, username, 'Someone')
      INTO v_user_name
      FROM public.profiles
      WHERE id = new.id;

    FOR v_passed_user IN
      SELECT id
      FROM public.profiles
      WHERE id != new.id
        AND xp >= new.xp   -- they now tie or are equal (pushed down)
        AND xp < old.xp    -- they were above the updater before
      LIMIT 20             -- safety cap
    LOOP
      INSERT INTO public.notifications (user_id, title, body, type)
      VALUES (
        v_passed_user.id,
        'You''ve been overtaken!',
        v_user_name || ' just passed you on the leaderboard',
        'leaderboard_overtaken'
      );
    END LOOP;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_leaderboard_change ON public.profiles;
CREATE TRIGGER on_leaderboard_change
  AFTER UPDATE OF xp, level ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_leaderboard_change();

-- ─────────────────────────────────────────────────────────────
-- First Quest Welcome Notification
--    Replace assign_random_quest and assign_specific_quest
--    to detect first-ever quest and send a welcome message.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.assign_random_quest(p_user_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_quest_id       uuid;
  v_duration_hours integer;
  v_result         public.user_quests;
  v_quest_count    integer;
  v_notif_title    text;
  v_notif_body     text;
BEGIN
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Expire overdue assigned quests (without notification — expire_overdue_quests handles that via cron)
  UPDATE public.user_quests
    SET status = 'expired'
    WHERE user_id = p_user_id
      AND status = 'assigned'
      AND expires_at IS NOT NULL
      AND expires_at < now();

  IF EXISTS (
    SELECT 1 FROM public.user_quests
    WHERE user_id = p_user_id AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'User already has an active quest';
  END IF;

  SELECT id, coalesce(duration_hours, 4)
    INTO v_quest_id, v_duration_hours
    FROM public.quests
    WHERE is_active = true
      AND id NOT IN (
        SELECT quest_id FROM public.user_quests
        WHERE user_id = p_user_id
          AND status = 'approved'
          AND completed_at > now() - interval '7 days'
      )
    ORDER BY random()
    LIMIT 1;

  IF v_quest_id IS NULL THEN
    RAISE EXCEPTION 'No available quests';
  END IF;

  INSERT INTO public.user_quests (user_id, quest_id, expires_at)
  VALUES (
    p_user_id,
    v_quest_id,
    now() + make_interval(hours => v_duration_hours)
  )
  RETURNING * INTO v_result;

  -- Count all quests this user has ever had (including this new one)
  SELECT COUNT(*) INTO v_quest_count
    FROM public.user_quests
    WHERE user_id = p_user_id;

  IF v_quest_count = 1 THEN
    v_notif_title := 'Welcome! Your first quest is ready 🚀';
    v_notif_body  := 'Your first quest is live! Complete it within ' ||
                     CASE WHEN v_duration_hours = 1 THEN '1 hour'
                          ELSE v_duration_hours::text || ' hours'
                     END || ' and earn XP!';
  ELSE
    v_notif_title := 'New Quest!';
    v_notif_body  := format(
      'You have a new quest! Complete it within %s.',
      CASE WHEN v_duration_hours = 1 THEN '1 hour'
           ELSE v_duration_hours::text || ' hours'
      END
    );
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (p_user_id, v_notif_title, v_notif_body, 'quest_assigned', v_result.id::text);

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.assign_specific_quest(p_user_id uuid, p_quest_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_duration_hours integer;
  v_result         public.user_quests;
  v_quest_count    integer;
  v_notif_title    text;
  v_notif_body     text;
BEGIN
  IF auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.user_quests
    SET status = 'expired'
    WHERE user_id = p_user_id
      AND status = 'assigned'
      AND expires_at IS NOT NULL
      AND expires_at < now();

  IF EXISTS (
    SELECT 1 FROM public.user_quests
    WHERE user_id = p_user_id AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'User already has an active quest';
  END IF;

  SELECT coalesce(duration_hours, 4)
    INTO v_duration_hours
    FROM public.quests
    WHERE id = p_quest_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quest not found or inactive';
  END IF;

  INSERT INTO public.user_quests (user_id, quest_id, expires_at)
  VALUES (
    p_user_id,
    p_quest_id,
    now() + make_interval(hours => v_duration_hours)
  )
  RETURNING * INTO v_result;

  -- Count all quests this user has ever had (including this new one)
  SELECT COUNT(*) INTO v_quest_count
    FROM public.user_quests
    WHERE user_id = p_user_id;

  IF v_quest_count = 1 THEN
    v_notif_title := 'Welcome! Your first quest is ready 🚀';
    v_notif_body  := 'Your first quest is live! Complete it within ' ||
                     CASE WHEN v_duration_hours = 1 THEN '1 hour'
                          ELSE v_duration_hours::text || ' hours'
                     END || ' and earn XP!';
  ELSE
    v_notif_title := 'New Quest!';
    v_notif_body  := format(
      'You have a new quest! Complete it within %s.',
      CASE WHEN v_duration_hours = 1 THEN '1 hour'
           ELSE v_duration_hours::text || ' hours'
      END
    );
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (p_user_id, v_notif_title, v_notif_body, 'quest_assigned', v_result.id::text);

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
