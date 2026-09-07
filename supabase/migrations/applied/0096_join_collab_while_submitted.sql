-- ============================================================
-- MIGRATION 0093: Allow joining a collab/versus group while a
-- previous quest is still in 'submitted' (pending review) status.
--
-- Background:
--   0045 + 0046 already established that 'submitted' quests must
--   NOT block new quest assignments — only an active 'assigned'
--   quest blocks. The collab join_collab_group RPC (0072) was the
--   one outlier that still raised on 'submitted', forcing the
--   client to call abandon_quest, which itself only handles
--   'assigned' → "Cannot abandon: quest not found or not in
--   assigned status" (P0001).
--
--   This migration brings join_collab_group in line with the rest
--   of the codebase: only block on 'assigned'. The newly created
--   collab user_quest stacks alongside the existing submitted one
--   (the unique index idx_one_active_quest_per_user is already
--   scoped to status='assigned' since 0045, so this is safe).
-- ============================================================

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

  -- Block ONLY if joiner has an in-progress (assigned) quest.
  -- 'submitted' quests are pending admin review and may stack
  -- alongside a new collab quest (matches assign_random_quest).
  IF EXISTS (
    SELECT 1 FROM public.user_quests
    WHERE user_id = auth.uid() AND status = 'assigned'
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

GRANT EXECUTE ON FUNCTION public.join_collab_group(text) TO authenticated;
