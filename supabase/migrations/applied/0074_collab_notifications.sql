-- ============================================================
-- MIGRATION 0074: Collab notification trigger (v2 — groups)
-- When a group member's submission is approved, notify ALL
-- other members in the group.
-- ============================================================

DROP TRIGGER IF EXISTS on_collab_submission_approved ON public.submissions;
DROP FUNCTION IF EXISTS public.notify_collab_partner_on_approval();

CREATE OR REPLACE FUNCTION public.notify_collab_group_on_approval()
RETURNS trigger AS $$
DECLARE
  v_group_id    uuid;
  v_approver_name text;
BEGIN
  IF NEW.status != 'approved' OR OLD.status != 'pending' THEN
    RETURN NEW;
  END IF;

  -- Find the group this submission belongs to
  SELECT m.group_id INTO v_group_id
    FROM public.collab_group_members m
    WHERE m.user_quest_id = NEW.user_quest_id;

  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(display_name, username) INTO v_approver_name
    FROM public.profiles WHERE id = NEW.user_id;

  -- Notify all other group members
  INSERT INTO public.notifications (user_id, title, body, type, reference_id)
  SELECT m.user_id,
         v_approver_name || '''s quest was approved!',
         'Your group quest partner''s submission was approved',
         'collab_partner_approved',
         NEW.id::text
  FROM public.collab_group_members m
  WHERE m.group_id = v_group_id AND m.user_id != NEW.user_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_collab_group_submission_approved
  AFTER UPDATE OF status ON public.submissions
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_collab_group_on_approval();
