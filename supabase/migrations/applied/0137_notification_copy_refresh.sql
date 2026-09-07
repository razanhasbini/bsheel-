-- ============================================================
-- MIGRATION 0137: Notification copy refresh.
--
-- Rewrites every server-side notification's title + body to the
-- new BSHEEL voice. Behaviour, gating, RLS, and trigger semantics
-- are preserved verbatim from the latest definition of each
-- function — only the literal strings change.
--
-- Companion change on the client: `sendNotificationToUser` callsites
-- in mobile_app (follow, new_comment, comment_reply, mention) were
-- updated in the same commit. Admin "ANNOUNCEMENTS" broadcasts are
-- composed manually in the admin web and intentionally untouched.
--
-- New copy decisions worth flagging:
--   * Quest assigned (not first): rotates over 3 body variants per
--     call (random) so users don't get the same line every time.
--   * Reaction milestone: distinct title/body per 10/25/50 tier.
--   * level_up notification is RE-INTRODUCED here. It existed in
--     0036 but was dropped when 0113 consolidated the approval
--     trigger. Now back: fires only when the post-update level is
--     strictly greater than the pre-update level.
-- ============================================================

-- ── Quest: assign_random_quest ──────────────────────────────
-- Latest body from 0109; restoring first-quest detection (count=1)
-- which 0109 dropped, plus rotating body variants for subsequent.
CREATE OR REPLACE FUNCTION public.assign_random_quest(p_user_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_quest_id       uuid;
  v_duration_hours integer;
  v_result         public.user_quests;
  v_quest_count    integer;
  v_dur_str        text;
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
    SELECT 1
    FROM public.user_quests
    WHERE user_id = p_user_id
      AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'User already has an active quest';
  END IF;

  SELECT q.id, COALESCE(q.duration_hours, 4)
    INTO v_quest_id, v_duration_hours
    FROM public.quests q
    WHERE q.is_active = true
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_quests uq
        WHERE uq.user_id = p_user_id
          AND uq.quest_id = q.id
          AND uq.status IN ('submitted', 'approved')
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.admin_quest_injections i
        WHERE i.quest_id = q.id
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

  v_dur_str := CASE WHEN v_duration_hours = 1 THEN '1 hour'
                    ELSE v_duration_hours::text || ' hours'
               END;

  SELECT COUNT(*) INTO v_quest_count
    FROM public.user_quests
    WHERE user_id = p_user_id;

  IF v_quest_count = 1 THEN
    v_notif_title := 'Your adventure begins. ⚔️';
    v_notif_body  := 'First quest unlocked. Finish it in ' || v_dur_str ||
                     ' and the XP is yours.';
  ELSE
    v_notif_title := 'New quest just dropped.';
    v_notif_body  := CASE floor(random() * 3)::int
      WHEN 0 THEN 'Tap in. ' || v_dur_str || ' on the clock. ⏳'
      WHEN 1 THEN 'A fresh quest landed in your lap. ' || v_dur_str ||
                  ' to make it count.'
      ELSE 'Real life called. It assigned you something. ' || v_dur_str ||
           ' to deliver.'
    END;
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (
    p_user_id,
    v_notif_title,
    v_notif_body,
    'quest_assigned',
    v_result.id::text
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Quest: assign_specific_quest ────────────────────────────
CREATE OR REPLACE FUNCTION public.assign_specific_quest(p_user_id uuid, p_quest_id uuid)
RETURNS public.user_quests AS $$
DECLARE
  v_duration_hours integer;
  v_result         public.user_quests;
  v_quest_count    integer;
  v_dur_str        text;
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
    SELECT 1
    FROM public.user_quests
    WHERE user_id = p_user_id
      AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'User already has an active quest';
  END IF;

  SELECT COALESCE(duration_hours, 4)
    INTO v_duration_hours
    FROM public.quests
    WHERE id = p_quest_id
      AND is_active = true;

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

  UPDATE public.admin_quest_injections
    SET consumed_at = now()
    WHERE target_user_id = p_user_id
      AND quest_id = p_quest_id
      AND consumed_at IS NULL;

  v_dur_str := CASE WHEN v_duration_hours = 1 THEN '1 hour'
                    ELSE v_duration_hours::text || ' hours'
               END;

  SELECT COUNT(*) INTO v_quest_count
    FROM public.user_quests
    WHERE user_id = p_user_id;

  IF v_quest_count = 1 THEN
    v_notif_title := 'Your adventure begins. ⚔️';
    v_notif_body  := 'First quest unlocked. Finish it in ' || v_dur_str ||
                     ' and the XP is yours.';
  ELSE
    v_notif_title := 'New quest just dropped.';
    v_notif_body  := CASE floor(random() * 3)::int
      WHEN 0 THEN 'Tap in. ' || v_dur_str || ' on the clock. ⏳'
      WHEN 1 THEN 'A fresh quest landed in your lap. ' || v_dur_str ||
                  ' to make it count.'
      ELSE 'Real life called. It assigned you something. ' || v_dur_str ||
           ' to deliver.'
    END;
  END IF;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  VALUES (
    p_user_id,
    v_notif_title,
    v_notif_body,
    'quest_assigned',
    v_result.id::text
  );

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Quest: expire_overdue_quests (cron) ─────────────────────
CREATE OR REPLACE FUNCTION public.expire_overdue_quests()
RETURNS void AS $$
DECLARE
  v_rec RECORD;
BEGIN
  IF auth.uid() IS NULL AND current_setting('role', true) != 'service_role' THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  FOR v_rec IN
    SELECT uq.id AS user_quest_id, uq.user_id
    FROM public.user_quests uq
    WHERE uq.status = 'assigned'
      AND uq.expires_at < now()
  LOOP
    UPDATE public.user_quests
      SET status = 'expired'
      WHERE id = v_rec.user_quest_id;

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_rec.user_id,
      'Quest gone. Poof. 💨',
      'Time ran out. Pull a new one and try again. No streak shame here.',
      'quest_expired',
      v_rec.user_quest_id::text
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Quest: send_quest_timer_warnings (cron, 30-min band) ────
CREATE OR REPLACE FUNCTION public.send_quest_timer_warnings()
RETURNS void AS $$
DECLARE
  v_rec RECORD;
BEGIN
  FOR v_rec IN
    SELECT uq.id AS user_quest_id, uq.user_id
    FROM public.user_quests uq
    WHERE uq.status = 'assigned'
      AND uq.expires_at BETWEEN now() + interval '25 minutes'
                            AND now() + interval '35 minutes'
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.user_id      = uq.user_id
          AND n.type         = 'quest_timer_warning'
          AND n.reference_id = uq.id::text
      )
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      v_rec.user_id,
      '⏰ 30 minutes. That''s it.',
      'Your quest is about to peace out. Move.',
      'quest_timer_warning',
      v_rec.user_quest_id::text
    );
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Submissions: handle_submission_approved (approve/reject/level_up) ──
-- Latest body from 0113. Re-introduces level_up notification.
CREATE OR REPLACE FUNCTION public.handle_submission_approved()
RETURNS trigger AS $$
DECLARE
  quest_xp    integer;
  v_old_level integer;
  v_new_level integer;
BEGIN
  IF new.status = 'approved' AND (old.status IS NULL OR old.status != 'approved') THEN
    IF new.xp_awarded THEN
      RETURN new;
    END IF;

    UPDATE public.user_quests
       SET status = 'approved', completed_at = now()
     WHERE id = new.user_quest_id;

    SELECT q.xp_reward INTO quest_xp
      FROM public.quests q
      JOIN public.user_quests uq ON uq.quest_id = q.id
     WHERE uq.id = new.user_quest_id;

    SELECT level INTO v_old_level
      FROM public.profiles WHERE id = new.user_id;

    UPDATE public.profiles
       SET xp = xp + COALESCE(quest_xp, 10),
           quests_completed = quests_completed + 1,
           level = GREATEST(1, (xp + COALESCE(quest_xp, 10)) / 100 + 1)
     WHERE id = new.user_id
    RETURNING level INTO v_new_level;

    UPDATE public.submissions
       SET xp_awarded = true
     WHERE id = new.id;

    INSERT INTO public.notifications (user_id, title, body, type, reference_id)
    VALUES (
      new.user_id,
      'Approved. Respect. ✅',
      '+' || COALESCE(quest_xp, 10) ||
        ' XP added to your name. Keep cooking.',
      'submission_approved',
      new.id::text
    );

    -- level_up: only when the level actually increased.
    IF v_new_level IS NOT NULL
       AND v_old_level IS NOT NULL
       AND v_new_level > v_old_level THEN
      INSERT INTO public.notifications (user_id, title, body, type)
      VALUES (
        new.user_id,
        'Level ' || v_new_level || '. Look at you. 🎮',
        'You levelled up in real life. That''s not a thing most apps can say.',
        'level_up'
      );
    END IF;
  END IF;

  IF new.status = 'rejected' AND (old.status IS NULL OR old.status != 'rejected') THEN
    UPDATE public.user_quests
       SET status = 'rejected'
     WHERE id = new.user_quest_id;

    IF new.visibility = 'deleted' THEN
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        new.user_id,
        'Quest rejected. We took the post down.',
        'Mods pulled the post and rolled back the XP. No drama. The quest is yours again whenever you want it.',
        'submission_rejected',
        new.id::text
      );
    ELSE
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        new.user_id,
        'Quest rejected. Try again. 🔁',
        COALESCE(
          new.review_note,
          'The judges weren''t convinced this round. Take another swing. Same quest, fresh shot.'
        ),
        'submission_rejected',
        new.id::text
      );
    END IF;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: handle_submission_admin_notify (new + appeal) ────
-- Latest body from 0051. Trigger fires on rejected→pending for the
-- appeal branch (that's the appeal flow's status transition).
CREATE OR REPLACE FUNCTION public.handle_submission_admin_notify()
RETURNS trigger AS $$
DECLARE
  v_admin RECORD;
  v_submitter_name text;
BEGIN
  SELECT coalesce(display_name, username, 'Someone')
    INTO v_submitter_name
    FROM public.profiles
    WHERE id = new.user_id;

  IF TG_OP = 'INSERT' THEN
    FOR v_admin IN SELECT user_id FROM public.admins LOOP
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_admin.user_id,
        'Inbox: ' || v_submitter_name || ' sent proof. 📥',
        'New submission waiting on a verdict.',
        'new_submission',
        new.id::text
      );
    END LOOP;
  END IF;

  IF TG_OP = 'UPDATE'
     AND old.status = 'rejected'
     AND new.status = 'pending' THEN
    FOR v_admin IN SELECT user_id FROM public.admins LOOP
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_admin.user_id,
        v_submitter_name || ' is back for round two. 🔁',
        'Resubmitted after rejection. Fresh eyes needed.',
        'appeal_submitted',
        new.id::text
      );
    END LOOP;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Social: follow_quest_completed ──────────────────────────
CREATE OR REPLACE FUNCTION public.handle_follow_quest_completed()
RETURNS trigger AS $$
DECLARE
  v_submitter_name text;
  v_follower       RECORD;
BEGIN
  IF new.status = 'approved' AND (old.status IS NULL OR old.status != 'approved') THEN
    SELECT coalesce(display_name, username, 'Someone')
      INTO v_submitter_name
      FROM public.profiles
      WHERE id = new.user_id;

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
        v_submitter_name || ' just pulled it off.',
        'Quest cleared. Go gas them up. 🙌',
        'follow_quest_completed',
        new.id::text
      );
    END LOOP;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Reactions: handle_reaction_created (single vote) ────────
-- Latest body from 0103.
CREATE OR REPLACE FUNCTION public.handle_reaction_created()
RETURNS trigger AS $$
DECLARE
  v_submitter_id uuid;
  v_reactor_name text;
BEGIN
  SELECT s.user_id INTO v_submitter_id
    FROM public.submissions s
   WHERE s.id = NEW.submission_id;

  IF v_submitter_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT coalesce(display_name, username, 'Someone') INTO v_reactor_name
    FROM public.profiles
   WHERE id = NEW.user_id;

  INSERT INTO public.notifications (
    user_id, title, body, type, reference_id, actor_id
  )
  VALUES (
    v_submitter_id,
    v_reactor_name || ' just reacted. 🗳️',
    'Someone has thoughts about your quest. Go see.',
    'reaction_received',
    NEW.submission_id,
    NEW.user_id
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Reactions: handle_reaction_milestone (10 / 25 / 50) ────
CREATE OR REPLACE FUNCTION public.handle_reaction_milestone()
RETURNS trigger AS $$
DECLARE
  v_total_reactions integer;
  v_owner_id        uuid;
  v_title           text;
  v_body            text;
BEGIN
  SELECT COUNT(*) INTO v_total_reactions
    FROM public.reactions
    WHERE submission_id = new.submission_id;

  IF v_total_reactions IN (10, 25, 50) THEN
    SELECT user_id INTO v_owner_id
      FROM public.submissions
      WHERE id = new.submission_id;

    IF v_owner_id IS NOT NULL AND v_owner_id != new.user_id THEN
      IF v_total_reactions = 10 THEN
        v_title := '10 reactions and counting. 🔥';
        v_body  := 'Your post is doing numbers. Keep posting like this.';
      ELSIF v_total_reactions = 25 THEN
        v_title := '25 reactions. The squad sees you. 👀';
        v_body  := 'This one''s hitting. Go take a bow.';
      ELSE
        v_title := '50 reactions. You broke containment. 🚀';
        v_body  := 'Half a hundred people hit react. Your post is officially a moment.';
      END IF;

      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_owner_id,
        v_title,
        v_body,
        'reaction_milestone',
        new.submission_id::text
      );
    END IF;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Leaderboard: handle_leaderboard_change (top10 + overtaken) ─
CREATE OR REPLACE FUNCTION public.handle_leaderboard_change()
RETURNS trigger AS $$
DECLARE
  v_old_rank    bigint;
  v_new_rank    bigint;
  v_passed_user RECORD;
  v_user_name   text;
BEGIN
  IF new.xp <= old.xp AND new.level <= old.level THEN
    RETURN new;
  END IF;

  SELECT COUNT(*) + 1 INTO v_old_rank
    FROM public.profiles
    WHERE id != new.id
      AND xp > old.xp;

  SELECT COUNT(*) + 1 INTO v_new_rank
    FROM public.profiles
    WHERE id != new.id
      AND xp > new.xp;

  IF v_new_rank <= 10 AND v_old_rank > 10 THEN
    INSERT INTO public.notifications (user_id, title, body, type)
    VALUES (
      new.id,
      'Top 10. Welcome to the front page. 🏆',
      'You climbed into the top 10 on the leaderboard. Don''t get comfortable.',
      'top_10_entry'
    );
  END IF;

  IF v_new_rank < v_old_rank THEN
    SELECT coalesce(display_name, username, 'Someone')
      INTO v_user_name
      FROM public.profiles
      WHERE id = new.id;

    FOR v_passed_user IN
      SELECT id
      FROM public.profiles
      WHERE id != new.id
        AND xp >= new.xp
        AND xp < old.xp
      LIMIT 20
    LOOP
      INSERT INTO public.notifications (user_id, title, body, type)
      VALUES (
        v_passed_user.id,
        v_user_name || ' just pulled ahead of you. 😤',
        'They climbed past you on the leaderboard. Your move.',
        'leaderboard_overtaken'
      );
    END LOOP;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Collab: join_collab_group (RPC) ─────────────────────────
-- Latest body from 0096. Only the embedded notification copy is changed.
CREATE OR REPLACE FUNCTION public.join_collab_group(p_code text)
RETURNS json AS $$
DECLARE
  v_group         public.collab_groups;
  v_member_count  int;
  v_new_uq_id     uuid;
  v_joiner_name   text;
BEGIN
  SELECT * INTO v_group FROM public.collab_groups
    WHERE code = upper(p_code) AND status = 'open' AND expires_at > now()
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Group not found or expired';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.collab_group_members
    WHERE group_id = v_group.id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'You are already in this group';
  END IF;

  SELECT count(*) INTO v_member_count
    FROM public.collab_group_members WHERE group_id = v_group.id;
  IF v_member_count >= v_group.max_members THEN
    RAISE EXCEPTION 'Group is full (%/% members)', v_member_count, v_group.max_members;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_quests
    WHERE user_id = auth.uid() AND status = 'assigned'
  ) THEN
    RAISE EXCEPTION 'You already have an active quest. Abandon it first.';
  END IF;

  INSERT INTO public.user_quests (user_id, quest_id, status, assigned_at, expires_at)
  VALUES (auth.uid(), v_group.quest_id, 'assigned', now(), v_group.expires_at)
  RETURNING id INTO v_new_uq_id;

  INSERT INTO public.collab_group_members (group_id, user_id, user_quest_id)
  VALUES (v_group.id, auth.uid(), v_new_uq_id);

  IF v_member_count + 1 >= v_group.max_members THEN
    UPDATE public.collab_groups SET status = 'closed' WHERE id = v_group.id;
  END IF;

  SELECT COALESCE(display_name, username, 'Someone') INTO v_joiner_name
    FROM public.profiles WHERE id = auth.uid();

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  SELECT m.user_id,
         v_joiner_name || ' signed up for the mission. 🤝',
         'You''ve got a teammate on this one. Go win it together.',
         'collab_joined',
         v_group.id::text
  FROM public.collab_group_members m
  WHERE m.group_id = v_group.id AND m.user_id != auth.uid();

  RETURN json_build_object(
    'group_id',      v_group.id,
    'user_quest_id', v_new_uq_id,
    'quest_id',      v_group.quest_id,
    'expires_at',    v_group.expires_at,
    'mode',          v_group.mode
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.join_collab_group(text) TO authenticated;

-- ── Collab: notify_collab_group_on_approval ─────────────────
CREATE OR REPLACE FUNCTION public.notify_collab_group_on_approval()
RETURNS trigger AS $$
DECLARE
  v_group_id      uuid;
  v_approver_name text;
BEGIN
  IF NEW.status != 'approved' OR OLD.status != 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT m.group_id INTO v_group_id
    FROM public.collab_group_members m
    WHERE m.user_quest_id = NEW.user_quest_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(display_name, username, 'Someone') INTO v_approver_name
    FROM public.profiles WHERE id = NEW.user_id;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  SELECT m.user_id,
         v_approver_name || ' delivered. ✅',
         'Your teammate''s proof got approved. The squad eats good tonight.',
         'collab_partner_approved',
         NEW.id::text
  FROM public.collab_group_members m
  WHERE m.group_id = v_group_id AND m.user_id != NEW.user_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Admin: send_pending_review_reminders (cron, hourly) ─────
CREATE OR REPLACE FUNCTION public.send_pending_review_reminders()
RETURNS void AS $$
DECLARE
  v_pending_count integer;
  v_admin         RECORD;
BEGIN
  SELECT COUNT(*) INTO v_pending_count
    FROM public.submissions
    WHERE status = 'pending'
      AND created_at < now() - interval '24 hours';

  IF v_pending_count = 0 THEN
    RETURN;
  END IF;

  FOR v_admin IN SELECT user_id FROM public.admins LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.notifications
      WHERE user_id    = v_admin.user_id
        AND type       = 'pending_review_reminder'
        AND created_at > now() - interval '24 hours'
    ) THEN
      INSERT INTO public.notifications (user_id, title, body, type)
      VALUES (
        v_admin.user_id,
        '⚠️ ' || v_pending_count || ' submissions are getting stale.',
        'These have been sitting in the queue for over 24 hours. Time to triage.',
        'pending_review_reminder'
      );
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Moderation: report_content ──────────────────────────────
-- Latest body from 0069. The 0120 rate-check trigger is unaffected.
CREATE OR REPLACE FUNCTION public.report_content(
  p_reported_type text,
  p_reported_id   text,
  p_reason        text
)
RETURNS uuid AS $$
DECLARE
  v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.reports
    WHERE reporter_id   = auth.uid()
      AND reported_type = p_reported_type
      AND reported_id   = p_reported_id
      AND status        = 'pending'
  ) THEN
    RAISE EXCEPTION 'You have already reported this content';
  END IF;

  INSERT INTO public.reports (reporter_id, reported_type, reported_id, reason)
  VALUES (auth.uid(), p_reported_type, p_reported_id, p_reason)
  RETURNING id INTO v_id;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  SELECT a.user_id,
         '🚩 Report filed on ' || p_reported_type || '.',
         'Reason: "' || left(p_reason, 100) || '"',
         'content_report',
         v_id::text
  FROM public.admins a;

  RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── Moderation: block_user ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.block_user(
  p_blocked_id uuid,
  p_reason     text DEFAULT 'Blocked by user'
)
RETURNS void AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF auth.uid() = p_blocked_id THEN
    RAISE EXCEPTION 'Cannot block yourself';
  END IF;

  INSERT INTO public.blocked_users (blocker_id, blocked_id)
  VALUES (auth.uid(), p_blocked_id)
  ON CONFLICT (blocker_id, blocked_id) DO NOTHING;

  INSERT INTO public.reports (reporter_id, reported_type, reported_id, reason)
  VALUES (auth.uid(), 'user', p_blocked_id::text, p_reason)
  ON CONFLICT DO NOTHING;

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  SELECT a.user_id,
         '🚫 User blocked and reported.',
         'Reason: "' || left(p_reason, 100) || '"',
         'content_report',
         p_blocked_id::text
  FROM public.admins a;

  DELETE FROM public.follows
    WHERE (follower_id = auth.uid() AND following_id = p_blocked_id)
       OR (follower_id = p_blocked_id AND following_id = auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
