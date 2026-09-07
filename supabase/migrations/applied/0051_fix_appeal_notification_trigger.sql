-- ============================================================
-- MIGRATION 0051: Fix appeal notification trigger
-- The original trigger in 0036 checks for rejected → 'submitted',
-- but appeals set status to 'pending'. Fix to match actual behavior.
-- ============================================================

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

  -- New submission (INSERT) → notify all admins
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

  -- Appeal: status changes from 'rejected' → 'pending' (with appealed = true)
  IF TG_OP = 'UPDATE'
     AND old.status = 'rejected'
     AND new.status = 'pending' THEN
    FOR v_admin IN
      SELECT user_id FROM public.admins
    LOOP
      INSERT INTO public.notifications (user_id, title, body, type, reference_id)
      VALUES (
        v_admin.user_id,
        'Appeal Submitted',
        v_submitter_name || ' appealed a rejected submission',
        'appeal_submitted',
        new.id::text
      );
    END LOOP;
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
