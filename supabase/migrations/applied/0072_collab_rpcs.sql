-- ============================================================
-- MIGRATION 0072: Collaborative quest RPCs (v2 — groups)
-- ============================================================

-- Drop old pair-based functions
DROP FUNCTION IF EXISTS public.create_collab_invite(uuid);
DROP FUNCTION IF EXISTS public.get_collab_invite_details(text);
DROP FUNCTION IF EXISTS public.join_collab_quest(text);
DROP FUNCTION IF EXISTS public.get_collab_status(uuid);

-- 1. Create a collab group for the caller's active quest
CREATE OR REPLACE FUNCTION public.create_collab_group(p_user_quest_id uuid, p_mode text DEFAULT 'with')
RETURNS json AS $$
DECLARE
  v_uq     public.user_quests;
  v_code   text;
  v_group  public.collab_groups;
BEGIN
  IF p_mode NOT IN ('with', 'versus') THEN
    RAISE EXCEPTION 'Mode must be "with" or "versus"';
  END IF;

  SELECT * INTO v_uq FROM public.user_quests
    WHERE id = p_user_quest_id AND user_id = auth.uid()
      AND status IN ('assigned', 'submitted');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No active quest found or not your quest';
  END IF;

  -- Already in a group for this quest?
  IF EXISTS (
    SELECT 1 FROM public.collab_group_members
    WHERE user_quest_id = p_user_quest_id
  ) THEN
    -- Return existing group info
    SELECT g.* INTO v_group FROM public.collab_groups g
    JOIN public.collab_group_members m ON m.group_id = g.id
    WHERE m.user_quest_id = p_user_quest_id LIMIT 1;
    RETURN json_build_object('group_id', v_group.id, 'code', v_group.code,
                             'mode', v_group.mode, 'expires_at', v_group.expires_at);
  END IF;

  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  INSERT INTO public.collab_groups (quest_id, creator_id, code, mode, expires_at)
  VALUES (v_uq.quest_id, auth.uid(), v_code, p_mode, v_uq.expires_at)
  RETURNING * INTO v_group;

  -- Add creator as first member
  INSERT INTO public.collab_group_members (group_id, user_id, user_quest_id)
  VALUES (v_group.id, auth.uid(), p_user_quest_id);

  RETURN json_build_object('group_id', v_group.id, 'code', v_group.code,
                           'mode', v_group.mode, 'expires_at', v_group.expires_at);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Preview a group by code (before joining)
CREATE OR REPLACE FUNCTION public.get_collab_group_details(p_code text)
RETURNS json AS $$
DECLARE
  v_group  public.collab_groups;
  v_members json;
  v_result json;
BEGIN
  SELECT * INTO v_group FROM public.collab_groups
    WHERE code = upper(p_code) AND status = 'open' AND expires_at > now();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Group not found or expired';
  END IF;

  -- Build member list
  SELECT json_agg(json_build_object(
    'user_id', p.id,
    'username', p.username,
    'display_name', p.display_name,
    'avatar_url', p.avatar_url
  )) INTO v_members
  FROM public.collab_group_members m
  JOIN public.profiles p ON p.id = m.user_id
  WHERE m.group_id = v_group.id;

  SELECT json_build_object(
    'group_id', v_group.id,
    'code', v_group.code,
    'mode', v_group.mode,
    'status', v_group.status,
    'member_count', (SELECT count(*) FROM public.collab_group_members WHERE group_id = v_group.id),
    'max_members', v_group.max_members,
    'expires_at', v_group.expires_at,
    'members', COALESCE(v_members, '[]'::json),
    'quest_title', q.title,
    'quest_description', q.description,
    'quest_category', q.category,
    'quest_difficulty', q.difficulty,
    'quest_xp_reward', q.xp_reward,
    'quest_duration_hours', COALESCE(q.duration_hours, 4),
    'creator_username', cp.username,
    'creator_display_name', cp.display_name,
    'creator_avatar_url', cp.avatar_url
  ) INTO v_result
  FROM public.quests q
  JOIN public.profiles cp ON cp.id = v_group.creator_id
  WHERE q.id = v_group.quest_id;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;


-- 3. Join a collab group
CREATE OR REPLACE FUNCTION public.join_collab_group(p_code text)
RETURNS json AS $$
DECLARE
  v_group       public.collab_groups;
  v_member_count integer;
  v_new_uq_id   uuid;
  v_joiner_name text;
BEGIN
  SELECT * INTO v_group FROM public.collab_groups
    WHERE code = upper(p_code) AND status = 'open' AND expires_at > now()
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Group not found or expired';
  END IF;

  -- Already a member?
  IF EXISTS (
    SELECT 1 FROM public.collab_group_members
    WHERE group_id = v_group.id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'You are already in this group';
  END IF;

  -- Check capacity
  SELECT count(*) INTO v_member_count FROM public.collab_group_members WHERE group_id = v_group.id;
  IF v_member_count >= v_group.max_members THEN
    RAISE EXCEPTION 'Group is full (%/% members)', v_member_count, v_group.max_members;
  END IF;

  -- Block if joiner has an active quest
  IF EXISTS (
    SELECT 1 FROM public.user_quests
    WHERE user_id = auth.uid() AND status IN ('assigned', 'submitted')
  ) THEN
    RAISE EXCEPTION 'You already have an active quest. Abandon it first.';
  END IF;

  -- Create user_quest with SAME timer as the group
  INSERT INTO public.user_quests (user_id, quest_id, status, assigned_at, expires_at)
  VALUES (auth.uid(), v_group.quest_id, 'assigned', now(), v_group.expires_at)
  RETURNING id INTO v_new_uq_id;

  -- Add as member
  INSERT INTO public.collab_group_members (group_id, user_id, user_quest_id)
  VALUES (v_group.id, auth.uid(), v_new_uq_id);

  -- Close group if now full
  IF v_member_count + 1 >= v_group.max_members THEN
    UPDATE public.collab_groups SET status = 'closed' WHERE id = v_group.id;
  END IF;

  -- Notify all existing members
  SELECT COALESCE(display_name, username) INTO v_joiner_name
    FROM public.profiles WHERE id = auth.uid();

  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  SELECT m.user_id,
         v_joiner_name || ' joined your quest!',
         v_joiner_name || ' joined the group quest',
         'collab_joined',
         v_group.id::text
  FROM public.collab_group_members m
  WHERE m.group_id = v_group.id AND m.user_id != auth.uid();

  RETURN json_build_object(
    'group_id', v_group.id,
    'user_quest_id', v_new_uq_id,
    'quest_id', v_group.quest_id,
    'expires_at', v_group.expires_at,
    'mode', v_group.mode
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. Get full group status for a user_quest
CREATE OR REPLACE FUNCTION public.get_collab_group_status(p_user_quest_id uuid)
RETURNS json AS $$
DECLARE
  v_group_id uuid;
  v_group    public.collab_groups;
  v_members  json;
BEGIN
  SELECT m.group_id INTO v_group_id
    FROM public.collab_group_members m
    WHERE m.user_quest_id = p_user_quest_id;

  IF NOT FOUND THEN
    RETURN json_build_object('is_collab', false);
  END IF;

  SELECT * INTO v_group FROM public.collab_groups WHERE id = v_group_id;

  SELECT json_agg(json_build_object(
    'user_id', p.id,
    'username', p.username,
    'display_name', p.display_name,
    'avatar_url', p.avatar_url,
    'quest_status', uq.status,
    'submission_status', s.status,
    'submission_time_seconds', m.submission_time_seconds,
    'vote_count', COALESCE(vc.cnt, 0)
  ) ORDER BY m.joined_at) INTO v_members
  FROM public.collab_group_members m
  JOIN public.profiles p ON p.id = m.user_id
  JOIN public.user_quests uq ON uq.id = m.user_quest_id
  LEFT JOIN public.submissions s ON s.user_quest_id = m.user_quest_id
  LEFT JOIN (
    SELECT submission_id, count(*) AS cnt FROM public.collab_votes
    WHERE group_id = v_group_id GROUP BY submission_id
  ) vc ON vc.submission_id = s.id
  WHERE m.group_id = v_group_id;

  RETURN json_build_object(
    'is_collab', true,
    'group_id', v_group.id,
    'mode', v_group.mode,
    'status', v_group.status,
    'code', v_group.code,
    'max_members', v_group.max_members,
    'expires_at', v_group.expires_at,
    'members', COALESCE(v_members, '[]'::json)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;


-- 5. Abandon quest (unchanged)
CREATE OR REPLACE FUNCTION public.abandon_quest(p_user_quest_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE public.user_quests
  SET status = 'expired', completed_at = now()
  WHERE id = p_user_quest_id
    AND user_id = auth.uid()
    AND status = 'assigned';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cannot abandon: quest not found or not in assigned status';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 6. Vote on a submission (VERSUS mode)
CREATE OR REPLACE FUNCTION public.vote_collab(p_group_id uuid, p_submission_id uuid)
RETURNS void AS $$
DECLARE
  v_group public.collab_groups;
  v_sub_owner uuid;
BEGIN
  SELECT * INTO v_group FROM public.collab_groups WHERE id = p_group_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Group not found';
  END IF;

  IF v_group.mode != 'versus' THEN
    RAISE EXCEPTION 'Voting is only available in VERSUS mode';
  END IF;

  -- Get submission owner
  SELECT user_id INTO v_sub_owner FROM public.submissions WHERE id = p_submission_id;
  IF v_sub_owner = auth.uid() THEN
    RAISE EXCEPTION 'Cannot vote for your own submission';
  END IF;

  -- Insert (unique constraint prevents double voting)
  INSERT INTO public.collab_votes (group_id, voter_id, submission_id)
  VALUES (p_group_id, auth.uid(), p_submission_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Grants
GRANT EXECUTE ON FUNCTION public.create_collab_group(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_collab_group_details(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_collab_group(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_collab_group_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.abandon_quest(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vote_collab(uuid, uuid) TO authenticated;
